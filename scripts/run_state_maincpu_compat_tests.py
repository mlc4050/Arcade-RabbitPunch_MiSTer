# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare original 68000 phase/bus control with the actual state adapter every clock."""
import hashlib
import json
import shutil
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    original = (root/'rtl/rabbitpunch_maincpu.vhd').read_bytes()
    reference = (root/'sim/state/rabbitpunch_maincpu_reference.vhd').read_text()
    assert hashlib.sha256(original.replace(b'\r\n', b'\n')).hexdigest() in reference
    expected = original.decode().replace('\r\n', '\n')
    expected = expected.replace('rabbitpunch_maincpu', 'rabbitpunch_maincpu_reference')
    expected = expected.replace('entity work.rabbitpunch_fx68k', 'entity work.rabbitpunch_state_fx68k')
    expected = expected.replace('            o_halted_out_n => open\n',
                                '            o_halted_out_n => open,\n            o_stopped => open\n')
    assert reference[reference.index('library ieee;'):] == expected
    manifest = json.loads((root/'rtl/state/vendor/konamigx/vendor_manifest.json').read_text())
    for item in manifest['files']:
        assert hashlib.sha256((root/item['target']).read_bytes()).hexdigest() == item['sha256'], item['target']
    sources = ['rtl/state/vendor/konamigx/fx68k/'+name for name in
               ('fx68k.sv', 'fx68kAlu.sv', 'uaddrPla.sv')]
    sources += ['rtl/state/vendor/konamigx/gx_ss_m68k.sv',
                'rtl/state/rabbitpunch_state_fx68k.vhd',
                'rtl/state/rabbitpunch_m68k_capture.vhd',
                'rtl/state/rabbitpunch_capture_stack_undo.vhd',
                'rtl/state/rabbitpunch_capture_phase.vhd',
                'rtl/state/rabbitpunch_state_maincpu.vhd',
                'rtl/rabbitpunch_bus.vhd', 'rtl/rabbitpunch_clock_enables.vhd',
                'sim/state/rabbitpunch_maincpu_reference.vhd', 'sim/state/state_maincpu_compat_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    results = []
    for external in (False, True):
        for initial_reset, warm_reset in ((100, 100), (101, 99)):
            name = 'state_maincpu_compat_'+('fractional' if external else 'divider')+'_'+str(initial_reset)+'_lfref'
            out = root/'debug/baselines'/name
            for filename in ('microrom.mem', 'nanorom.mem'):
                target = out/'rtl/cpu/fx68k'/filename
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root/'rtl/state/vendor/konamigx/fx68k'/filename, target)
            sim_args = ['-suppress', '8315', '-suppress', '8360',
                        '-gGBOOL_EXTERNAL_PHASE_ENABLE='+str(external).lower(),
                        '-gGINT_INITIAL_RESET_CYCLES='+str(initial_reset),
                        '-gGINT_WARM_RESET_CYCLES='+str(warm_reset)]
            result = run_case(name, sources, 'state_maincpu_compat_tb', '3 ms', 'STATE_MAINCPU_COMPAT_PASS',
                              sim_args=sim_args, wall_timeout=120)
            assert hashes == {p: hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
            result.update(external_phase=external, initial_reset_cycles=initial_reset, warm_reset_cycles=warm_reset,
                          log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest())
            results.append(result)
    report = dict(accepted=True, results=results, source_sha256=hashes,
                  original_control_sha256=hashlib.sha256(original).hexdigest(),
                  original_control_lf_sha256=hashlib.sha256(original.replace(b'\r\n', b'\n')).hexdigest(),
                  runner_sha256=hashlib.sha256((root/'scripts/run_state_maincpu_compat_tests.py').read_bytes()).hexdigest(),
                  scope='Exact per-clock original phase/bus control versus actual state adapter, both '
                  'instantiating the same unchanged GX instruction core. Only reference entity/boundary '
                  'names and passive STOP output translation differ from original control source, '
                  'checked byte-for-byte after that transformation. Divider and fractional enables; '
                  'two reset-duration pairs, variable0/17/65-clock replies, two byte/readback '
                  'diagnostics, user pause, STOP, reset replay and two IRQ/autovector handlers per case. '
                  'Every request pulse/packet/write-data/IRQ/pause clock must match with no offset. '
                  'Normal mode only; no game-ROM or capture/restore qualification in this gate.')
    (root/'docs/reference/state_maincpu_compat_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
