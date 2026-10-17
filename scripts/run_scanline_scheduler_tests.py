# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ["rtl/rabbitpunch_scanline_scheduler.vhd", "sim/video/scanline_scheduler_tb.vhd"]
hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result = run_case("scanline_scheduler", sources, "scanline_scheduler_tb", "100 us", "SCANLINE_SCHEDULER_PASS")
assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
              scope="Line-bank ownership with a delayed renderer model; no pixel RAM added, no physical timing, real renderer or CPU/SDRAM integration proof")
(root / "docs/reference/scanline_scheduler_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
