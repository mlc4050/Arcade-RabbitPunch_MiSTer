# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check whole-operation legacy maintenance admission during state quiesce."""
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
    assert all(character.isalnum() or character == '_' for character in args.label)
    require_no_jtag('RabbitPunch state maintenance admission native test')
    root = core_root()
    out = root / 'debug/ghdl' / ('state_maintenance_clients' + ('_' + args.label if args.label else ''))
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/rabbitpunch_maintenance_clients.vhd', 'sim/state/state_maintenance_clients_tb.vhd']
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir=' + str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir=' + str(out),
                     'state_maintenance_clients_tb', '--assert-level=error', '--stop-time=1ms']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True, timeout=60, **NO_WINDOW)
        logs.append(result.stdout + result.stderr)
        (out / 'result.log').write_text('\n'.join(logs), encoding='utf-8')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_MAINTENANCE_CLIENTS_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log=(out / 'result.log').relative_to(root).as_posix(),
        log_sha256=hashlib.sha256((out / 'result.log').read_bytes()).hexdigest(),
        scope='Production legacy maintenance byte/session owner with synthetic acknowledged '
              'backend. Original external priority, packet ownership, cancellation and '
              'late-reply cases plus state quiesce: block new external sessions, drain '
              'already accepted whole score operations even before byte-owner admission, '
              'retain active external credits and queued payloads, then retire all owners. '
              'No RAM, actual NVRAM engine, game-state coordinator or hardware qualification.')
    (root / 'docs/reference/state_maintenance_clients_checks.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
