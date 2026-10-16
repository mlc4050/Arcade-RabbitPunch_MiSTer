"""Native palette RAM RGB555, streaming and reset regression."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ["rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_palette_pixel.vhd", "sim/video/palette_pixel_tb.vhd"]
    result = run_case("video_palette_pixel", sources, "palette_pixel_tb", "5 ms", "PALETTE_PIXEL_PASS", wall_timeout=180)
    result.update(ram_values=65536, post_reset_pixels=2,
                  source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  ram_model="altera_mf.altsyncram BIDIR_DUAL_PORT")
    (root / "docs/reference/palette_pixel_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
