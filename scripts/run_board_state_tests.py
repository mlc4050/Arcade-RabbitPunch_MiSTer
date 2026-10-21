# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify board-register and timing state ports with native VHDL tests."""
import hashlib
import json
import argparse
from coretools import core_root
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', nargs='+', choices=('state_memory', 'board_register_state', 'timing_state'))
    args = parser.parse_args()
    root = core_root()
    cases = [
        ('state_memory', ['rtl/rabbitpunch_layout.vhd',
         'rtl/rabbitpunch_decode.vhd', 'rtl/rabbitpunch_ram16.vhd',
         'rtl/rabbitpunch_ram8.vhd', 'rtl/rabbitpunch_board_memory.vhd',
         'rtl/rabbitpunch_memory.vhd', 'rtl/rabbitpunch_sound_bus.vhd',
         'rtl/state/rabbitpunch_state_memory.vhd', 'sim/state/state_memory_tb.vhd'],
         'state_memory_tb', '101 ms', 'STATE_MEMORY_PASS'),
        ('board_register_state', ['rtl/rabbitpunch_layout.vhd',
         'rtl/rabbitpunch_decode.vhd', 'rtl/rabbitpunch_io.vhd',
         'rtl/rabbitpunch_irq.vhd', 'sim/state/board_register_state_tb.vhd'],
         'board_register_state_tb', '101 us', 'BOARD_REGISTER_STATE_PASS'),
        ('timing_state', ['rtl/rabbitpunch_clock_enables.vhd',
         'rtl/rabbitpunch_raster.vhd', 'sim/state/timing_state_tb.vhd'],
         'timing_state_tb', '11 ms', 'TIMING_STATE_PASS'),
    ]
    results = []
    for name, sources, top, duration, marker in cases:
        if args.only and name not in args.only:
            continue
        hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest()
                  for name in sources}
        result = run_case(name, sources, top, duration, marker, wall_timeout=120)
        assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest()
                          for name in sources}, 'Sources changed during qualification'
        result['source_sha256'] = hashes
        result['log_sha256'] = hashlib.sha256((root/result['log']).read_bytes()).hexdigest()
        results.append(result)
        (root/('docs/reference/'+name+'_checks.json')).write_text(
            json.dumps(result, indent=2)+'\n', encoding='utf-8')
    # Keep independent case evidence when repairing only one test. Ignore any
    # older case whose sources no longer match this checkout.
    results = []
    for name, *_ in cases:
        path = root/('docs/reference/'+name+'_checks.json')
        if path.exists():
            result = json.loads(path.read_text())
            if all(hashlib.sha256((root/source).read_bytes()).hexdigest() == digest
                   for source, digest in result['source_sha256'].items()):
                results.append(result)
    report = dict(results=results, scope='Isolated native board I/O, IRQ and timing '
                  'state ports and all 106496 bytes of native main/sound RAM '
                  'through the standalone state-memory adapter. Eight register '
                  'round trips, full RAM capture/perturb/restore, canceled debt '
                  'draining, invalid addresses, and exact clock/beam '
                  'continuation. Production defaults retain normal behavior; '
                  'ports are not connected to a complete game state engine. '
                  'No CPU, sound-chip, DDR, OSD or hardware qualification.')
    (root/'docs/reference/board_state_checks.json').write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
