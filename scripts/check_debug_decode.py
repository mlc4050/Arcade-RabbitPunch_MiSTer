# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Exercise the probe decoder with mocked Tcl transport; never opens JTAG."""
import hashlib
import json
from pathlib import Path
import tkinter
from coretools import core_root

root = core_root()
script = root / 'scripts/read_issp.tcl'
# Distinct upper address bits and unsigned bit 31 exercise field ordering and sign.
words = [0x5250554E, 0x89ABCDEF, 12, 345, 67, 89, 62208,
         0x02FEDCBA, 0xCAFE, 0x0187F123, 0x01ABCDEF,
         431 | (255 << 9), 0x07FF, 123456, 9, 1]
packet = sum(word << (32 * index) for index, word in enumerate(words))

def evaluate(raw, argv=(), instance='RPUN'):
    runtime = tkinter.Tcl()
    output = []
    calls = []
    runtime.createcommand('capture_output', lambda *args: output.append(' '.join(map(str, args))) or '')
    runtime.createcommand('capture_transport', lambda *args: calls.append(args) or '')
    runtime.eval('proc puts {args} {capture_output {*}$args}')
    runtime.eval('proc exit {code} {error "EXIT:$code"}')
    runtime.eval('proc get_hardware_names {} {return MOCK}')
    runtime.eval('proc get_device_names {args} {return 5CSEBA6_MOCK}')
    runtime.eval('proc start_insystem_source_probe {args} {capture_transport start}')
    runtime.eval('proc end_insystem_source_probe {args} {capture_transport end}')
    runtime.call('set', 'mock_instances', f'{{0 1 512 {instance}}}')
    runtime.eval('proc get_insystem_source_probe_instance_info {args} {return $::mock_instances}')
    runtime.call('set', 'mock_raw', raw)
    runtime.eval('proc read_probe_data {args} {capture_transport read; return $::mock_raw}')
    runtime.call('set', 'argv', tuple(argv))
    error = None
    try:
        runtime.call('source', str(script))
    except tkinter.TclError as failure:
        error = str(failure)
    return output, calls, error

raw = f'{packet:0512b}'
output, calls, error = evaluate(raw, ('RPUN',))
assert error is None, error
fields = dict(line.strip().split() for line in output if line.startswith('  '))
expected = {'core_tag': '0x5250554E', 'build_id': '0x89ABCDEF', 'frames': '12',
            'last_write_address': '0x00FEDCBA', 'last_write_bytes': '0x00000002',
            'last_write_data': '0x0000CAFE', 'last_sound_address': '0x0000F123',
            'last_sound_data': '0x00000087', 'last_sound_write': 'yes',
            'last_cpu_address': '0x00ABCDEF', 'last_cpu_write': 'yes',
            'beam_x': '431', 'beam_y': '255', 'underflow': 'yes',
            'framework_reset': 'yes', 'audio_samples': '123456', 'underflow_events': '9',
            'layout_version': '1'}
for name, value in expected.items():
    assert fields[name] == value, (name, fields[name], value)
assert calls == [('start',), ('read',), ('end',)]
checks = ['valid_registered_packet']
for name, bad_raw, argv, instance in [
    ('wrong_tag', f'{packet ^ 1:0512b}', (), 'RPUN'),
    ('wrong_layout', f'{packet ^ (1 << 480):0512b}', (), 'RPUN'),
    ('wrong_width', raw[1:], (), 'RPUN'),
    ('wrong_binary', raw[:200] + 'X' + raw[201:], (), 'RPUN'),
    ('unknown_instance', raw, (), 'OTHER'),
    ('missing_requested_instance', raw, ('NOPE',), 'RPUN'),
    ('read_only_clear', raw, ('RPUN', 'clear'), 'RPUN'),
    ('read_only_set', raw, ('RPUN', 'set', '1'), 'RPUN'),
    ('read_only_pulse', raw, ('RPUN', 'pulse', '1'), 'RPUN'),
]:
    output, calls, error = evaluate(bad_raw, argv, instance)
    assert error == 'EXIT:1', (name, error, output)
    if name.startswith('wrong_'):
        assert calls == [('start',), ('read',), ('end',)]
    else:
        assert calls == [], (name, calls)
    checks.append(name)
result = dict(checks=checks, decoded_fields=len(fields),
    source_sha256=hashlib.sha256(script.read_bytes()).hexdigest(),
    scope='Python-hosted Tcl decoder with mocked enumeration/read/session commands; valid bit ordering and fail-closed identity/layout/width/selection/read-only controls; no JTAG tool or hardware connection')
(root / 'docs/reference/debug_decode_checks.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'PASS debug decoder: {len(checks)} cases, {len(fields)} fields; no JTAG opened')
