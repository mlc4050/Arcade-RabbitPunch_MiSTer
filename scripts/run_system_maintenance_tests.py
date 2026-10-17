# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Verify paused maintenance and reset/load ownership with executing 68000 code."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


from run_system_download_tests import system_sources


def main():
    root = core_root()
    sources = system_sources()[:-1] + ['sim/board/system_maintenance_tb.vhd']
    result = run_case('system_maintenance', sources, 'system_maintenance_tb', '1 ms', 'SYSTEM_MAINTENANCE_PASS', wall_timeout=300)
    result.update(source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
        scope='Executing fx68k and complete logical system with production queued maintenance, native work RAM and SDRAM loader: CPU consumes restored byte pairs, coordinated CPU pause, both byte lanes/end address, pending maintenance reset drain, hot replacement on offered board IO write and queued ROM fetch, independent user-pause preservation; synthetic 64-byte programs, audio/video idle, no HPS persistence or physical timing proof')
    (root / 'docs/reference/system_maintenance_checks.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
