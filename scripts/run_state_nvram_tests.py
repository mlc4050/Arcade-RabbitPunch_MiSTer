# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify NVRAM/state serialization against the pinned MAME score geometry."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label', default='')
    args = parser.parse_args()
    assert all(character.isalnum() or character == '_' for character in args.label)
    require_no_jtag('RabbitPunch state/NVRAM native test')
    root = core_root()
    name = 'state_nvram' + ('_' + args.label if args.label else '')
    out = root / 'debug/ghdl' / name
    out.mkdir(parents=True, exist_ok=True)
    reference = json.loads((root / 'docs/reference/hiscore_reference.json').read_text())
    data = bytearray()
    for game in ('rabiolep', 'rpunch'):
        row = next(item for item in reference if item['set'] == game)
        initial = (root / 'debug/hiscore_reference' / game / 'initial.bin').read_bytes()
        assert len(initial) == row['length']
        assert hashlib.sha256(initial).hexdigest() == row['initial_sha256']
        assert initial[0] == row['first'] and initial[-1] == row['last']
        data.extend(initial)
    (out / 'scores.hex').write_text(''.join(f'{value:02x}\n' for value in data), encoding='utf-8')
    sources = ['sim/fast/rabbitpunch_ram8_model.vhd', 'rtl/rabbitpunch_hiscore.vhd',
               'sim/state/state_nvram_tb.vhd']
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    commands = [[args.ghdl, '-a', '--std=08', '--workdir=' + str(out), *[str(root / name) for name in sources]],
                [args.ghdl, '--elab-run', '--std=08', '--workdir=' + str(out),
                 'state_nvram_tb', '--assert-level=error', '--stop-time=1ms']]
    logs = []
    for command in commands:
        result = subprocess.run(command, cwd=out, text=True, capture_output=True, timeout=60, **NO_WINDOW)
        logs.append(result.stdout + result.stderr)
        (out / 'result.log').write_text('\n'.join(logs), encoding='utf-8')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_NVRAM_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        fixture_sha256=hashlib.sha256(data).hexdigest(),
        log=str((out / 'result.log').relative_to(root)),
        log_sha256=hashlib.sha256((out / 'result.log').read_bytes()).hexdigest(),
        scope='Both pinned MAME score geometries with original score fixtures, '
              'production score controller, logical RAM8 model and delayed byte backend. '
              'Quiesce during an active full-table restore, idle lease stability, '
              'repeated state restore/rescan without stale RAM writes, trusted captured '
              'readiness with legitimately changed guard bytes, invalid guard '
              'retry, deferred manual save and a host download announced while held. '
              'No physical RAM, complete platform, host disk persistence or hardware proof.')
    (root / 'docs/reference/state_nvram_checks.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
