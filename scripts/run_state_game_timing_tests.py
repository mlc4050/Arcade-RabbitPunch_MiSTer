# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify held guest timing with continuous physical sync and aligned release."""
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
    require_no_jtag('RabbitPunch guest timing and continuous physical sync native test')
    root = core_root()
    assert args.label.replace('_', '').isalnum() or not args.label
    out = root/'debug/ghdl'/('state_game_timing'+('_'+args.label if args.label else ''))
    if args.label:
        assert not out.exists(), 'Preserve previous attempts'
    out.mkdir(parents=True, exist_ok=True)
    sources = ['rtl/rabbitpunch_clock_enables.vhd', 'rtl/rabbitpunch_raster.vhd',
               'rtl/state/rabbitpunch_state_game_timing.vhd', 'rtl/rabbitpunch_scanline_scheduler.vhd',
               'rtl/rabbitpunch_video_output.vhd', 'rtl/rabbitpunch_scanout.vhd',
               'sim/state/state_game_timing_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    logs = []
    for command in [[args.ghdl, '-a', '--std=08', '--workdir='+str(out), *sources],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_game_timing_tb', '--assert-level=error'],
                    [args.ghdl, '--elab-run', '--std=08', '--workdir='+str(out),
                     'state_game_timing_tb', '-gGBOOL_FULL_SIZE=true', '-gGINT_PHASE_CASES=1',
                     '--assert-level=error']]:
        try:
            result = subprocess.run(command, cwd=root, text=True, capture_output=True,
                                    timeout=90, **NO_WINDOW)
        except subprocess.TimeoutExpired as error:
            decode = lambda value: value.decode(errors='replace') if isinstance(value, bytes) else value or ''
            logs.append(decode(error.stdout)+decode(error.stderr)+'\nTIMEOUT90 seconds\n')
            (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
            raise
        logs.append(result.stdout+result.stderr)
        (out/'result.log').write_text('\n'.join(logs), encoding='utf-8', newline='\n')
        assert result.returncode == 0, logs[-1]
    log = '\n'.join(logs)
    assert log.count('STATE_GAME_TIMING_PASS') == 2, log
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(accepted=True, source_sha256=hashes,
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
                  prior_timeout='debug/fit_archive/game_timing_full_phase_timeout: full-size seven-phase sweep exceeded90s; not accepted; original source retained',
                  scope='Independent integer recurrence checks all guest clock enables, half-phase and IRQ events plus continuous physical raster/pixel/HSync/VSync. Compact72x16 geometry covers seven pixel phases,21 repeated restored field loads and seven aligned releases; default432x256 covers one full-frame alignment,three restored loads and one release. Each release has12000 exact continuation clocks. Actual native scanout with default and state timing selected has identical physical metadata every clock through holds/loads; presentation muted. No RGB renderer/CRT hardware or whole-game restore qualification.')
    report['modulo128_phase_checked'] = True
    report_name = 'state_game_timing'+('_'+args.label if args.label else '')+'_checks.json'
    (root/'docs/reference'/report_name).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print(log, end='')


if __name__ == '__main__':
    main()
