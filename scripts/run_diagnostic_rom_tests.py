# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Execute original diagnostic firmware on unchanged fx68k, including a corrupt-ROM control."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from coretools import core_root, NO_WINDOW
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full-fill', action='store_true')
    args = parser.parse_args()
    root = core_root()
    mode = 'full' if args.full_fill else 'short'
    subprocess.check_call([sys.executable, str(root / 'scripts/build_diagnostic_rom.py')] +
                          ([] if args.full_fill else ['--test-short']), **NO_WINDOW)
    sources = ['rtl/cpu/fx68k/fx68k.sv', 'rtl/cpu/fx68k/fx68kAlu.sv', 'rtl/cpu/fx68k/uaddrPla.sv',
               'rtl/rabbitpunch_fx68k.vhd', 'rtl/rabbitpunch_bus.vhd', 'rtl/rabbitpunch_maincpu.vhd', 'sim/board/diagnostic_rom_tb.vhd']
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    results = []
    for corrupt in (False, True):
        case = f'diagnostic_rom_{mode}_' + ('corrupt' if corrupt else 'known')
        directory = root / 'debug/baselines' / case
        directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / f'debug/diagnostic/{mode}/maincpu.hex', directory / 'maincpu.hex')
        marker = 'DIAGNOSTIC_ROM_NEGATIVE_PASS' if corrupt else 'DIAGNOSTIC_ROM_PASS'
        result = run_case(case, sources, 'diagnostic_rom_tb', '201 ms', marker, wall_timeout=1800,
            sim_args=(f'-gGINT_FILL_WORDS={32768 if args.full_fill else 64}',
                      f'-gGBOOL_CORRUPT_ROM={str(corrupt).lower()}'))
        assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
        result.update(source_sha256=hashes, bitmap_fill_words=32768 if args.full_fill else 64,
            corrupt_rom=corrupt, log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
            fixture_sha256=hashlib.sha256((directory / 'maincpu.hex').read_bytes()).hexdigest(),
            scope='Real fx68k instruction execution, delayed behavioral bus replies, original diagnostic ROM, ordered bitmap fill, known/corrupt ROM-word branch and controls-to-RAM heartbeat; no native SDRAM/BRAM, video output or hardware execution proof')
        results.append(result)
    (root / f'docs/reference/diagnostic_rom_{mode}_checks.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
