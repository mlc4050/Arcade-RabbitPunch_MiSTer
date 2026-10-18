# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check the enabled CRT adapter feeding the qualified framework effects netlist."""
import argparse
import json
from concurrent.futures import ThreadPoolExecutor
from coretools import core_root
from run_baselines import run_case
from crt_hq_reference import LIBRARIES, capture_reference, pixels_at, sha256

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only', type=int, nargs='+', choices=range(7))
parser.add_argument('--compact', action='store_true', help='Use 64/96 horizontal geometry for a quick harness check')
parser.add_argument('--extended-rows', action='store_true', help='Use the longer 6-visible/12-total row fixture')
parser.add_argument('--wall-timeout', type=int, default=1800)
args = parser.parse_args()
if args.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
fit = json.loads((root / 'docs/reference/video_options_synth.json').read_text(encoding='utf-8'))
proof = json.loads((root / 'docs/reference/video_options_checks.json').read_text(encoding='utf-8'))
netlist = 'debug/netlists/video_options_' + fit['commit'][:7] + '/video_options_check.vo'
assert sha256(root / netlist) == proof[0]['source_sha256'][netlist]
sources = [netlist, 'rtl/video/crt_adjust/crt_adjust.sv',
           'rtl/rabbitpunch_crt_adjust.vhd', 'sim/video/crt_video_options_tb.vhd']
hashes = {name: sha256(root / name) for name in sources}
suffix = ('_compact' if args.compact else '') + ('_extended' if args.extended_rows else '') + ('_' + '_'.join(map(str, args.only)) if args.only is not None else '')
generics = []
if args.compact:
    generics += ['-gGINT_VISIBLE_WIDTH=64', '-gGINT_TOTAL_WIDTH=96', '-gGINT_HORIZONTAL_SYNC_START=80', '-gGINT_HORIZONTAL_SYNC_END=88']
if args.extended_rows:
    generics += ['-gGINT_VISIBLE_HEIGHT=6', '-gGINT_TOTAL_HEIGHT=12', '-gGINT_VERTICAL_SYNC_START=8', '-gGINT_VERTICAL_SYNC_END=10']
results = []
for mode in (args.only if args.only is not None else range(7)):
    name = 'crt_video_options_' + str(mode) + ('_compact' if args.compact else '') + ('_extended' if args.extended_rows else '_short')

    def run_adjusted():
        return run_case(name, sources, 'crt_video_options_tb', '10 ms', 'CRT_VIDEO_OPTIONS_PASS',
                        sim_args=LIBRARIES + ['-gGINT_MODE=' + str(mode)] + generics, wall_timeout=args.wall_timeout)

    if mode == 2:
        with ThreadPoolExecutor(max_workers=2) as pool:
            reference = pool.submit(capture_reference, root, netlist, args.compact, args.extended_rows, args.wall_timeout)
            result = run_adjusted()
            expected_pixels, reference_result = reference.result()
        actual = root / 'debug/baselines' / name / 'hq_pixels.hex'
        actual_pixels = pixels_at(actual, len(expected_pixels))
        differing = sum(actual_pixel != expected_pixel for actual_pixel, expected_pixel in zip(actual_pixels, expected_pixels))
        if differing:
            raise SystemExit(f'HQ2x differs from native black-blanking reference at {differing} pixels')
        result.update(compared_pixels=len(actual_pixels), differing_pixels=0, pixels_sha256=sha256(actual),
                      reference=reference_result)
    else:
        result = run_adjusted()
    assert hashes == {name: sha256(root / name) for name in sources}
    result.update(mode=mode, source_sha256=hashes, effects_fit_commit=fit['commit'],
                  log_sha256=sha256(root / result['log']))
    results.append(result)
    (root / ('debug/crt_video_options' + suffix + '_partial_checks.json')).write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
report = dict(cases=results, visible=[64 if args.compact else 288, 6 if args.extended_rows else 1],
              total=[96 if args.compact else 432, 12 if args.extended_rows else 4], pixel_divider=7,
              requested_horizontal_size=2, requested_horizontal_position=8,
              scope='Enabled CRT RTL plus qualified synthesized framework effects. Bounded vertical fixture. HQ2x compares every pixel to an independent native framework capture with black blanking, not raw MAME; other modes check flat RGB. All modes check line widths and visible totals. Native/direct checks every-clock effects bypass. No patterned-edge algorithm, extreme clipping, live-setting transition or physical monitor proof.')
(root / 'docs/reference' / ('crt_video_options' + suffix + '_checks.json')).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
