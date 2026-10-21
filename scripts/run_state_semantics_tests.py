# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify complete-body register, padding, cadence and beam legality before application."""
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
    case = 'state_semantics' + ('_' + args.label if args.label else '')
    require_no_jtag('RabbitPunch body semantics native test')
    root = core_root()
    out = root/'debug/ghdl'/case
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_layout.vhd', 'rtl/state/rabbitpunch_state_semantics.vhd', 'sim/state/state_semantics_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_semantics_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=60, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_SEMANTICS_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Read-only complete-body legality stream:34 cases cover M68K SR/PC/SSP and padding, Z80 IM/reserved bits, IO/IRQ/cadence/beam/ADPCM wrapper bounds, FM tail padding, FM startup consistency, captured score readiness,189-bit ADPCM tail padding, valid boundary values, stalls, truncated/excess length, abort with ignored late bytes and valid retry. No state-write port or full-game integration/FPGA timing qualification.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
