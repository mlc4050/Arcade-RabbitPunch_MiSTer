# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify main CPU/NVRAM/state reply ownership across cancellation and reset."""
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
    require_no_jtag('RabbitPunch main state bus ownership native test')
    root = core_root()
    out = root/'debug/ghdl/state_main_bus'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/rabbitpunch_bus_owner.vhd',
               'rtl/state/rabbitpunch_state_main_bus.vhd', 'sim/state/state_main_bus_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_main_bus_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=90, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_MAIN_BUS_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Nine accepted CPU/NVRAM/state packets through the actual shared bus owner: preserved direct CPU edge and CPU priority, delayed replies, latched state address/data/byte/write fields, canceled live access, accepted state request on reset edge, retained reset until debt/session retirement, fresh legacy/CPU replies after state, exact no-replay packet and reply counts. Synthetic backend; no physical RAM, complete board or game-state restoration.')
    (root/'docs/reference/state_main_bus_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(log, end='')


if __name__ == '__main__':
    main()
