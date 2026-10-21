# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify the held-machine access/release protocol with native VHDL."""
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
    parser.add_argument('--resume-request', action='store_true')
    args = parser.parse_args()
    assert all(character.isalnum() or character == '_' for character in args.label)
    require_no_jtag('RabbitPunch machine-state access native test')
    root = core_root()
    out = root / 'debug/ghdl' / ('state_machine_access' + ('_' + args.label if args.label else ''))
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_machine_access.vhd', 'sim/state/state_machine_access_tb.vhd']
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir=' + str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir=' + str(out),
                     'state_machine_access_tb', '-gGBOOL_RESUME_REQUEST='+str(args.resume_request).lower(),
                     '--assert-level=error', '--stop-time=1ms', '--stop-delta=1000']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=60, **NO_WINDOW)
        logs.append(result.stdout + result.stderr)
        (out / 'result.log').write_text('\n'.join(logs), encoding='utf-8')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_MACHINE_ACCESS_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log=(out / 'result.log').relative_to(root).as_posix(),
        log_sha256=hashlib.sha256((out / 'result.log').read_bytes()).hexdigest(),
        scope='Machine access protocol with synthetic CPU/bank/transport credit endpoints. '
              'Paired acquisition after NVRAM/legacy drain, chips held only after captured '
              'CPU drains, entry/return cache barriers, private return after bank debt, '
              'single-clock physical alignment release, held NVRAM readiness load/reconciliation, '
              'three incomplete-apply retries, early/late cancellation, acquisition/alignment '
              'timeouts and reset debt retirement. No actual CPU/chip/renderer composition, '
              'DDR image engine, whole-game continuation, FPGA or hardware proof.')
    report_name = 'state_machine_access'+('_'+args.label if args.label else '')+'_checks.json'
    report['resume_request_feedback'] = args.resume_request
    (root / 'docs/reference'/report_name).write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
