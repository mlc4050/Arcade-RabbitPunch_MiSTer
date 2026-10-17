# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/rabbitpunch_maintenance_clients.vhd','sim/board/maintenance_clients_tb.vhd']
result=run_case('maintenance_clients',sources,'maintenance_clients_tb','100 us','MAINTENANCE_CLIENTS_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Maintenance byte-session arbitration: simultaneous external priority, direct idle handshake, ended-session debt, correct reply owner, no active-session preemption and score-only cancellation isolation. Backend response/readiness modeled; production RAM integration tested separately.')
(root/'docs/reference/maintenance_clients_checks.json').write_text(json.dumps(result,indent=2)+'\n')
