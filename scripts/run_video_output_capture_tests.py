"""Check actual mixed logical-line video against complete MAME screenshots."""
import argparse
import hashlib
import json
import re
import struct
from concurrent.futures import ThreadPoolExecutor
from coretools import core_root
from png_rgb import read_rgb, write_rgb
from run_baselines import run_case
from run_tile_tests import capture_vectors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="capture directory basename for a focused replay")
    parser.add_argument("--jobs", type=int, choices=(1, 2), default=1, help="independent simulator processes; default serial")
    args = parser.parse_args()
    root = core_root()
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
               "rtl/jtframe/jtframe_draw.v", "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_board_memory.vhd",
               "rtl/rabbitpunch_sprite_priority.vhd", "rtl/rabbitpunch_pixel_mixer.vhd",
               "rtl/rabbitpunch_tile_row.vhd", "rtl/rabbitpunch_tile_lookup.vhd",
               "rtl/rabbitpunch_tile_layer.vhd", "rtl/rabbitpunch_tiles.vhd",
               "rtl/rabbitpunch_sprite_scan.vhd", "rtl/rabbitpunch_sprite_row.vhd",
               "rtl/rabbitpunch_sprite_line.vhd", "rtl/rabbitpunch_sprites.vhd",
               "rtl/rabbitpunch_bitmap_pixel.vhd", "rtl/rabbitpunch_video.vhd",
               "rtl/rabbitpunch_palette_pixel.vhd", "rtl/rabbitpunch_rgb_video.vhd",
               "rtl/rabbitpunch_board_video.vhd",
               "sim/video/tile_test_support.vhd", "rtl/rabbitpunch_video_output.vhd", "sim/video/video_output_capture_tb.vhd"]
    def run_fixture(fixture):
        capture = root / fixture["capture"]
        name = "video_output_" + capture.name.replace("-", "_")
        directory = root / "debug/baselines" / name
        directory.mkdir(parents=True, exist_ok=True)
        _, tile_directory, _ = capture_vectors(root, fixture)
        for filename in ("vram.hex", "tiles0.hex", "tiles1.hex"):
            (directory / filename).write_bytes((tile_directory / filename).read_bytes())
        registers = (capture / "reg_vregs.bin").read_bytes()
        settings = [int.from_bytes(registers[12:14], "big")]
        settings.extend(int.from_bytes(registers[offset:offset+2], "big") & 511 for offset in (0, 2, 4, 6))
        settings.extend((registers[17] & 63, registers[19] & 63))
        (directory / "video_settings.hex").write_text("".join(f"{value:04x}\n" for value in settings), encoding="ascii")
        for filename, raw in (("spriteram.hex", (capture / "spriteram.bin").read_bytes()),
                              ("bitmap.hex", (capture / "bitmap.bin").read_bytes()),
                              ("palette.hex", (capture / "palette.bin").read_bytes())):
            (directory / filename).write_text("".join(f"{item[0]:04x}\n" for item in struct.iter_unpack(">H", raw)), encoding="ascii")
        graphics = (root / "debug/rom_regions" / fixture["set"] / "sprites.bin").read_bytes()
        (directory / "sprites.hex").write_text("".join(f"{item[0]:08x}\n" for item in struct.iter_unpack("<I", graphics)), encoding="ascii")
        result = run_case(name, sources, "video_output_capture_tb", "60 ms", "VIDEO_OUTPUT_CAPTURE_PASS", wall_timeout=600)
        pixels = [int(line, 16) for line in (directory / "pixels.hex").read_text().splitlines()]
        assert len(pixels) == 62208
        actual = b"".join(pixel.to_bytes(3, "big") for pixel in pixels)
        width, height, expected = read_rgb(capture / "reference.png")
        assert (width, height) == (288, 216)
        differing = sum(actual[offset:offset+3] != expected[offset:offset+3] for offset in range(0, len(actual), 3))
        write_rgb(directory / "video.png", 288, 216, actual)
        if differing:
            raise SystemExit(f"{name}: {differing} mixed RGB pixels differ from MAME")
        transcript = (root / result["log"]).read_text(encoding="utf-8")
        result.update(set=fixture["set"], capture=fixture["capture"], pixels=62208, differing_pixels=0,
                      concurrent_cpu_writes=int(re.search(r"cpu_writes=\s*(\d+)", transcript)[1]),
                      max_line_cycles=int(re.search(r"max_cycles=\s*(\d+)", transcript)[1]),
                      expected_rgb_sha256=hashlib.sha256(expected).hexdigest(), actual_rgb_sha256=hashlib.sha256(actual).hexdigest(),
                      source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
                      log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                      scope="Fixed-latency metadata/RGB output adapter and actual VHDL/JTFRAME rendering with shared native board RAM, CPU-interface fixture preload and concurrent work-RAM writes; static video contents/independent ROM channels, no CPU execution/shared SDRAM/physical raster")
        print(f"PASS {name}: all 62208 actual HDL RGB pixels identical to MAME", flush=True)
        return result
    fixtures = json.loads((root / "scripts/mame/video_fixtures.json").read_text())
    fixtures = [fixture for fixture in fixtures if not args.only or
                (root / fixture["capture"]).name == args.only]
    # Each fixture owns its simulator library, vectors, transcript and image.
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(run_fixture, fixtures))
    if not results:
        raise SystemExit("No matching video fixture")
    report = f"debug/video_{args.only}_checks.json" if args.only else "docs/reference/video_output_capture_checks.json"
    (root / report).write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
