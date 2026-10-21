# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify isolated shared-DDR response ownership across cancellation."""
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
    out = root/'debug/ghdl/state_ddr_arbiter'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_ddr_arbiter.vhd', 'sim/state/state_ddr_arbiter_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_ddr_arbiter_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=30, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_DDR_ARBITER_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Standalone single-clock DDR arbiter: loader exclusive ownership, '
                  'rotation write priority, snapshot single-beat read/write payload/masks, '
                  'physical BUSY stalls, accepted snapshot read drained across cancellation '
                  'and initialization before loader takeover, canceled loader3/255-beat '
                  'bursts routed only to loader, no premature read-idle, single-beat loader '
                  'write priority, no new commands during initialization. No production '
                  'rotation queue, loader, DDR controller, game states or FPGA timing qualification.')
    (root/'docs/reference/state_ddr_arbiter_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
