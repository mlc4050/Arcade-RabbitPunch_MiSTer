"""Check VHDL scanline candidate selection independently of pixel drawing."""
import hashlib
import argparse
import json
import re
import struct

from coretools import core_root
from run_baselines import run_case
from run_sprite_tests import sprite_pen


def run_vectors(root, name, ram, lines, graphics=None, line_ram=False, renderer=False):
    directory = root / "debug/baselines" / name
    directory.mkdir(parents=True, exist_ok=True)
    # A known intersecting one-sprite line is used for reset at each fetch phase.
    lines = [((513 - (ram[0] & 511)) & 511, 1, 1, 64), *lines]
    expected, addresses, offsets, packets = [], [], [], []
    for y, count, priority, flags in lines:
        packets.append(y | count << 9 | priority << 15 | flags << 21)
        offsets.append(len(expected) | len(addresses) << 32)
        for slot in reversed(range(count)):
            data0, data1, data2, _ = ram[slot * 4:slot * 4 + 4]
            addresses.append(slot * 4)
            local_row = (y - (513 - (data0 & 511))) & 511
            if local_row >= 32:
                continue
            addresses.extend((slot * 4 + 1, slot * 4 + 2))
            code = data1 & 0x7ff
            x = ((data2 & 511) + 8) & 511
            palette = ((data1 >> 13) & 7) | ((flags & 64) >> 3)
            expected.append(slot | code << 6 | local_row << 17 | x << 22 | y << 31 |
                            palette << 40 | int(bool(data1 & 0x1000)) << 44 |
                            int(bool(data1 & 0x800)) << 45 | int(slot < priority) << 46)
    def write(name, values, width):
        (directory / name).write_text("".join(f"{value:0{width}x}\n" for value in values), encoding="ascii")
    write("counts.hex", (len(lines), len(expected), len(addresses)), 8)
    write("lines.hex", packets, 16)
    write("offsets.hex", offsets, 16)
    write("expected.hex", expected, 16)
    write("addresses.hex", addresses, 3)
    write("ram.hex", ram, 4)
    sources = ["rtl/rabbitpunch_sprite_scan.vhd", "sim/video/tile_test_support.vhd",
               "rtl/jtframe/jtframe_draw.v", "rtl/rabbitpunch_sprite_row.vhd",
               "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_sprite_priority.vhd",
               "rtl/rabbitpunch_sprite_line.vhd"]
    top, marker = "sprite_scan_tb", "SPRITE_SCAN_PASS"
    if graphics is not None:
        write("sprites.hex", (item[0] for item in struct.iter_unpack("<I", graphics)), 8)
        pixels = []
        for command in expected:
            code, row = command >> 6 & 2047, command >> 17 & 31
            horizontal, vertical = command >> 44 & 1, command >> 45 & 1
            palette = command >> 40 & 15
            for pixel in range(16):
                pixels.append(768 + palette * 16 + sprite_pen(graphics, code,
                              31 - row if vertical else row, 15 - pixel if horizontal else pixel))
        write("pixels.hex", pixels, 3)
        if line_ram:
            entries = []
            for line_number in range(len(lines)):
                start = offsets[line_number] & 0xffffffff
                end = offsets[line_number+1] & 0xffffffff if line_number+1 < len(lines) else len(expected)
                line_entries = [0] * 512
                for row_number in range(start, end):
                    command = expected[row_number]
                    slot, x, behind = command & 63, command >> 22 & 511, command >> 46 & 1
                    for pixel in range(16):
                        palette = pixels[row_number*16 + pixel] & 255
                        address = (x+pixel) & 511
                        old = line_entries[address]
                        if palette & 15 != 15 and (not old & 0x8000 or slot > (old >> 8 & 63)):
                            line_entries[address] = 0x8000 | behind << 14 | slot << 8 | palette
                entries.extend(line_entries)
            write("line_entries.hex", entries, 4)
        top, marker = "sprite_scan_draw_tb", "SPRITE_SCAN_DRAW_PASS"
        if line_ram:
            top, marker = "sprite_scan_line_tb", "SPRITE_SCAN_LINE_PASS"
    if renderer:
        sources.extend(("rtl/rabbitpunch_sprites.vhd", "sim/video/sprite_renderer_tb.vhd"))
        top, marker = "sprite_renderer_tb", "SPRITE_RENDERER_PASS"
    else:
        sources.append("sim/video/sprite_scan_tb.vhd")
    if graphics is not None and not renderer:
        sources.append("sim/video/sprite_scan_line_tb.vhd" if line_ram else "sim/video/sprite_scan_draw_tb.vhd")
    result = run_case(name, sources, top, "120 ms", marker, wall_timeout=240)
    transcript = (root / result["log"]).read_text(encoding="utf-8")
    result.update(lines=len(lines), selected_rows=len(expected), ram_reads=len(addresses),
                  max_cycles=int(re.search(r"max_cycles=\s*(\d+)", transcript)[1]),
                  ram_sha256=hashlib.sha256(struct.pack(">2048H", *ram)).hexdigest(),
                  log_sha256=hashlib.sha256(transcript.encode()).hexdigest(),
                  scope="Static descriptor scan only; behavioral RAM and stalled row consumer; not a render deadline")
    if graphics is not None:
        result.update(compared_pixels=len(pixels), graphics_sha256=hashlib.sha256(graphics).hexdigest(),
                      scope="VHDL scan feeding JTFRAME row drawing; static RAM, independent RAM/ROM responders; no line RAM/mixing/shared arbitration")
        if line_ram:
            result.update(line_entries=len(entries),
                          scope="VHDL scan, actual JTFRAME row drawing and native two-bank sprite line RAM; static descriptors/independent responders; no raster or shared arbitration")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--draw", action="store_true", help="connect scan output to the real sprite-row drawer")
    parser.add_argument("--line", action="store_true", help="also store and compare every native sprite-line entry")
    parser.add_argument("--renderer", action="store_true", help="test the complete VHDL sprite-line controller")
    args = parser.parse_args()
    args.line = args.line or args.renderer
    args.draw = args.draw or args.line
    root = core_root()
    ram = [0] * 2048
    for slot in range(64):
        ram[slot * 4:slot * 4 + 4] = [
            ((slot * 37 + 1) & 511) | 0xa000,
            ((slot * 173) & 2047) | (slot % 4) << 11 | (slot % 8) << 13,
            ((slot * 29 + 499) & 511) | 0xc000, 0xffff]
    lines = [(y, count, priority, flags)
             for count, priority, flags in ((0, 63, 64), (1, 0, 0), (63, 1, 0), (63, 63, 64))
             for y in range(512)]
    graphics = None
    if args.draw:
        graphics = bytearray(0x80000)
        for code in range(2048):
            for row in range(32):
                for pixel in range(16):
                    offset = code * 256 + row * 8 + (pixel // 4) * 2 + 1 - (pixel % 4) // 2
                    graphics[offset] |= ((code + 3 * row + pixel) & 15) << (4 * (pixel % 2))
    prefix = "renderer_" if args.renderer else "line_" if args.line else "draw_" if args.draw else "scan_"
    results = [run_vectors(root, "video_sprite_" + prefix + "spread", ram, lines, graphics, args.line, args.renderer)]
    crowded = list(ram)
    for slot in range(64):
        crowded[slot * 4] = 1
    results.append(run_vectors(root, "video_sprite_" + prefix + "crowded", crowded, lines, graphics, args.line, args.renderer))
    for fixture in json.loads((root / "scripts/mame/video_fixtures.json").read_text()):
        capture = root / fixture["capture"]
        ram = struct.unpack(">2048H", (capture / "spriteram.bin").read_bytes())
        registers = (capture / "reg_vregs.bin").read_bytes()
        flags = int.from_bytes(registers[12:14], "big")
        lines = [(y, registers[17] & 63, registers[19] & 63, flags) for y in range(216)]
        if args.draw:
            graphics = (root / "debug/rom_regions" / fixture["set"] / "sprites.bin").read_bytes()
        result = run_vectors(root, prefix + capture.name.replace("-", "_"), ram, lines, graphics, args.line, args.renderer)
        result.update(set=fixture["set"], capture=fixture["capture"])
        results.append(result)
    report = "sprite_renderer_checks.json" if args.renderer else "sprite_scan_line_checks.json" if args.line else "sprite_scan_draw_checks.json" if args.draw else "sprite_scan_checks.json"
    (root / "docs/reference" / report).write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
