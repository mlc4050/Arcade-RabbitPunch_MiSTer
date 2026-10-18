# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Run machine diagnostics on the installed Altera PLL model clock."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
from run_machine_tests import machine_sources
root = core_root()
sources = machine_sources()[:-1] + ['rtl/rabbitpunch_pll.vhd',
    'rtl/rabbitpunch_reset_release.vhd', 'rtl/rabbitpunch_clocked_machine.vhd',
    'sim/board/clocked_machine_tb.vhd']
hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
result = run_case('clocked_machine', sources, 'clocked_machine_tb', '1 ms',
    'CLOCKED_MACHINE_PASS', sim_args=('-L', 'altera_lnsim_ver', '-L', 'altera_ver', '-L', 'lpm_ver'), wall_timeout=300)
assert hashes == {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
result.update(source_sha256=hashes,
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Machine download/control/CPU diagnostics driven by installed vendor PLL behavioral model and production reset release; live horizontal cadence through gameplay resets. Before first vertical render; sound ROM absent/audio not scored; SDRAM command model samples the 5357 ps shifted external clock with the production read-window selection, no physical phase/electrical/fitted-counter or complete MiSTer proof')
(root / 'docs/reference/clocked_machine_checks.json').write_text(json.dumps(result, indent=2) + '\n')
