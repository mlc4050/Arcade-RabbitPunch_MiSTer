# SPDX-License-Identifier: GPL-3.0-or-later
"""Check index-255 ROM isolation and the state-enabled Cheats submenu."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--label', default='v4')
args=parser.parse_args()
assert args.label.replace('_','').isalnum()
case='cheats_host_'+args.label
root=core_root()
assert not (root/f'docs/reference/{case}_checks.json').exists(), 'Preserve earlier receipts'
assert not (root/f'debug/baselines/{case}').exists(), 'Preserve earlier runs'
sources=['rtl/rabbitpunch_config.vhd','rtl/state/rabbitpunch_state_config.vhd','rtl/rabbitpunch_layout.vhd','rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','sim/cheats/cheats_host_tb.vhd']
result=run_case(case,sources,'cheats_host_tb','1 ms','CHEATS_HOST_PASS')
report=dict(accepted=True,result=result,
    source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='State-enabled configuration retains DIP separator and standard Cheats submenu. Production ROM frontend ignores index255 writes, alongside ordinary direct/DDR regression cases. Behavioral host/DDR; not physical Main menu execution.')
(root/f'docs/reference/{case}_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print('CHEATS_HOST_PASS')
