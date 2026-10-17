# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root = core_root()
results = []
for name, sources, top, marker, libraries in [
    ("reset_release", ["rtl/rabbitpunch_reset_release.vhd", "sim/board/reset_release_tb.vhd"], "reset_release_tb", "RESET_RELEASE_PASS", ()),
    ("pll", ["rtl/rabbitpunch_pll.vhd", "rtl/rabbitpunch_reset_release.vhd", "sim/board/pll_tb.vhd"], "pll_tb", "PLL_PASS", ("-L", "altera_lnsim_ver", "-L", "altera_ver", "-L", "lpm_ver")),
]:
    hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result = run_case(name, sources, top, "1 ms", marker, sim_args=libraries, wall_timeout=180)
    assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  scope="Reset release and installed Altera PLL behavioral model; no fitted PLL-counter, board electrical phase or hardware lock evidence")
    results.append(result)
(root / "docs/reference/pll_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
