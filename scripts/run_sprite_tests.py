"""VHDL/JTFRAME sprite-row checks against the pinned MAME graphics layout."""
import hashlib
import itertools
import json
import struct

from coretools import core_root
from run_baselines import run_case


def sprite_pen(graphics, code, row, pixel):
    # Independent direct sampling of MAME splayout (rpunch.cpp), also checked
    # against complete MAME screenshots by render_reference.py.
    byte = graphics[code * 256 + row * 8 + (pixel // 4) * 2 + 1 - (pixel % 4) // 2]
    return byte >> (4 * (pixel % 2)) & 15


def run_vectors(root, name, graphics, rows):
    directory = root / "debug/baselines" / name
    directory.mkdir(parents=True, exist_ok=True)
    assert len(graphics) == 0x80000 and len(rows) >= 3
    packets, expected = [], []
    for code, row, x, y, palette, horizontal, vertical, behind, delay in rows:
        packets.append(code | row << 11 | x << 16 | y << 25 | palette << 34 |
                       horizontal << 38 | vertical << 39 | behind << 40 | delay << 41)
        for pixel in range(16):
            source_x = 15 - pixel if horizontal else pixel
            source_y = 31 - row if vertical else row
            expected.append(768 + palette * 16 + sprite_pen(graphics, code, source_y, source_x))
    (directory / "count.hex").write_text(f"{len(rows):08x}\n", encoding="ascii")
    (directory / "rows.hex").write_text("".join(f"{item:016x}\n" for item in packets), encoding="ascii")
    (directory / "expected.hex").write_text("".join(f"{item:03x}\n" for item in expected), encoding="ascii")
    (directory / "sprites.hex").write_text(
        "".join(f"{item[0]:08x}\n" for item in struct.iter_unpack("<I", graphics)), encoding="ascii")
    result = run_case(name, ["rtl/jtframe/jtframe_draw.v", "rtl/rabbitpunch_sprite_row.vhd",
                            "sim/video/tile_test_support.vhd", "sim/video/sprite_row_tb.vhd"],
                      "sprite_row_tb", "60 ms", "SPRITE_ROW_PASS", wall_timeout=180)
    result.update(rows=len(rows), compared_pixels=len(expected),
                  graphics_sha256=hashlib.sha256(graphics).hexdigest(),
                  vectors_sha256=hashlib.sha256((directory / "rows.hex").read_bytes()).hexdigest(),
                  expected_sha256=hashlib.sha256((directory / "expected.hex").read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  scope="Native sprite rows only; no list scheduling, sprite overlap, foreground mixing or raster")
    return result


def main():
    root = core_root()
    manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
    donor = next(item for item in manifest["files"] if item["target"] == "rtl/jtframe/jtframe_draw.v")
    assert hashlib.sha256((root / donor["target"]).read_bytes()).hexdigest() == donor["sha256"]
    synthetic = bytearray(0x80000)
    for code in range(2048):
        for row in range(32):
            for pixel in range(16):
                offset = code * 256 + row * 8 + (pixel // 4) * 2 + 1 - (pixel % 4) // 2
                synthetic[offset] |= ((code + 3 * row + pixel) & 15) << (4 * (pixel % 2))
    rows = []
    for code, row, palette, horizontal, vertical, delay in itertools.product(
            (0, 1, 1023, 1024, 2047), range(32), range(16), range(2), range(2), (0, 3, 11)):
        rows.append((code, row, 508 if palette & 1 else 32, (code + row + palette) & 511,
                     palette, horizontal, vertical, (palette + row) & 1, delay))
    results = [run_vectors(root, "video_sprite_row", bytes(synthetic), rows)]
    for fixture in json.loads((root / "scripts/mame/video_fixtures.json").read_text()):
        capture = root / fixture["capture"]
        graphics = (root / "debug/rom_regions" / fixture["set"] / "sprites.bin").read_bytes()
        registers = (capture / "reg_vregs.bin").read_bytes()
        flags = int.from_bytes(registers[12:14], "big")
        count, priority = registers[17] & 63, registers[19] & 63
        descriptors = struct.unpack(">2048H", (capture / "spriteram.bin").read_bytes())
        rows = []
        for slot in reversed(range(count)):
            data0, data1, data2, _ = descriptors[slot * 4:slot * 4 + 4]
            for row in range(32):
                rows.append((data1 & 0x7ff, row, ((data2 & 511) + 8) & 511,
                             (513 - (data0 & 511) + row) & 511,
                             (data1 >> 13) | ((flags & 0x40) >> 3),
                             int(bool(data1 & 0x1000)), int(bool(data1 & 0x800)),
                             int(slot < priority), (0, 3, 11)[row % 3]))
        result = run_vectors(root, "sprites_" + capture.name.replace("-", "_"), graphics, rows)
        result.update(set=fixture["set"], capture=fixture["capture"], sprite_count=count,
                      descriptors_sha256=hashlib.sha256((capture / "spriteram.bin").read_bytes()).hexdigest())
        results.append(result)
    (root / "docs/reference/sprite_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
