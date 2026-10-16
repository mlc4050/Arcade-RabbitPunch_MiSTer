"""Test actual native dual-port sprite line RAM, including bypass hazards."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    result = run_case("video_sprite_line", ["rtl/rabbitpunch_ram16.vhd",
                      "rtl/rabbitpunch_sprite_priority.vhd", "rtl/rabbitpunch_sprite_line.vhd",
                      "sim/video/tile_test_support.vhd", "sim/video/sprite_line_tb.vhd"],
                      "sprite_line_tb", "5 ms", "SPRITE_LINE_PASS", wall_timeout=180)
    result.update(log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  ram_model="altera_mf.altsyncram BIDIR_DUAL_PORT",
                  scope="Two native 512-entry sprite lines; synthetic candidates and concurrent opposite-bank reads; no integrated raster")
    (root / "docs/reference/sprite_line_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
