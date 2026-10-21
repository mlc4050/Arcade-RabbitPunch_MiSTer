# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check drained state cache normalization with actual SDRAM transactions."""
import hashlib
import json
import argparse
from coretools import core_root
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='')
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum() or not args.label
    root = core_root()
    case = 'state_roms_normalize'+('_'+args.label if args.label else '')
    if args.label:
        assert not (root/'debug/baselines'/case).exists(), 'Preserve previous attempts'
    sources = ['rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_sdram_types.vhd',
        'rtl/memory/sdram/sdram.sv', 'rtl/rabbitpunch_sdram.vhd',
        'rtl/rabbitpunch_rom_requests.vhd', 'rtl/rabbitpunch_rom_cache.vhd',
        'rtl/rabbitpunch_read_arbiter.vhd', 'rtl/rabbitpunch_audio_roms.vhd',
        'rtl/rabbitpunch_audio_rom_transport.vhd', 'rtl/state/rabbitpunch_state_sdram_phase.vhd', 'rtl/rabbitpunch_roms.vhd',
        'sim/vendor/sdram/sdram_chip_model_wide.sv', 'sim/state/state_roms_tb.vhd']
    hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result = run_case(case, sources, 'state_roms_tb', '2 ms',
                      'STATE_ROMS_PASS', wall_timeout=90)
    assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result.update(source_sha256=hashes,
        log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
        scope='Production ROM subsystem with actual SDRAM controller/chip model, '
              'loader and all five readers. Two image epochs, cache hits/refills, '
              'accepted sample read withdrawn before response, full debt drain '
              'then state cache invalidation without physical-controller reset. '
              'Exactly five new bursts after each normalization and zero for '
              'the warm repeat. Synthetic image bytes; no actual sound-chip '
              'capture, full-machine continuation or hardware timing proof.')
    report = 'state_roms'+('_'+args.label if args.label else '')+'_checks.json'
    (root / 'docs/reference'/report).write_text(
        json.dumps(result, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
