# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib,json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/rabbitpunch_ram16.vhd','rtl/rabbitpunch_ram8.vhd','sim/memory/ram_powerup_tb.vhd']
result=run_case('ram_powerup',sources,'ram_powerup_tb','100 us','RAM_POWERUP_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Native M10K configuration contents without simulator deposits: all 256 addresses on both read ports, three logical word patterns and zeroed byte RAM; independent upper/lower writes and disabled-output retention. Board binding is checked separately; physical hardware power-up not yet measured.')
(root/'docs/reference/ram_powerup_checks.json').write_text(json.dumps(result,indent=2)+'\n')
