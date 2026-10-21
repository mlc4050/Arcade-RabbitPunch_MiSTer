# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Exercise architectural retirement immediately before a Z80 capture."""
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
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_no_jtag('Z80 retirement/capture regression')
    root = core_root()
    out = root/'debug/ghdl'/('t80_retirement_'+args.label)
    assert not out.exists()
    out.mkdir(parents=True)
    donors = ['rtl/state/vendor/meatsauce_t80/'+name+'.vhd'
              for name in ('T80_Reg', 'T80_MCode', 'T80_ALU', 'T80')]
    sources = donors + ['rtl/state/rabbitpunch_t80_capture.vhd', 'sim/state/t80_retirement_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name in sources:
        target = out/'inputs'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((root/name).read_bytes())
    logs = []
    for library, group in (('state_t80', donors), ('work', sources[len(donors):])):
        folder = out/library
        folder.mkdir()
        commands = [[args.ghdl, '-a', '--std=08', '-fsynopsys',
            '-P'+str(out/'state_t80'), '--work='+library, '--workdir='+str(folder),
            *[str(root/name) for name in group]]]
        if library == 'work':
            commands.append([args.ghdl, '--elab-run', '--std=08', '-fsynopsys',
                '-P'+str(out/'state_t80'), '--workdir='+str(folder), 't80_retirement_tb', '--assert-level=error'])
        for command in commands:
            result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=120, **NO_WINDOW)
            logs.append(dict(command=command, returncode=result.returncode, stdout=result.stdout, stderr=result.stderr))
            (out/'commands.json').write_text(json.dumps(logs, indent=2)+'\n')
            assert result.returncode == 0, result.stdout+result.stderr
    assert 'T80_RETIREMENT_PASS' in logs[-1]['stdout']
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        command_log_sha256=hashlib.sha256((out/'commands.json').read_bytes()).hexdigest(),
        scope='Native VHDL unchanged T80 donor. Capture immediately after LD A,E; '
              'cancel during the normalization edge without abandoning the CPU, '
              'require committed accumulator and unconsumed next opcode, then '
              'three restores with256 exact architectural/bus clocks and RAM writes. '
              'Not a full instruction-set, board, whole-game or hardware proof.')
    (root/'docs/reference'/('t80_retirement_'+args.label+'_checks.json')).write_text(json.dumps(report, indent=2)+'\n')
    print('PASS delayed Z80 retirement and three exact continuations')


if __name__ == '__main__':
    main()
