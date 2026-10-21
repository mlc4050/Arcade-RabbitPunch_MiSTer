# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify complete immutable-image framing, CRC and field validation before application."""
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
    case = 'state_image_validator' + ('_' + args.label if args.label else '')
    require_no_jtag('RabbitPunch complete-image validation native test')
    root = core_root()
    out = root/'debug/ghdl'/case
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/state/rabbitpunch_state_layout.vhd', 'rtl/state/rabbitpunch_state_crc.vhd', 'rtl/state/rabbitpunch_state_preflight.vhd', 'rtl/state/rabbitpunch_state_semantics.vhd', 'rtl/state/rabbitpunch_state_image_buffer.vhd', 'rtl/state/rabbitpunch_state_image_validator.vhd', 'sim/state/state_image_validator_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_image_validator_tb', '--assert-level=error']]:
        result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                timeout=90, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert 'STATE_IMAGE_VALIDATOR_PASS' in log, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    (out/'result.log').write_text(log, encoding='utf-8', newline='\n')
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  scope='Complete107280-byte private image RAM/framing/CRC/body-semantics integration: independently zlib-pinned valid and CRC-valid illegal-SR images, body CRC and ROM identity rejection, unsealed source, cancel/reset with delayed accepted read debt, injected read error, live identity permission gating and valid retry. Read-only interface cannot modify game state. No application/backend/CPU or full game restore qualification.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(log, end='')


if __name__ == '__main__':
    main()
