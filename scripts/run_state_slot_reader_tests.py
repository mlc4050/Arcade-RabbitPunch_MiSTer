# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify external slot staging into immutable RAM before restore preflight."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
from coretools import core_root, NO_WINDOW


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label')
    args = parser.parse_args()
    root = core_root()
    assert not args.label or args.label.replace('_', '').isalnum()
    case = 'state_slot_reader'+('_'+args.label if args.label else '')
    out = root/'debug/ghdl'/case
    assert not out.exists(), 'Preserve previous native reader attempts'
    out.mkdir(parents=True)
    sources = ['rtl/state/rabbitpunch_state_crc.vhd', 'rtl/state/rabbitpunch_state_preflight.vhd', 'rtl/state/rabbitpunch_state_image_buffer.vhd', 'rtl/state/rabbitpunch_state_slot_reader.vhd', 'sim/state/state_slot_reader_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name in sources:
        target = out/'inputs'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, target)
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_slot_reader_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_SLOT_READER_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes, cases=11,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Native DDR reader/private RAM/preflight integration: stalled DDR and fill stream, complete byte ordering, outer length/empty checks, changed counter rejection, cancellation drains accepted read, corrupted body rejected by real preflight and valid retry. ARM file-loaded FFFFFFFF counter with valid length is accepted through CRC preflight; zero length remains empty, changed counter is rejected and corrupt loaded body still fails CRC. No game state write interface, host-copy lock, physical DDR, CPU semantic validation or full game restore qualification.')
    (root/'docs/reference'/(case+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
