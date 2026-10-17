# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check paused byte maintenance using real score geometry and native dual-port RAM."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
out = root / 'debug/baselines/maintenance_owner'
out.mkdir(parents=True, exist_ok=True)
reference = json.loads((root / 'docs/reference/hiscore_reference.json').read_text())
parts = []
for row in reference:
    initial = (root / 'debug/hiscore_reference' / row['set'] / 'initial.bin').read_bytes()
    assert hashlib.sha256(initial).hexdigest() == row['initial_sha256']
    saved = bytes(value if index in (0, len(initial) - 1) else value ^ ((index * 17 + 0x5a) & 255) for index, value in enumerate(initial))
    parts += [saved, saved]
(out / 'scores.hex').write_text(''.join(f'{value:02x}\n' for part in parts for value in part))
sources = ['rtl/rabbitpunch_ram16.vhd', 'rtl/rabbitpunch_maintenance.vhd', 'rtl/rabbitpunch_bus_owner.vhd', 'sim/board/maintenance_owner_tb.vhd']
result = run_case('maintenance_owner', sources, 'maintenance_owner_tb', '1 ms', 'MAINTENANCE_OWNER_PASS')
result.update(source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources},
    vectors_sha256=hashlib.sha256((out / 'scores.hex').read_bytes()).hexdigest(),
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Queued CPU/maintenance bus owner, byte adapter and native RAM, idle CPU pulse bypass with no extra request edge, simultaneous CPU priority, late CPU queued behind active maintenance, poisoned held payloads, explicit maintenance permission and qualified replies: both live-MAME score-block geometries, modified interior values, exact byte lanes/neighbors, actual-pause and CPU-debt gates, 0..51/300-cycle backend acknowledgment delay and reset debt drain. No production bus-owner mux, executing CPU or HPS persistence integration')
(root / 'docs/reference/maintenance_owner_checks.json').write_text(json.dumps(result, indent=2) + '\n')
