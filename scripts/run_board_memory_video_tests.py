"""CPU/video sharing tests against actual native board RAM."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd", "rtl/rabbitpunch_ram16.vhd",
               "rtl/rabbitpunch_board_memory.vhd", "sim/board/board_memory_video_tb.vhd"]
    result = run_case("board_memory_video", sources, "board_memory_video_tb", "5 ms", "BOARD_MEMORY_VIDEO_PASS", wall_timeout=180)
    result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  scope="Native BRAM access sharing at CPU transaction interface; no executing CPU, raster or SDRAM")
    (root / "docs/reference/board_memory_video_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
