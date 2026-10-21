# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify unchanged state-aware T80 at a clean board-specific fetch boundary."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--mode', type=int, choices=(0, 1, 2))
    parser.add_argument('--label', help='Preserve this run in a new directory and receipt')
    args = parser.parse_args()
    root = core_root()
    require_no_jtag('Native T80 capture regression')
    if args.label:
        assert args.label.replace('_', '').isalnum()
    out = root/'debug/ghdl'/('t80_capture'+('_'+args.label if args.label else ''))
    if args.label:
        assert not out.exists(), 'Preserve previous attempts'
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
    sources = state_sources + original_sources + ['rtl/rabbitpunch_t80.vhd',
              'rtl/state/rabbitpunch_t80_capture.vhd', 'sim/state/t80_capture_tb.vhd']
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
    for mode in (range(3) if args.mode is None else [args.mode]):
        log = command(['--elab-run', '--std=08', '-fsynopsys', '-P'+str(libraries['state_t80']),
                       '--workdir='+str(libraries['work']), 't80_capture_tb',
                       '-gGINT_INTERRUPT_MODE='+str(mode), '--assert-level=error'], 'mode'+str(mode)+'.log')
        assert 'T80_CAPTURE_PASS' in log, log[-4000:]
        cases.append(dict(mode=mode, log=(out/('mode'+str(mode)+'.log')).relative_to(root).as_posix(),
                          log_sha256=hashlib.sha256((out/('mode'+str(mode)+'.log')).read_bytes()).hexdigest()))
        print('PASS T80 capture IM'+str(mode), flush=True)
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes, cases=cases,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  scope='Unchanged230-bit T80 donor with new VHDL clean-fetch capture/bus wrapper. '
                  'Synthetic native VHDL program compares normal bus timing/address/writes '
                  'against original production T80se, then tests three400-write continuations '
                  'with both register banks, live R/I reads, R bit7/wrap and periodic IRQ. '
                  'Prefix/EI admission guards, acquisition cancellation, alternate bank '
                  'reload, complementary writes to all238used bits, full256-bit image and RAM '
                  'restore, three512-clock HALT continuations/IRQ wakes and pendingEI+IRQ '
                  'request deferred to safe acknowledged IRQ entry and its continuation '
                  'are checked for each selected IM. Board NMI/BUSRQ are tied '
                  'inactive; this is not an all-microstate/general NMI/ISA proof, real soundROM '
                  'comparison, production sound bus, Quartus fit or full game restore.')
    suffix = '' if args.mode is None else '_mode'+str(args.mode)
    if args.label:
        suffix += '_'+args.label
    (root/('docs/reference/t80_capture'+suffix+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
