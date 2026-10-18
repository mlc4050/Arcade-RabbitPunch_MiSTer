# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare full HDL RGB through shared SDRAM chip commands against MAME."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path
from coretools import core_root
from png_rgb import read_rgb, write_rgb
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="capture basename; default all six, serial")
    parser.add_argument("--pll-clock", action="store_true", help="Use the vendor PLL and shifted chip clock")
    parser.add_argument('--phase-ps', type=int, default=10714, help='PLL chip-clock phase; nondefault phases use a private generated bench')
    args = parser.parse_args()
    if not 1 <= args.phase_ps < 21428 or (not args.pll_clock and args.phase_ps != 10714):
        parser.error('A phase inside one period requires --pll-clock')
    root = core_root()
    if (root / "debug/scanout_stop_requested").exists():
        raise SystemExit("STOPPED between capture cases for a source update; completed cases are retained")
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
    sources.remove("sim/video/video_sdram_capture_tb.vhd")
    sources += ["rtl/rabbitpunch_rom_cache.vhd", "rtl/rabbitpunch_clock_enables.vhd",
        "rtl/rabbitpunch_raster.vhd", "rtl/rabbitpunch_scanline_scheduler.vhd",
        "rtl/rabbitpunch_video_output.vhd", "rtl/rabbitpunch_scanout.vhd",
        "rtl/rabbitpunch_pll.vhd", "sim/video/scanout_capture_tb.vhd"]
    template = root / 'sim/video/scanout_capture_tb.vhd'
    template_hash = hashlib.sha256(template.read_bytes()).hexdigest()
    if args.pll_clock and args.phase_ps != 10714:
        generated = root / f'debug/phases/scanout_capture_{args.phase_ps}ps.vhd'
        generated.parent.mkdir(parents=True, exist_ok=True)
        text = template.read_text()
        marker_text = 'pll : entity work.rabbitpunch_pll\n            port map ('
        assert text.count(marker_text) == 1
        text = text.replace(marker_text, 'pll : entity work.rabbitpunch_pll\n            generic map (\n                GSTR_SDRAM_PHASE_SHIFT => "' + str(args.phase_ps) + ' ps"\n            )\n            port map (')
        if not generated.exists() or generated.read_text() != text:
            generated.write_text(text)
        sources[-1] = generated.relative_to(root).as_posix()
    top = "scanout_capture_tb"
    marker = "SCANOUT_CAPTURE_PASS"
    prefix = "scanout_pll_" if args.pll_clock else "scanout_capture_"
    if args.pll_clock and args.phase_ps != 10714:
        prefix = f"scanout_pll_{args.phase_ps}ps_"
    hashes = {p: hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
    reports = []
    for fixture in fixtures:
        capture = root / fixture["capture"]
        case = prefix + capture.name.replace("-", "_")
        directory = root / "debug/baselines" / case
        directory.mkdir(parents=True, exist_ok=True)
        for filename, capture_file in (("spriteram.hex", "spriteram.bin"), ("vram.hex", "videoram.bin"),
                                       ("bitmap.hex", "bitmap.bin"), ("palette.hex", "palette.bin")):
            words = struct.iter_unpack(">H", (capture / capture_file).read_bytes())
            (directory / filename).write_text("".join(f"{word:04x}\n" for (word,) in words))
        registers = (capture / "reg_vregs.bin").read_bytes()
        settings = [int.from_bytes(registers[12:14], "big")]
        settings += [int.from_bytes(registers[offset:offset+2], "big") & 511 for offset in (0, 2, 4, 6)]
        settings += [registers[17] & 63, registers[19] & 63]
        (directory / "video_settings.hex").write_text("".join(f"{word:04x}\n" for word in settings))
        regions = root / "debug/rom_regions" / fixture["set"]
        region_names = ("maincpu", "audiocpu", "tiles1", "tiles2", "sprites", "upd")
        expected_sizes = (0x40000, 0x10000, 0x80000, 0x80000, 0x80000, 0x40000)
        parts = [(regions / (name + ".bin")).read_bytes() for name in region_names]
        assert tuple(map(len, parts)) == expected_sizes
        image = b"".join(parts)
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
        libraries = [item for name in ("altera_lnsim_ver", "altera_ver", "lpm_ver") for item in ("-L", name)]
        result = run_case(case, sources, top, "80 ms", marker,
                          sim_args=libraries + (["-gGBOOL_PLL_CLOCK=true"] if args.pll_clock else []),
                          wall_timeout=1800, setup_commands=setup)
        assert hashes == {p: hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
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
            concurrent_cpu_rom_reads=int(re.search(r"rom_reads=\s*(\d+)", log)[1]),
            max_line_cycles=int(re.search(r"max_cycles=\s*(\d+)", log)[1]),
            expected_rgb_sha256=hashlib.sha256(expected).hexdigest(), actual_rgb_sha256=hashlib.sha256(actual).hexdigest(),
            rom_image_sha256=hashlib.sha256(image).hexdigest(),
            fixture_sha256={name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                for name in ("maincpu.hex", "video_settings.hex", "spriteram.hex", "vram.hex", "bitmap.hex", "palette.hex")},
            source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
            log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
            scope=(f"Vendor PLL and {args.phase_ps} ps shifted SDRAM clock with early runtime read capture; " if args.pll_clock else "Synthetic same-phase system/chip clock; ") + "Continuous provisional raster and real graphics/shared SDRAM command model; static MAME snapshot, synthetic RAM writes/ROM reads, direct ROM preload; no CPU execution or hardware/electrical timing proof")
        assert template_hash == hashlib.sha256(template.read_bytes()).hexdigest(), 'Bench template changed during simulation'
        result.update(sdram_phase_ps=args.phase_ps if args.pll_clock else 0, template_sha256=template_hash)
        result.update(pll_clock=args.pll_clock, sdram_read_capture_adjust=int(args.pll_clock),
            line_budget_cycles=3024, underflow=False,
            physical_sdram_bursts=int(re.search(r"bursts=\s*(\d+)", log)[1]))
        reports.append(result)
        print(f"PASS {case}: all 62208 RGB pixels identical to MAME through shared SDRAM", flush=True)
        (root / f"docs/reference/{prefix}{capture.name.replace(chr(45), chr(95))}_checks.json").write_text(json.dumps([result], indent=2) + "\n")
    if not args.only:
        (root / f"docs/reference/{prefix}checks.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
