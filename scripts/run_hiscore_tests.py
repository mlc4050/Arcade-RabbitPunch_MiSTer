# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Atomic score-store tests from pinned live-MAME initialization captures."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
out = root / 'debug/baselines/hiscore'
out.mkdir(parents=True, exist_ok=True)
reference = json.loads((root / 'docs/reference/hiscore_reference.json').read_text())
parts = []
for row in reference:
    initial = (root / 'debug/hiscore_reference' / row['set'] / 'initial.bin').read_bytes()
    assert hashlib.sha256(initial).hexdigest() == row['initial_sha256']
    # Saved sentinels may change after play; they gate initialization only.
    saved = bytes(value ^ ((index * 17 + 0x5a) & 255) for index, value in enumerate(initial))
    parts += [initial, saved]
(out / 'scores.hex').write_text(''.join(f'{value:02x}\n' for part in parts for value in part))
sources = ['rtl/rabbitpunch_ram8.vhd', 'rtl/rabbitpunch_ram16.vhd',
    'rtl/rabbitpunch_maintenance.vhd', 'rtl/rabbitpunch_hiscore.vhd', 'sim/board/hiscore_tb.vhd']
result = run_case('hiscore', sources, 'hiscore_tb', '5 ms', 'HISCORE_PASS')
result.update(source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources},
    vectors_sha256=hashlib.sha256((out / 'scores.hex').read_bytes()).hexdigest(),
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Atomic saved-score banks with native dual-port RAM and production maintenance byte adapter, both captured MAME geometries. Backend pause confirmation and varying acknowledgment latency, initialization guards, changed saved guard bytes, exact restoration and neighbors, first run without a file, unchanged/changed captures, autosave request edges, malformed file rejection and reset debt. No HPS configuration parser, production platform composition or disk persistence claim.')
(root / 'docs/reference/hiscore_checks.json').write_text(json.dumps(result, indent=2) + '\n')
