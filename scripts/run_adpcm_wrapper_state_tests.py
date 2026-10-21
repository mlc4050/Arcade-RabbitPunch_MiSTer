# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify board ADPCM wrapper state with the generated full-state chip."""
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
    parser.add_argument('--label', default='')
    args = parser.parse_args()
    assert all(value.isalnum() or value == '_' for value in args.label)
    case = 'adpcm_wrapper_state' + ('_' + args.label if args.label else '')
    require_no_jtag('RabbitPunch corrected ADPCM wrapper state gate')
    root = core_root()
    out = root/'debug/ghdl'/case
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/generated/jt7759_state_netlist.vhd', 'rtl/rabbitpunch_upd7759.vhd', 'rtl/rabbitpunch_adpcm.vhd', 'sim/state/adpcm_wrapper_state_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'adpcm_wrapper_state_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'ADPCM_WRAPPER_STATE_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Integrated ADPCM VHDL wrapper/generated-chip state path: pending WAITING/START command snapshots, bank/reset/start readiness/command reload, complementary wrapper controls and all189 corrected chip bits, masked outward ROM requests during hold and nine1024-clock immediate continuations with nonzero PCM and gameplay reset priority over a held partial chip load. Synthetic throttled ROM, not physical transport or full game restore.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
