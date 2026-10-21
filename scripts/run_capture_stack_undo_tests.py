# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Exercise the capture-entry RAM undo adapter with delayed backend replies."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from coretools import core_root
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label', default='', choices=('', 'normal_compat'))
    args = parser.parse_args()
    require_no_jtag('RabbitPunch capture stack undo qualification')
    root = core_root()
    suffix = '_'+args.label if args.label else ''
    out = root/('debug/ghdl/stack_undo'+suffix)
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_capture_stack_undo.vhd',
               'sim/state/capture_stack_undo_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    commands = [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                 'capture_stack_undo_tb', '--assert-level=error']]
    logs = []
    for command in commands:
        result = subprocess.run(command, cwd=root, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=30)
        logs.append(result.stdout)
        assert result.returncode == 0, result.stdout
    log = '\n'.join(logs)
    assert 'CAPTURE_STACK_UNDO_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  ghdl=subprocess.check_output([args.ghdl, '--version'], text=True).splitlines()[0],
                  scope='Isolated RAM adapter, delayed backend: last-word undo preserves earlier '
                  'writes, five repeated undo operations, both byte lanes, normal pass-through '
                  'without speculative reads, missing-journal rejection, cancellation during '
                  'old-word read and accepted game-write debt, explicit journal discard. '
                  'Not yet connected to GX CPU, production RAM or a game state controller; '
                  'parent must validate journal address against captured SSP-2.')
    (root/('docs/reference/capture_stack_undo'+suffix+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
