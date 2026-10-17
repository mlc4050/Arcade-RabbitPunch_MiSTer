# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check downloaded programs with production single-clock timing wiring."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
from run_platform_tests import platform_sources


def machine_sources():
    return platform_sources()[:-1] + [
        'rtl/rabbitpunch_clock_enables.vhd', 'rtl/rabbitpunch_raster.vhd',
        'rtl/rabbitpunch_scanline_scheduler.vhd', 'rtl/rabbitpunch_video_output.vhd',
        'rtl/rabbitpunch_scanout.vhd', 'rtl/rabbitpunch_machine.vhd',
        'sim/board/machine_tb.vhd']


def main():
    root = core_root()
    sources = machine_sources()
    hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
    result = run_case('machine', sources, 'machine_tb', '1 ms', 'MACHINE_PASS', wall_timeout=300)
    assert hashes == {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
    result.update(source_sha256=hashes,
        log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
        scope='Production machine wiring with real CPU, audio enables, native SDRAM/chip model and continuous /7 pixel cadence through loading, pause, hot replacement, reset and partial-image recovery; synthetic 64-byte main programs. Completes before the first vertical interrupt/render window; no full-frame, game audio, PLL or hardware proof; sound ROM is absent and vendor unknown-state warnings are expected, audio function is not scored')
    (root / 'docs/reference/machine_checks.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
