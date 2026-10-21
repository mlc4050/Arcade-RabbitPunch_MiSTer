# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify image framing/compatibility/integrity checks before state mutation."""
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
    out = root/'debug/ghdl/state_preflight'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_crc.vhd', 'rtl/state/rabbitpunch_state_preflight.vhd',
               'sim/state/state_preflight_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_preflight_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_PREFLIGHT_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Isolated stream-only board-image preflight:21 cases, valid retry after '
                  'all rejection cases, independent '
                  'zlib body-CRC fixture, stalled stream, simultaneous last-byte/finish, '
                  'magic/version/ABI/ROM/config/headerCRC/bodyCRC/length/section/reserved '
                  'checks, overflowing section values, early end, excess byte, live ROM/config '
                  'change and abort with ignored late bytes. No state-write interface exists. '
                  'CPU/beam field legality, immutable DDR source, two-pass application and '
                  'whole-game rollback/restore remain parent integration requirements.')
    (root/'docs/reference/state_preflight_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
