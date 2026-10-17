# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ["rtl/rabbitpunch_clock_enables.vhd", "rtl/rabbitpunch_raster.vhd",
           "rtl/rabbitpunch_scanline_scheduler.vhd", "rtl/rabbitpunch_video_output.vhd",
           "rtl/rabbitpunch_scanout.vhd", "sim/video/scanout_tb.vhd"]
hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result = run_case("scanout", sources, "scanout_tb", "50 ms", "SCANOUT_PASS", wall_timeout=180)
assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
              scope="Continuous provisional raster/scheduler/output with 2557-cycle row and four-edge RGB models; 124416 synthetic RGB checks, deliberate 4000-cycle deadline violation, live sync through readiness loss/recovery; no actual graphics, CPU, SDRAM or hardware output proof")
(root / "docs/reference/scanout_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
