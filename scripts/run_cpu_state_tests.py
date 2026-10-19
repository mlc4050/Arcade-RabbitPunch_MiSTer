# SPDX-License-Identifier: GPL-3.0-or-later
"""Qualify instruction-boundary CPU state helpers against unchanged native CPUs."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
manifest = json.loads((root/'rtl/state/vendor/nmk16/vendor_manifest.json').read_text())
for item in manifest['files']:
    assert hashlib.sha256((root/item['target']).read_bytes()).hexdigest() == item['sha256']
sources = ['rtl/cpu/fx68k/fx68k.sv','rtl/cpu/fx68k/fx68kAlu.sv','rtl/cpu/fx68k/uaddrPla.sv',
    'rtl/rabbitpunch_fx68k.vhd','rtl/state/vendor/nmk16/ss_m68k_park.sv',
    'rtl/state/rabbitpunch_m68k_state.vhd','sim/state/m68k_state_tb.vhd']
result = run_case('m68k_state', sources, 'm68k_state_tb', '21 ms', 'M68K_STATE_PASS', wall_timeout=180, sim_args=['-suppress','8315','-suppress','8360'])
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Native fx68k, unchanged NMK16 monitor helper, descriptive VHDL wrapper and VHDL memory/stimulus/scoreboard. Architectural register/64KiB RAM round trip with 400 ordered resumed game writes; USP separately checked. Synthetic continuously running supervisor program with SR interrupt mask zero only; fully masked case did not park and remains unresolved; STOP, pending normal interrupt, real game bus, Z80, sound, DDR/file slots and physical hardware are separate gates. Testbench snapshots are not a production state engine.')
(root/'docs/reference/m68k_state_checks.json').write_text(json.dumps(result,indent=2)+'\n')
