# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check the approved provisional clock-enable ratios and raster contract."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    cases = [
        ("clock_enables", ["rtl/rabbitpunch_clock_enables.vhd", "sim/board/clock_enables_tb.vhd"], "clock_enables_tb", "CLOCK_ENABLES_PASS", ()),
        ("raster_small", ["rtl/rabbitpunch_clock_enables.vhd", "rtl/rabbitpunch_raster.vhd", "sim/video/raster_tb.vhd"], "raster_tb", "RASTER_PASS", ("-gSMALL_MODE=true",)),
        ("raster_nominal", ["rtl/rabbitpunch_clock_enables.vhd", "rtl/rabbitpunch_raster.vhd", "sim/video/raster_tb.vhd"], "raster_tb", "RASTER_PASS", ()),
    ]
    results = []
    for name, sources, top, marker, sim_args in cases:
        hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
        result = run_case(name, sources, top, "30 ms", marker, sim_args=sim_args, wall_timeout=180)
        assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}, "Sources changed during raster test"
        result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                      scope="Provisional enable ratios and parameterized beam contract only: no PLL, game/render integration, original-board timing measurement or physical output proof")
        results.append(result)
    (root / "docs/reference/raster_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
