# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify validated image publication through the actual word stream and DDR slot writer."""
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
    args = parser.parse_args()
    require_no_jtag('RabbitPunch complete image publication native test')
    root = core_root()
    out = root/'debug/ghdl/state_publish'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_layout.vhd',
               'rtl/state/rabbitpunch_state_image_words.vhd', 'rtl/state/rabbitpunch_state_slot_writer.vhd',
               'rtl/state/rabbitpunch_state_publish.vhd', 'sim/state/state_publish_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_publish_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=90, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_PUBLISH_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Nine complete-image publisher cases with actual word stream and DDRslotwriter: full107280-byte payload and13410 ordered words, four slot addresses and repeated counters, payload-first publication with prior invalidation, stalls, dual image/DDR accepted read debt, cancel/reset, source-permission/error failure, final-commit cancellation and retry. Synthetic byte source/DDR endpoint; permission supplied by test, no CRC-validator/game-state restoration or host SD acknowledgement.')
    (root/'docs/reference/state_publish_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(log, end='')


if __name__ == '__main__':
    main()
