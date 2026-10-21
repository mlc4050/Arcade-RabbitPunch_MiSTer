# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify both production sound CPU selections and drained HALT capture."""
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
    out = root/'debug/ghdl/soundcpu_state_paths'
    libraries = {name: out/name for name in ('state_t80', 'work')}
    for path in libraries.values():
        path.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((root/'rtl/state/vendor/meatsauce_t80/vendor_manifest.json').read_text(encoding='utf-8-sig'))
    for row in manifest['files']:
        assert hashlib.sha256((root/row['target']).read_bytes()).hexdigest() == row['sha256']
    state_sources = ['rtl/state/vendor/meatsauce_t80/'+name+'.vhd'
                     for name in ('T80_Reg', 'T80_MCode', 'T80_ALU', 'T80')]
    original_sources = ['rtl/cpu/t80/'+name+'.vhd'
                        for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources = state_sources + original_sources + ['rtl/state/rabbitpunch_t80_capture.vhd', 'rtl/rabbitpunch_z80.vhd', 'rtl/rabbitpunch_soundcpu.vhd', 'sim/state/soundcpu_state_paths_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}

    def command(arguments, log):
        result = subprocess.run([args.ghdl, *map(str, arguments)], cwd=root,
                                text=True, capture_output=True, timeout=120, **NO_WINDOW)
        (out/log).write_text(result.stdout+result.stderr, encoding='utf-8', newline='\n')
        assert result.returncode == 0, (out/log).read_text()[-4000:]
        return result.stdout+result.stderr

    command(['-a', '--std=08', '-fsynopsys', '--work=state_t80',
             '--workdir='+str(libraries['state_t80']), *state_sources], 'state_compile.log')
    command(['-a', '--std=08', '-fsynopsys', '-P'+str(libraries['state_t80']),
             '--workdir='+str(libraries['work']), *sources[len(state_sources):]], 'work_compile.log')
    cases = []
    for mode in (False, True):
        log = command(['--elab-run', '--std=08', '-fsynopsys', '-P'+str(libraries['state_t80']),
                       '--workdir='+str(libraries['work']), 'soundcpu_state_paths_tb',
                       '-gGBOOL_STATE_CAPABLE='+str(mode).lower(), '--assert-level=error'], 'mode'+str(mode)+'.log')
        assert 'SOUNDCPU_STATE_PATHS_PASS' in log, log[-4000:]
        cases.append(dict(mode=mode, log=(out/('mode'+str(mode)+'.log')).relative_to(root).as_posix(),
                          log_sha256=hashlib.sha256((out/('mode'+str(mode)+'.log')).read_bytes()).hexdigest()))
        print('PASS sound CPU state selection='+str(mode), flush=True)
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes, cases=cases,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  scope='Both production sound CPU selections:65-clock delayed replies, RAM/peripheral writes, reset/pause debt draining; state-capable path additionally captures HALT while user pause asserted, reloads256-bit image and resumes three times without replaying writes or overriding retained user pause. No full sound-board or game-state restore qualification.')
    (root/('docs/reference/soundcpu_state_paths_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
