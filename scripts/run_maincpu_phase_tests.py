# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv", "rtl/cpu/fx68k/uaddrPla.sv",
           "rtl/rabbitpunch_bus.vhd", "rtl/rabbitpunch_fx68k.vhd", "rtl/rabbitpunch_maincpu.vhd",
           "rtl/rabbitpunch_clock_enables.vhd", "sim/board/maincpu_phase_tb.vhd"]
results = []
for name, generic in [("maincpu_fractional_phase", "true"), ("maincpu_legacy_phase", "false")]:
    hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result = run_case(name, sources, "maincpu_phase_tb", "3 ms", "MAINCPU_PHASE_PASS",
                      sim_args=(f"-gEXTERNAL_PHASE_ENABLE={generic}",), wall_timeout=180)
    assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result.update(external_phase_enable=generic == "true", source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
                  scope="Executing unchanged fx68k with fractional or legacy phase selection, variable-latency bus model, byte lanes, pause, reset replay and IRQ/autovector/handler; no game ROM or physical memory proof")
    results.append(result)
(root / "docs/reference/maincpu_phase_checks.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
