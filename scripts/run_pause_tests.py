# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Verify pause ownership and one toggle per button press without gating clocks."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/rabbitpunch_pause.vhd','sim/board/pause_tb.vhd']
result=run_case('pause',sources,'pause_tb','1 ms','PAUSE_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Pause-request logic only: one user toggle per rising press, held key/release, optional OSD pause, independent debug/state pause owners and reset while held; no clock gate, CPU-drain or new physical controls proof')
(root/'docs/reference/pause_checks.json').write_text(json.dumps(result,indent=2)+'\n')
