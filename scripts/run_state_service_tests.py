# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify immutable full-image save/restore orchestration with delayed endpoints."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--wall-timeout', type=int, default=60)
    parser.add_argument('--group', type=int, choices=(0, 1, 2, 3, 4), default=0)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    assert 1 <= args.wall_timeout <= 600
    require_no_jtag('RabbitPunch immutable-image service native test')
    root = core_root()
    case = 'state_service_'+args.label
    out = root/'debug/ghdl'/case
    assert not out.exists(), 'Preserve previous attempts with a fresh label'
    out.mkdir(parents=True)
    # Independent byte geometry and software CRC; no DUT CRC/layout functions.
    body = bytearray(107216)
    body[:106496] = bytes((address*17+3)%256 for address in range(106496))
    for word, data in ((18, 0x000ff7fa), (19, 0x00002000), (20, 0x00000400)):
        struct.pack_into('<I', body, 106496+word*4, data)
    expected_crc = zlib.crc32(body)
    reference = out/'state_service_reference.vhd'
    reference.write_text('library ieee;\nuse ieee.std_logic_1164.all;\n'
        'use ieee.numeric_std.all;\npackage state_service_reference is\n'
        '    constant CU32_EXPECTED_BODY_CRC : unsigned(31 downto 0) := x"'+
        format(expected_crc, '08X')+'";\nend package;\n', encoding='utf-8', newline='\n')
    sources = ['rtl/state/rabbitpunch_state_'+name+'.vhd' for name in (
        'layout', 'crc', 'header', 'preflight', 'semantics', 'image_buffer',
        'snapshot', 'slot_reader', 'image_validator', 'apply', 'image_words',
        'slot_writer', 'publish', 'service')]
    sources += [reference.relative_to(root).as_posix(), 'sim/state/state_service_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name in sources:
        snapshot = out/'inputs'/name
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes((root/name).read_bytes())
    attempt = dict(accepted=False, source_sha256=hashes, case_group=args.group,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        native_wall_limit_seconds=args.wall_timeout, scope='Unfinished attempt; not qualification.')
    (out/'attempt.json').write_text(json.dumps(attempt, indent=2)+'\n')
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_service_tb', '--assert-level=error', '--max-stack-alloc=0']]:
        if '--elab-run' in command:
            command.insert(command.index('--assert-level=error'), '-gGINT_CASE_GROUP='+str(args.group))
        try:
            result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                    timeout=args.wall_timeout, **NO_WINDOW)
        except subprocess.TimeoutExpired as error:
            def decoded(value):
                return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
            logs.append(decoded(error.stdout)+decoded(error.stderr))
            (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
            attempt.update(rejected_reason='Native process wall limit; no completion claim.',
                           log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest())
            (out/'attempt.json').write_text(json.dumps(attempt, indent=2)+'\n')
            raise SystemExit('Native GHDL child reached its wall limit; terminated and partial log retained: '+str(out)) from None
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1][-6000:]
    log = '\n'.join(logs)
    assert 'STATE_SERVICE_PASS' in log, log[-6000:]
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in hashes}
    groups = {0: 'Complete save/restore/counter/corrupt preflight/partial retry/DDR cancel suite.',
              1: 'Full body save/restore, independent CRC, repeated counter and corrupt preflight.',
              2: 'Partial-apply hold and complete full-body retry.',
              3: 'Cancellation after accepted DDR read with no machine acquisition/write.',
              4: 'Cancellation after accepted snapshot body read, FAIL cleanup and drained return without publication.'}
    report = dict(accepted=True, source_sha256=hashes, case_group=args.group,
        exercised=groups[args.group], expected_body_crc32=f'{expected_crc:08x}',
        independent_body_sha256=hashlib.sha256(body).hexdigest(),
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
        scope='Actual private image RAM/snapshot/header/CRC/semantics/validator/'
              'apply/publish/slot-reader/writer composition with delayed synthetic '
              'machine/body/DDR endpoints. Groups0..3 first construct a complete '
              '107280-byte image and check independent Python-zlib body CRC. '
              'The exercised field identifies the additional assertions in this '
              'bounded group. Protocol qualification only; no '
              'actual CPUs/chips/video, real game restoration, FPGA or hardware proof.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(json.dumps(report, indent=2)+'\n')
    print(log, end='')


if __name__ == '__main__':
    main()
