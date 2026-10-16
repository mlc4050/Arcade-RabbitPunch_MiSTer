"""Checks of VHDL tile adapters around the unchanged JTFRAME drawer."""
import hashlib
import json
import struct

from coretools import core_root
from run_baselines import run_case
from png_rgb import write_rgb


def capture_vectors(root, fixture):
    game, capture_name = fixture["set"], fixture["capture"]
    capture = root / capture_name
    name = "tiles_" + capture.name.replace("-", "_")
    run_dir = root / "debug/baselines" / name
    run_dir.mkdir(parents=True, exist_ok=True)
    raw_vram = (capture / "videoram.bin").read_bytes()
    vram = struct.unpack(">8192H", raw_vram)
    registers = (capture / "reg_vregs.bin").read_bytes()
    flags = int.from_bytes(registers[12:14], "big")
    scroll = [int.from_bytes(registers[offset:offset+2], "big") & 511 for offset in (0, 2, 4, 6)]
    (run_dir / "vram.hex").write_text("".join(f"{value:04x}\n" for value in vram), encoding="ascii")
    (run_dir / "settings.hex").write_text("".join(f"{value:04x}\n" for value in [flags, *scroll]), encoding="ascii")
    graphics = [(root / "debug/rom_regions" / game / f"{region}.bin").read_bytes()
                for region in ("tiles1", "tiles2")]
    for layer, data in enumerate(graphics):
        if len(data) != 0x80000:
            raise SystemExit("Unexpected tile ROM size")
        (run_dir / f"tiles{layer}.hex").write_text(
            "".join(f"{value[0]:08x}\n" for value in struct.iter_unpack("<I", data)), encoding="ascii")
    expected = []
    # Independent per-pixel sampling of the MAME tile layout. The HDL emits
    # queued eight-pixel bursts and must crop their edges to the same viewport.
    for layer in range(2):
        for y in range(216):
            sy = (y + scroll[layer*2]) & 511
            for x in range(8, 296):
                sx = (x + scroll[layer*2+1]) & 511
                entry = vram[layer*4096 + (sx//8)*64 + sy//8]
                code = (entry & 0xfff) | 0x2000 if flags & (0x400 << layer) else entry & 0x1fff
                value = graphics[layer][code*32 + (sy%8)*4 + (sx%8)//2]
                pen = value >> (4*(sx%2)) & 15
                color = ((flags & (0x10 << layer)) >> (1+layer)) | (entry >> 13)
                index = layer*256 + color*16 + pen
                expected.append(index | (int(not (layer and pen == 15)) << 9))
    (run_dir / "expected.hex").write_text("".join(f"{value:03x}\n" for value in expected), encoding="ascii")
    return name, run_dir, capture


def capture_preview(run_dir, capture):
    actual = [int(line, 16) for line in (run_dir / "pixels.hex").read_text().splitlines()
              if line.strip() and not line.startswith("//")]
    if len(actual) != 124416:
        raise SystemExit("Incomplete HDL tile pixel dump")
    palette = struct.unpack(">1024H", (capture / "palette.bin").read_bytes())
    indices = [actual[index+62208] & 511 if actual[index+62208] & 512 else actual[index] & 511
               for index in range(62208)]
    colors = [bytes(((value >> shift & 31) << 3) | (value >> shift & 31) >> 2
                    for shift in (10, 5, 0)) for value in palette]
    write_rgb(run_dir / "tiles.png", 288, 216, b"".join(colors[index] for index in indices))


def main():
    root = core_root()
    manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
    for item in manifest["files"]:
        if item["target"] == "rtl/jtframe/jtframe_draw.v":
            if hashlib.sha256((root / item["target"]).read_bytes()).hexdigest() != item["sha256"]:
                raise SystemExit("JTFRAME drawer differs from its pinned upstream version")
            break
    else:
        raise SystemExit("JTFRAME drawer provenance is missing")
    results = [run_case("video_tile_row", ["rtl/jtframe/jtframe_draw.v",
                       "rtl/rabbitpunch_tile_row.vhd", "sim/video/tile_test_support.vhd",
                       "sim/video/tile_row_tb.vhd"],
                       "tile_row_tb", "20 ms", "TILE_ROW_PASS")]
    results.append(run_case("video_tile_layer", ["rtl/jtframe/jtframe_draw.v",
                   "rtl/rabbitpunch_tile_row.vhd", "rtl/rabbitpunch_tile_lookup.vhd",
                   "rtl/rabbitpunch_tile_layer.vhd", "sim/video/tile_test_support.vhd",
                   "sim/video/tile_layer_tb.vhd"],
                   "tile_layer_tb", "20 ms", "TILE_LAYER_PASS"))
    fixtures = json.loads((root / "scripts/mame/video_fixtures.json").read_text())
    for fixture in fixtures:
        name, run_dir, capture = capture_vectors(root, fixture)
        result = run_case(name, ["rtl/jtframe/jtframe_draw.v", "rtl/rabbitpunch_tile_row.vhd",
                          "rtl/rabbitpunch_tile_lookup.vhd", "rtl/rabbitpunch_tile_layer.vhd",
                          "sim/video/tile_test_support.vhd", "sim/video/tile_layer_tb.vhd",
                          "sim/video/tile_capture_tb.vhd"], "tile_capture_tb", "20 ms", "TILE_CAPTURE_PASS")
        capture_preview(run_dir, capture)
        result.update(set=fixture["set"], capture=fixture["capture"], layer_pixels=124416,
                      vram_sha256=hashlib.sha256((capture / "videoram.bin").read_bytes()).hexdigest(),
                      registers_sha256=hashlib.sha256((capture / "reg_vregs.bin").read_bytes()).hexdigest(),
                      rtl_pixels_sha256=hashlib.sha256((run_dir / "pixels.hex").read_bytes()).hexdigest(),
                      scope="HDL tile layers; captured RAM and behavioral ROM responders, no sprites/bitmap/raster")
        results.append(result)
    for result in results:
        result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
    (root / "docs/reference/tile_checks.json").write_text(
        json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
