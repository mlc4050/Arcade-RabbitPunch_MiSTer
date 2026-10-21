#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Exercise real main-board capture, RAM borrowing and repeated continuation."""
import hashlib
import json
import shutil
import argparse
from coretools import core_root
from run_baselines import run_case


def board_sources():
    sources = ['rtl/state/vendor/konamigx/fx68k/' + filename for filename in
               ('fx68k.sv', 'fx68kAlu.sv', 'uaddrPla.sv')]
    sources += ['rtl/state/vendor/konamigx/gx_ss_m68k.sv']
    sources += ['rtl/state/' + filename + '.vhd' for filename in (
        'rabbitpunch_state_fx68k', 'rabbitpunch_m68k_capture',
        'rabbitpunch_capture_stack_undo', 'rabbitpunch_capture_phase',
        'rabbitpunch_state_maincpu')]
    sources += ['rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_decode.vhd',
        'rtl/jtframe/jtframe_draw.v', 'rtl/rabbitpunch_ram16.vhd',
        'rtl/rabbitpunch_board_memory.vhd', 'rtl/rabbitpunch_sprite_priority.vhd',
        'rtl/rabbitpunch_pixel_mixer.vhd', 'rtl/rabbitpunch_tile_row.vhd',
        'rtl/rabbitpunch_tile_lookup.vhd', 'rtl/rabbitpunch_tile_layer.vhd',
        'rtl/rabbitpunch_tiles.vhd', 'rtl/rabbitpunch_sprite_scan.vhd',
        'rtl/rabbitpunch_sprite_row.vhd', 'rtl/rabbitpunch_sprite_line.vhd',
        'rtl/rabbitpunch_sprites.vhd', 'rtl/rabbitpunch_bitmap_pixel.vhd',
        'rtl/rabbitpunch_video.vhd', 'rtl/rabbitpunch_palette_pixel.vhd',
        'rtl/rabbitpunch_rgb_video.vhd', 'rtl/rabbitpunch_board_video.vhd',
        'rtl/rabbitpunch_bus.vhd', 'rtl/rabbitpunch_fx68k.vhd', 'rtl/rabbitpunch_maincpu.vhd',
        'rtl/rabbitpunch_io.vhd', 'rtl/rabbitpunch_irq.vhd',
        'rtl/rabbitpunch_maintenance.vhd', 'rtl/rabbitpunch_bus_owner.vhd',
        'rtl/state/rabbitpunch_state_main_bus.vhd', 'rtl/rabbitpunch_cheats.vhd', 'rtl/rabbitpunch_board.vhd',
        'sim/state/state_board_tb.vhd']
    return sources


def main():
    root = core_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='')
    parser.add_argument('--wall-timeout', type=int, default=180)
    args = parser.parse_args()
    assert 1 <= args.wall_timeout <= 900
    assert all(character.isalnum() or character == '_' for character in args.label)
    manifest = json.loads((root / 'rtl/state/vendor/konamigx/vendor_manifest.json').read_text())
    for item in manifest['files']:
        assert hashlib.sha256((root / item['target']).read_bytes()).hexdigest() == item['sha256'], item['target']
    name = 'state_board_continuation' + ('_' + args.label if args.label else '')
    out = root / 'debug/baselines' / name
    for filename in ('microrom.mem', 'nanorom.mem'):
        target = out / 'rtl/cpu/fx68k' / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / 'rtl/state/vendor/konamigx/fx68k' / filename, target)
    sources = board_sources()
    hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result = run_case(name, sources, 'state_board_tb', '15 ms', 'STATE_BOARD_PASS',
                      sim_args=('-suppress', '8315', '-suppress', '8360'), wall_timeout=args.wall_timeout)
    assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result.update(source_sha256=hashes,
        log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
        scope='Actual main board with unchanged GX capture CPU, production bus owner, '
              'Intel RAM models for all five physical banks and real IO/IRQ registers. '
              'Delayed synthetic program ROM, complete 16KiB work-RAM reload, both byte '
              'lanes in every RAM bank, preserved stack sentinel, masked pending IRQ, '
              'retained user pause, three 400-write and 512-clock exact continuations. '
              'Renderer held in reset during bank access; no rendered pixels, sound '
              'parent, real game ROM, DDR, full-machine state service or hardware proof.')
    receipt = 'state_board_' + args.label + '_checks.json' if args.label else 'state_board_checks.json'
    (root / 'docs/reference' / receipt).write_text(
        json.dumps(result, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
