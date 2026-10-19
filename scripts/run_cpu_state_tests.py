# SPDX-License-Identifier: GPL-3.0-or-later
"""Qualify instruction-boundary CPU state helpers against unchanged native CPUs."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cpu", choices=("m68k", "z80"), default="m68k")
parser.add_argument("--masked", action="store_true")
args = parser.parse_args()
assert not args.masked or args.cpu == "m68k"
root = core_root()
manifest = json.loads((root/'rtl/state/vendor/nmk16/vendor_manifest.json').read_text())
for item in manifest['files']:
    assert hashlib.sha256((root/item['target']).read_bytes()).hexdigest() == item['sha256']
sources = ['rtl/cpu/fx68k/fx68k.sv','rtl/cpu/fx68k/fx68kAlu.sv','rtl/cpu/fx68k/uaddrPla.sv',
    'rtl/rabbitpunch_fx68k.vhd','rtl/state/vendor/nmk16/ss_m68k_park.sv',
    'rtl/state/rabbitpunch_m68k_state.vhd','sim/state/m68k_state_tb.vhd']
if args.cpu == 'z80':
    sources = ['rtl/cpu/t80/'+name+'.vhd' for name in ('T80_Pack','T80_Reg','T80_MCode','T80_ALU','T80','T80se')] + ['rtl/rabbitpunch_t80.vhd','rtl/state/vendor/nmk16/ss_z80_park.sv','rtl/state/rabbitpunch_z80_state.vhd','sim/state/z80_state_tb.vhd']
case = args.cpu + '_state' + ('_masked' if args.masked else '')
sim_args = ['-suppress','8315','-suppress','8360'] + (['-gGINT_INITIAL_STATUS=9984','-voptargs=+acc'] if args.masked else [])
setup = []
if args.masked:
    setup = ['onbreak {echo MASKED_CPU_INTERNALS; echo rIpl=[examine -radix hex /m68k_state_tb/cpu/cpu/rIpl]; echo iIpl=[examine -radix hex /m68k_state_tb/cpu/cpu/iIpl]; echo intPend=[examine -radix hex /m68k_state_tb/cpu/cpu/intPend]; echo prevNmi=[examine -radix hex /m68k_state_tb/cpu/cpu/prevNmi]; echo inl=[examine -radix hex /m68k_state_tb/cpu/cpu/inl]; echo pswI=[examine -radix hex /m68k_state_tb/cpu/cpu/pswI];  quit -code 1 -f}']
    setup += ['vcd file masked_interrupt.vcd', 'vcd add /m68k_state_tb/s_capture /m68k_state_tb/s_phase2 /m68k_state_tb/cpu/cpu/rIpl /m68k_state_tb/cpu/cpu/iIpl /m68k_state_tb/cpu/cpu/intPend /m68k_state_tb/cpu/cpu/prevNmi /m68k_state_tb/cpu/cpu/inl /m68k_state_tb/cpu/cpu/pswI /m68k_state_tb/cpu/cpu/Iac /m68k_state_tb/cpu/cpu/iplStable /m68k_state_tb/cpu/cpu/nmi /m68k_state_tb/cpu/cpu/iplComp /m68k_state_tb/cpu/cpu/enPhi2 /m68k_state_tb/cpu/cpu/extReset', 'vcd on']
result = run_case(case, sources, args.cpu+'_state_tb', '21 ms', args.cpu.upper()+'_STATE_PASS', wall_timeout=180, sim_args=sim_args, setup_commands=setup)
result.update(cpu=args.cpu, initial_status=(9984 if args.masked else 8192) if args.cpu == 'm68k' else None, source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Native fx68k, unchanged NMK16 monitor helper, descriptive VHDL wrapper and VHDL memory/stimulus/scoreboard. Architectural register/64KiB RAM round trip with 400 ordered resumed game writes; USP separately checked. Synthetic continuously running supervisor program; initial SR is recorded separately; masked and unmasked cases now enter through a resettable VHDL interrupt-request path; STOP, pending normal interrupt, real game bus, Z80, sound, DDR/file slots and physical hardware are separate gates. Testbench snapshots are not a production state engine.')
if args.cpu == 'z80':
    result['scope'] = 'Native production T80se, unchanged NMK16 NMI monitor and descriptive VHDL wrapper. 64KiB RAM and SP/IM restore, both register banks exercised, 400 ordered continuation writes including periodic mode-1 IRQ handler activity with external IRQ phase restored. No production sound-bus integration, chip state, HALT/pending-NMI/general interrupt-mode or physical hardware proof.'
(root/('docs/reference/'+case+'_checks.json')).write_text(json.dumps(result,indent=2)+'\n')
