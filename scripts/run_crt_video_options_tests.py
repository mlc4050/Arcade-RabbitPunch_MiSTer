# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check the enabled CRT adapter feeding the qualified framework effects netlist."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only', type=int, nargs='+', choices=range(7))
parser.add_argument('--wall-timeout', type=int, default=1800)
args = parser.parse_args()
if args.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
fit = json.loads((root / 'docs/reference/video_options_synth.json').read_text())
proof = json.loads((root / 'docs/reference/video_options_checks.json').read_text())
netlist = 'debug/netlists/video_options_' + fit['commit'][:7] + '/video_options_check.vo'
expected = proof[0]['source_sha256'][netlist]
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == expected
sources = [netlist, 'rtl/video/crt_adjust/crt_adjust.sv',
           'rtl/rabbitpunch_crt_adjust.vhd', 'sim/video/crt_video_options_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver')
             for item in ('-L', name)]
results = []
for mode in (args.only if args.only is not None else range(7)):
    result = run_case('crt_video_options_' + str(mode), sources, 'crt_video_options_tb',
                      '10 ms', 'CRT_VIDEO_OPTIONS_PASS',
                      sim_args=libraries + ['-gGINT_MODE=' + str(mode)], wall_timeout=args.wall_timeout)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(mode=mode, source_sha256=hashes, effects_fit_commit=fit['commit'],
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / 'debug/crt_video_options_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n')
report = dict(cases=results, visible=[288, 6], total=[432, 12], pixel_divider=7,
              requested_horizontal_size=2, requested_horizontal_position=8,
              scope='Enabled CRT RTL plus qualified synthesized framework effects. Production horizontal geometry; bounded vertical fixture. Exact flat-field RGB, line widths and visible totals; native/direct every-clock effects bypass; signed size disabled before doubling/HQ2x/scanline modes and retained in direct/native modes. No HQ2x edge-filter, extreme clipping, live-setting transition or physical monitor proof.')
name = 'crt_video_options' + ('_selected' if args.only is not None else '') + '_checks.json'
(root / 'docs/reference' / name).write_text(json.dumps(report, indent=2) + '\n')
