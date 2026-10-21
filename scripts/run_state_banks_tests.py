# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify held bank byte packing, complete writes and final wide-register commit."""
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
    case = 'state_banks' + ('_' + args.label if args.label else '')
    require_no_jtag('RabbitPunch held body banks native test')
    root = core_root()
    out = root/'debug/ghdl'/case
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_layout.vhd',
               'rtl/state/rabbitpunch_state_memory.vhd', 'rtl/state/rabbitpunch_state_body.vhd',
               'rtl/state/rabbitpunch_state_banks.vhd', 'sim/state/state_banks_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_banks_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=90, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_BANKS_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Real dense-RAM adapter plus held-body parent with synthetic physical RAM/register endpoints: every107216-byte read before and after a complete ordered write; two independent patterns, canonical zero donor/FM padding with unknown imported unused bits,20 CPU words,126 FM words,6 ADPCM words, deferred atomic T80/board load, denied partial/out-of-order commits, physical main/sound addresses and big-endian byte lanes, delayed RAM and session-loss/reset debt. Tests packing/protocol only; does not prove CPU/chip or complete-game restoration.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(log, end='')


if __name__ == '__main__':
    main()
