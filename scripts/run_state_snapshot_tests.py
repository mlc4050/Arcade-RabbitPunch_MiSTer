# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify two-pass captured-body CRC and immutable image construction."""
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
    out = root/'debug/ghdl/state_snapshot'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_crc.vhd', 'rtl/state/rabbitpunch_state_header.vhd', 'rtl/state/rabbitpunch_state_image_buffer.vhd', 'rtl/state/rabbitpunch_state_snapshot.vhd', 'sim/state/state_snapshot_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_snapshot_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_SNAPSHOT_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Native snapshot/header/private RAM integration: two captured-body passes with CRC consistency, exact independent zlib header and body bytes, held-machine admission, source/image stalls, unstable body/backend error rejection, canceled accepted read debt, changed/unknown ROM identity, lost machine hold, invalid section metadata, reset while debt owed, cancellation before machine hold and valid retry. No CPU/body-bank integration, DDR publication, semantic validation or full game restore qualification.')
    (root/'docs/reference/state_snapshot_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
