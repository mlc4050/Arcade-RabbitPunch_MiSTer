# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check empty-queue normalization without changing normal round-robin policy."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_no_jtag('State read-arbiter normalization regression')
    root = core_root()
    out = root/'debug/ghdl'/('state_read_arbiter_'+args.label)
    assert not out.exists(), 'Preserve previous attempts'
    out.mkdir(parents=True)
    sources = ['rtl/rabbitpunch_sdram_types.vhd', 'rtl/rabbitpunch_read_arbiter.vhd',
               'sim/state/state_read_arbiter_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    commands = [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources]]
    for invalid in (False, True):
        commands.append([args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
            'state_read_arbiter_tb', '-gGBOOL_INVALID_NORMALIZE='+str(invalid).lower(), '--assert-level=error'])
    for index, command in enumerate(commands):
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=60, **NO_WINDOW)
        logs.append(dict(command=command, returncode=result.returncode, stdout=result.stdout, stderr=result.stderr))
        (out/'commands.json').write_text(json.dumps(logs, indent=2)+'\n')
        output = result.stdout+result.stderr
        if index == 2:
            assert result.returncode != 0 and 'normalization requires drained requests' in output, output
        else:
            assert result.returncode == 0, output
            if index == 1:
                assert 'STATE_READ_ARBITER_PASS' in output
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        command_log_sha256=hashlib.sha256((out/'commands.json').read_bytes()).hexdigest(),
        scope='Native VHDL queue with three seeded cursor positions. Normal mode '
              'retains prior round-robin order; empty normalization chooses0/1/2 '
              'for simultaneous requests.24 replies retain owners/data under '
              'backend stalls and variable latency. Busy normalization rejected '
              'by assertion; no full-machine or hardware qualification.')
    (root/'docs/reference'/('state_read_arbiter_'+args.label+'_checks.json')).write_text(json.dumps(report, indent=2)+'\n')
    print('PASS normal ordering, normalized ordering,24 reply credits and busy rejection')


if __name__ == '__main__':
    main()
