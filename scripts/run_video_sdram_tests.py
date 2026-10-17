"""Compare full HDL RGB through shared SDRAM chip commands against MAME."""
import argparse
import hashlib
import json
import re
import shutil
import struct
from pathlib import Path
from coretools import core_root
from png_rgb import read_rgb, write_rgb
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="capture basename; default all six, serial")
    parser.add_argument("--cached", action="store_true", help="retain one eight-byte ROM burst per client")
    args = parser.parse_args()
    root = core_root()
    fixtures = json.loads((root / "scripts/mame/video_fixtures.json").read_text())
    fixtures = [row for row in fixtures if not args.only or Path(row["capture"]).name == args.only]
    if not fixtures:
        raise SystemExit("No matching capture")
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
        "rtl/jtframe/jtframe_draw.v", "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_board_memory.vhd",
        "rtl/rabbitpunch_sprite_priority.vhd", "rtl/rabbitpunch_pixel_mixer.vhd",
        "rtl/rabbitpunch_tile_row.vhd", "rtl/rabbitpunch_tile_lookup.vhd", "rtl/rabbitpunch_tile_layer.vhd",
        "rtl/rabbitpunch_tiles.vhd", "rtl/rabbitpunch_sprite_scan.vhd", "rtl/rabbitpunch_sprite_row.vhd",
        "rtl/rabbitpunch_sprite_line.vhd", "rtl/rabbitpunch_sprites.vhd", "rtl/rabbitpunch_bitmap_pixel.vhd",
        "rtl/rabbitpunch_video.vhd", "rtl/rabbitpunch_palette_pixel.vhd", "rtl/rabbitpunch_rgb_video.vhd",
        "rtl/rabbitpunch_board_video.vhd", "rtl/rabbitpunch_sdram_types.vhd", "rtl/memory/sdram/sdram.sv",
        "rtl/rabbitpunch_sdram.vhd", "rtl/rabbitpunch_rom_requests.vhd",
        "sim/vendor/sdram/sdram_chip_model_wide.sv", "sim/video/tile_test_support.vhd",
        "sim/video/video_sdram_capture_tb.vhd"]
    top = "video_sdram_cached_capture_tb" if args.cached else "video_sdram_capture_tb"
    marker = "VIDEO_SDRAM_CACHE_CAPTURE_PASS" if args.cached else "VIDEO_SDRAM_CAPTURE_PASS"
    if args.cached:
        sources.remove("sim/video/video_sdram_capture_tb.vhd")
        sources += ["rtl/rabbitpunch_rom_cache.vhd", "sim/video/video_sdram_cached_capture_tb.vhd"]
    prefix = "video_sdram_cache_" if args.cached else "video_sdram_"
    reports = []
    for fixture in fixtures:
        capture = root / fixture["capture"]
        case = prefix + capture.name.replace("-", "_")
        directory = root / "debug/baselines" / case
        directory.mkdir(parents=True, exist_ok=True)
        previous = root / "debug/baselines" / ("video_" + capture.name.replace("-", "_"))
        # These files are independently checked against capture bytes below.
        for name in ("video_settings.hex", "spriteram.hex", "vram.hex", "bitmap.hex", "palette.hex"):
            shutil.copyfile(previous / name, directory / name)
        for filename, capture_file in (("spriteram.hex", "spriteram.bin"), ("vram.hex", "videoram.bin"),
                                       ("bitmap.hex", "bitmap.bin"), ("palette.hex", "palette.bin")):
            if (capture / capture_file).exists():
                actual = [int(word, 16) for word in (directory / filename).read_text().splitlines()]
                assert actual == [word[0] for word in struct.iter_unpack(">H", (capture / capture_file).read_bytes())]
        regions = root / "debug/rom_regions" / fixture["set"]
        region_names = ("maincpu", "audiocpu", "tiles1", "tiles2", "sprites", "upd")
        image = b"".join((regions / (name + ".bin")).read_bytes() for name in region_names)
        assert len(image) == 0x210000
        (directory / "maincpu.hex").write_text("".join(f"{word[0]:04x}\n" for word in
            struct.iter_unpack(">H", (regions / "maincpu.bin").read_bytes())))
        # Direct model preload avoids millions of simulated loader transactions.
        # Loader byte masks and physical writes are tested separately by sdram_tb.
        memory_file = directory / "rom_words.mti"
        with memory_file.open("w") as output:
            output.write("// memory data file (do not edit following line - required for mem load use)\n")
            output.write(f"// instance=/{top}/shared_roms/chip/mem\n")
            output.write("// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n")
            for index, (word,) in enumerate(struct.iter_unpack("<H", image)):
                output.write(f"{index:x}: {word:04x}\n")
        setup = [f"mem load -format mti -infile {{{memory_file.as_posix()}}} /{top}/shared_roms/chip/mem"]
        result = run_case(case, sources, top, "60 ms", marker,
                          wall_timeout=900, setup_commands=setup)
        pixels = [int(word, 16) for word in (directory / "pixels.hex").read_text().splitlines()]
        assert len(pixels) == 62208
        actual = b"".join(word.to_bytes(3, "big") for word in pixels)
        width, height, expected = read_rgb(capture / "reference.png")
        assert (width, height) == (288, 216)
        differing = sum(actual[n:n+3] != expected[n:n+3] for n in range(0, len(actual), 3))
        write_rgb(directory / "video.png", width, height, actual)
        assert differing == 0, f"{case}: {differing} RGB pixels differ from MAME"
        log = (root / result["log"]).read_text()
        result.update(capture=fixture["capture"], set=fixture["set"], pixels=62208, differing_pixels=0,
            concurrent_cpu_writes=int(re.search(r"cpu_writes=\s*(\d+)", log)[1]),
            concurrent_cpu_rom_reads=int(re.search(r"SDRAM_ROM_READS=\s*(\d+)", log)[1]),
            max_line_cycles=int(re.search(r"max_cycles=\s*(\d+)", log)[1]),
            expected_rgb_sha256=hashlib.sha256(expected).hexdigest(), actual_rgb_sha256=hashlib.sha256(actual).hexdigest(),
            rom_image_sha256=hashlib.sha256(image).hexdigest(),
            source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
            log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
            scope="Actual shared SDRAM controller/chip-command model feeding graphics and competing synthetic CPU ROM reads; native board RAM with CPU writes; direct ROM model preload, no loader/CPU execution/physical raster/electrical timing proof")
        result["burst_cache"] = args.cached
        if args.cached:
            result["physical_sdram_bursts"] = int(re.search(r"SDRAM_PHYSICAL_BURSTS=\s*(\d+)", log)[1])
        reports.append(result)
        print(f"PASS {case}: all 62208 RGB pixels identical to MAME through shared SDRAM", flush=True)
        (root / f"debug/{prefix}{capture.name}_checks.json").write_text(json.dumps([result], indent=2) + "\n")
    if not args.only:
        (root / f"docs/reference/{prefix}checks.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
