"""Native bitmap RAM one-pixel-per-clock pipeline regression."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ["rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_bitmap_pixel.vhd", "sim/video/bitmap_pixel_tb.vhd"]
    result = run_case("video_bitmap_pixel", sources, "bitmap_pixel_tb", "5 ms", "BITMAP_PIXEL_PASS", wall_timeout=180)
    result.update(coordinates=131072, post_reset_pixels=2,
                  source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  ram_model="altera_mf.altsyncram BIDIR_DUAL_PORT")
    (root / "docs/reference/bitmap_pixel_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
