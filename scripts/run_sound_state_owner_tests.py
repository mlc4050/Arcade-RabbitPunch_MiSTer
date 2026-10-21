# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify production sound-board response ownership with a delayed VHDL backend."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from coretools import core_root, NO_WINDOW


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    args = parser.parse_args()
    root = core_root()
    out = root/'debug/ghdl/sound_state_owner'
    libraries = {name: out/name for name in ('state_t80', 'altera_mf', 'work')}
    for path in libraries.values():
        path.mkdir(parents=True, exist_ok=True)
    state_sources = ['rtl/state/vendor/meatsauce_t80/'+name+'.vhd'
                     for name in ('T80_Reg', 'T80_MCode', 'T80_ALU', 'T80')]
    work_sources = ['rtl/state/rabbitpunch_t80_capture.vhd', 'rtl/rabbitpunch_z80.vhd',
                    'rtl/rabbitpunch_soundcpu.vhd', 'rtl/rabbitpunch_ram8.vhd',
                    'rtl/rabbitpunch_sound_bus.vhd', 'rtl/state/generated/jt51_state_netlist.vhd',
                    'rtl/rabbitpunch_ym2151.vhd', 'rtl/rabbitpunch_sound_board.vhd',
                    'sim/state/delayed_state_sound_bus.vhd', 'sim/state/sound_state_owner_tb.vhd']
    sources = state_sources + work_sources
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    package = Path('D:/Quartus/quartus/eda/sim_lib/altera_mf_components.vhd')
    logs = []

    def command(arguments):
        result = subprocess.run([args.ghdl, *map(str, arguments)], cwd=root,
                                text=True, capture_output=True, timeout=60, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1][-5000:]

    command(['-a', '--std=08', '--work=altera_mf', '--workdir='+str(libraries['altera_mf']), package])
    command(['-a', '--std=08', '-fsynopsys', '--work=state_t80',
             '--workdir='+str(libraries['state_t80']), *state_sources])
    paths = ['-P'+str(libraries[name]) for name in ('state_t80', 'altera_mf')]
    command(['-a', '--std=08', '-fsynopsys', *paths,
             '--workdir='+str(libraries['work']), *work_sources])
    command(['--elab-run', '--std=08', '-fsynopsys', *paths,
             '--workdir='+str(libraries['work']), 'sound_state_owner_tb',
             '--assert-level=error', '--disp-tree=inst'])
    log = '\n'.join(logs)
    assert 'SOUND_STATE_OWNER_PASS' in log and 'delayed_state_test' in log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
                  vendor_component_package_sha256=hashlib.sha256(package.read_bytes()).hexdigest(),
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Actual state-enabled sound board/Z80/generated FM with test-only delayed '
                  'VHDL backend architecture: late RAM read/write reply retains state ownership '
                  'after mode cancel, held cancellation, short gameplay reset during accepted debt, '
                  'no new CPU requests until debt retired, clean rebootstrap and retained user '
                  'pause on resume. Hierarchy confirms delayed_state_test. This is a protocol '
                  'injection test, not original sound RAM, real-ROM audio, ADPCM or whole-game restore.')
    (root/'docs/reference/sound_state_owner_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('PASS sound state response ownership with delayed protocol backend')


if __name__ == '__main__':
    main()
