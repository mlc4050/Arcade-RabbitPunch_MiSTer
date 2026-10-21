# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify observable E-clock normalization at the stalled 68000 monitor boundary."""
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
    parser.add_argument('--label', default='', choices=('', 'normal_compat'))
    args = parser.parse_args()
    require_no_jtag('RabbitPunch capture phase qualification')
    root = core_root()
    suffix = '_'+args.label if args.label else ''
    out = root/('debug/ghdl/capture_phase'+suffix)
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_capture_phase.vhd', 'sim/state/capture_phase_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'capture_phase_tb', '-gGBOOL_EXTERNAL_PHASE_ENABLE=false', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        assert result.returncode == 0, logs[-1]
    result = subprocess.run([args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out), 'capture_phase_tb', '-gGBOOL_EXTERNAL_PHASE_ENABLE=true', '--assert-level=error'], cwd=root, text=True, capture_output=True, timeout=30, **NO_WINDOW)
    logs.append(result.stdout+result.stderr)
    assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'CAPTURE_PHASE_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Phase-controller-only test against exact imported fx68k E/eCntr recurrence:60 acquisition phases,12000 identical resume clocks and user-pause override/preservation. Both internal divider and fractional external enables tested. Not full CPU hidden-state equivalence, monitor RTE/STOP integration or physical display timing qualification.')
    (root/('docs/reference/capture_phase'+suffix+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
