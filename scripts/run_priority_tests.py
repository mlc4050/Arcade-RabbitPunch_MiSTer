"""Check sprite occupancy and layer mixing, including real MAME screenshots.

Graphics decoding is a software stimulus model here. Scan/row engines have
separate tests; this is not an integrated video-engine or hardware screenshot.
"""
import hashlib
import json
import struct

from coretools import core_root
from png_rgb import read_rgb, write_rgb
from run_baselines import run_case
from run_sprite_tests import sprite_pen


def vectors(root, fixture):
    capture = root / fixture["capture"]
    roms = root / "debug/rom_regions" / fixture["set"]
    registers = (capture / "reg_vregs.bin").read_bytes()
    flags = int.from_bytes(registers[12:14], "big")
    scroll = [int.from_bytes(registers[offset:offset+2], "big") & 511 for offset in (0, 2, 4, 6)]
    vram = struct.unpack(">8192H", (capture / "videoram.bin").read_bytes())
    layers = []
    for layer in range(2):
        graphics = (roms / f"tiles{layer+1}.bin").read_bytes()
        pixels = []
        for y in range(216):
            sy = (y + scroll[layer*2]) & 511
            for x in range(8, 296):
                sx = (x + scroll[layer*2+1]) & 511
                entry = vram[layer*4096 + (sx//8)*64 + sy//8]
                code = (entry & 0xfff) | 0x2000 if flags & (0x400 << layer) else entry & 0x1fff
                data = graphics[code*32 + (sy%8)*4 + (sx%8)//2]
                pen = data >> (4*(sx%2)) & 15
                color = (entry >> 13) | ((flags & (0x10 << layer)) >> (1+layer))
                pixels.append(color*16 + pen)
        layers.append(pixels)
    graphics = (roms / "sprites.bin").read_bytes()
    sprites = struct.unpack(">2048H", (capture / "spriteram.bin").read_bytes())
    candidates = [[] for _ in range(62208)]
    for slot in reversed(range(registers[17] & 63)):
        data0, data1, data2, _ = sprites[slot*4:slot*4+4]
        x, y = (data2 & 511) + 8, 513 - (data0 & 511)
        if x > 295:
            x -= 512
        if y > 215:
            y -= 512
        palette = (data1 >> 13) | ((flags & 64) >> 3)
        behind = int(slot < (registers[19] & 63))
        for dy in range(32):
            for dx in range(16):
                px, py = x + dx, y + dy
                if not (8 <= px < 296 and 0 <= py < 216):
                    continue
                pen = sprite_pen(graphics, data1 & 2047, 31-dy if data1 & 0x800 else dy,
                                 15-dx if data1 & 0x1000 else dx)
                candidates[py*288 + px-8].append(slot | (palette*16 + pen) << 6 | behind << 14)
    bitmap = (capture / "bitmap.bin").read_bytes()
    base, flattened = [], []
    for position, entries in enumerate(candidates):
        y, x = position // 288, position % 288 + 8
        source_x = (x + 4) & 511
        value = bitmap[y*256 + source_x//2]
        pen = value & 15 if source_x % 2 else value >> 4
        bitmap_index = (flags & 15)*16 + pen
        base.append(layers[0][position] | layers[1][position] << 8 | bitmap_index << 16 | len(entries) << 24)
        # The arbiter must reproduce MAME even when arrival order changes.
        flattened.extend(reversed(entries) if position & 1 else entries)
    return capture, base, flattened


def main():
    root = core_root()
    sources = ["rtl/rabbitpunch_sprite_priority.vhd", "rtl/rabbitpunch_pixel_mixer.vhd",
               "sim/video/tile_test_support.vhd"]
    results = [run_case("video_priority", sources + ["sim/video/priority_tb.vhd"],
                        "priority_tb", "1 ms", "PRIORITY_PASS")]
    for fixture in json.loads((root / "scripts/mame/video_fixtures.json").read_text()):
        capture, base, candidates = vectors(root, fixture)
        name = "mixer_" + capture.name.replace("-", "_")
        directory = root / "debug/baselines" / name
        directory.mkdir(parents=True, exist_ok=True)
        for filename, values, width in (("base.hex", base, 8), ("candidates.hex", candidates, 4),
                                        ("counts.hex", [len(candidates)], 8)):
            (directory / filename).write_text("".join(f"{value:0{width}x}\n" for value in values), encoding="ascii")
        result = run_case(name, sources + ["sim/video/mixer_capture_tb.vhd"],
                          "mixer_capture_tb", "1 ms", "MIXER_CAPTURE_PASS")
        indices = [int(line, 16) for line in (directory / "pixels.hex").read_text().splitlines()]
        assert len(indices) == 62208
        palette = struct.unpack(">1024H", (capture / "palette.bin").read_bytes())
        colors = [bytes(((value >> shift & 31) << 3) | (value >> shift & 31) >> 2
                        for shift in (10, 5, 0)) for value in palette]
        actual = b"".join(colors[index] for index in indices)
        width, height, expected = read_rgb(capture / "reference.png")
        assert (width, height) == (288, 216)
        differing = sum(actual[offset:offset+3] != expected[offset:offset+3] for offset in range(0, len(actual), 3))
        write_rgb(directory / "mixed.png", 288, 216, actual)
        if differing:
            raise SystemExit(f"{name}: {differing} RGB pixels differ from MAME")
        result.update(set=fixture["set"], capture=fixture["capture"], pixels=62208, differing_pixels=differing,
                      sprite_candidates=len(candidates), expected_rgb_sha256=hashlib.sha256(expected).hexdigest(),
                      actual_rgb_sha256=hashlib.sha256(actual).hexdigest(),
                      scope="VHDL sprite arbitration and mixer; software-decoded layer/ROM stimulus; not integrated row engines or raster")
        results.append(result)
        print(f"PASS {name}: all 62208 RGB pixels identical to MAME", flush=True)
    for result in results:
        result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
    (root / "docs/reference/priority_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
