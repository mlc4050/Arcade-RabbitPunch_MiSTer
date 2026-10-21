# SPDX-License-Identifier: GPL-3.0-or-later
"""Check index-255 ROM isolation and the state-enabled Cheats submenu."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/rabbitpunch_config.vhd','rtl/state/rabbitpunch_state_config.vhd','rtl/rabbitpunch_layout.vhd','rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','sim/cheats/cheats_host_tb.vhd']
result=run_case('cheats_host_v2',sources,'cheats_host_tb','1 ms','CHEATS_HOST_PASS')
report=dict(accepted=True,result=result,
    source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='State-enabled configuration retains DIP separator and standard Cheats submenu. Production ROM frontend ignores index255 writes, alongside ordinary direct/DDR regression cases. Behavioral host/DDR; not physical Main menu execution.')
(root/'docs/reference/cheats_host_v2_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print('CHEATS_HOST_PASS')
