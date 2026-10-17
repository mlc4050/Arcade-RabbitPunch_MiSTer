# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check every mapped RAM word without simulator memory deposits."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
               "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_board_memory.vhd",
               "rtl/rabbitpunch_memory.vhd", "sim/memory/memory_powerup_tb.vhd"]
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result = run_case("memory_powerup", sources, "memory_powerup_tb", "10 ms",
                      "MEMORY_POWERUP_PASS", wall_timeout=300)
    if hashes != {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}:
        raise SystemExit("Memory sources changed during simulation")
    result.update(source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  scope="All 52224 mapped RAM words read via CPU and inspection before any write; bitmap FFFF, other banks zero. Upper/lower masked writes at first/middle/last addresses preserve the other byte. No RAM deposits; no physical hardware measurement.")
    (root / "docs/reference/memory_powerup_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
