"""Replay both tile layers through actual VHDL/JTFRAME and native line RAM."""
import hashlib
import json
import re
import struct
from coretools import core_root
from run_baselines import run_case
from run_tile_tests import capture_vectors


def line_vectors(root, fixture, name):
    _, old_directory, capture = capture_vectors(root, fixture)
    directory = root / "debug/baselines" / name
    directory.mkdir(parents=True, exist_ok=True)
    for filename in ("settings.hex", "vram.hex", "tiles0.hex", "tiles1.hex"):
        (directory / filename).write_bytes((old_directory / filename).read_bytes())
    vram = struct.unpack(">8192H", (capture / "videoram.bin").read_bytes())
    registers = (capture / "reg_vregs.bin").read_bytes()
    flags = int.from_bytes(registers[12:14], "big")
    scroll = [int.from_bytes(registers[offset:offset+2], "big") & 511 for offset in (0, 2, 4, 6)]
    graphics = [(root / "debug/rom_regions" / fixture["set"] / f"tiles{layer+1}.bin").read_bytes()
                for layer in range(2)]
    entries = []
    for y in range(216):
        for x in range(512):
            packed = 0
            for layer in range(2):
                sx, sy = (x + scroll[layer*2+1]) & 511, (y + scroll[layer*2]) & 511
                entry = vram[layer*4096 + (sx//8)*64 + sy//8]
                code = (entry & 4095) | 8192 if flags & (0x400 << layer) else entry & 8191
                value = graphics[layer][code*32 + (sy%8)*4 + (sx%8)//2]
                pen = value >> (4*(sx%2)) & 15
                palette = (entry >> 13) | ((flags & (0x10 << layer)) >> (1+layer))
                packed |= (palette*16 + pen) << (layer*8)
            entries.append(packed)
    (directory / "line_entries.hex").write_text("".join(f"{item:04x}\n" for item in entries), encoding="ascii")
    return directory


def main():
    root = core_root()
    results = []
    for fixture in json.loads((root / "scripts/mame/video_fixtures.json").read_text()):
        name = "tile_line_" + fixture["capture"].split("/")[-1].replace("-", "_")
        line_vectors(root, fixture, name)
        result = run_case(name, ["rtl/jtframe/jtframe_draw.v", "rtl/rabbitpunch_ram16.vhd",
                          "rtl/rabbitpunch_tile_row.vhd", "rtl/rabbitpunch_tile_lookup.vhd",
                          "rtl/rabbitpunch_tile_layer.vhd", "rtl/rabbitpunch_tiles.vhd",
                          "sim/video/tile_test_support.vhd", "sim/video/tile_line_tb.vhd"],
                          "tile_line_tb", "60 ms", "TILE_LINE_PASS", wall_timeout=240)
        transcript = (root / result["log"]).read_text(encoding="utf-8")
        result.update(set=fixture["set"], capture=fixture["capture"], packed_pixels=216*512,
                      max_cycles=int(re.search(r"max_cycles=\s*(\d+)", transcript)[1]),
                      log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                      scope="VHDL/JTFRAME tile lookup/drawing and native packed two-bank line RAM; static descriptor/ROM responders, no raster/shared arbitration")
        results.append(result)
    (root / "docs/reference/tile_line_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
