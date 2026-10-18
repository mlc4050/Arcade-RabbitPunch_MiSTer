# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare patterned HQ2x through CRT adjustment to the independent native path."""
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from coretools import core_root
from crt_hq_reference import LIBRARIES, pixels_at, sha256
from run_baselines import run_case

root = core_root()
proof = json.loads((root / 'docs/reference/video_options_checks.json').read_text())
fit = json.loads((root / 'docs/reference/video_options_synth.json').read_text())
netlist = 'debug/netlists/video_options_' + fit['commit'][:7] + '/video_options_check.vo'
assert sha256(root / netlist) == proof[0]['source_sha256'][netlist]
# Asymmetric diagonals, bars and alternating rows expose row/column displacement
# and channel swaps. Both fixtures generate the same input coordinates.
colours = {
    'red': 'to_unsigned((sint_x * 13 + sint_y * 71) mod 256, 8)',
    'green': 'to_unsigned(((sint_x / 4) * 97 + sint_y * 43) mod 256, 8)',
    'blue': 'to_unsigned(((sint_x + sint_y) mod 2) * 229 + 17, 8)',
}
geometry = ['-gGINT_MODE=2', '-gGINT_VISIBLE_WIDTH=64', '-gGINT_TOTAL_WIDTH=96',
            '-gGINT_HORIZONTAL_SYNC_START=80', '-gGINT_HORIZONTAL_SYNC_END=88',
            '-gGINT_VISIBLE_HEIGHT=4', '-gGINT_TOTAL_HEIGHT=10',
            '-gGINT_VERTICAL_SYNC_START=6', '-gGINT_VERTICAL_SYNC_END=8']


def fixture(adjusted):
    source = 'sim/video/' + ('crt_video_options_tb.vhd' if adjusted else 'video_options_tb.vhd')
    text = (root / source).read_text()
    if not adjusted:
        text = text.replace('use std.env.all;', 'use std.env.all;\nuse std.textio.all;')
        start = text.index('                assert (su8_output_red = x"31"')
        end = text.index('severity failure;', start) + len('severity failure;')
        text = text[:start] + '''                write(v_line, to_hstring(su8_output_red & su8_output_green & su8_output_blue));
                writeline(v_pixels, v_line);''' + text[end:]
        text = text.replace('    monitor : process\n', '''    monitor : process
        file v_pixels : text open write_mode is "pixels.hex";
        variable v_line : line;
''')
    for colour, value in zip(colours, ('31', '79', 'C5')):
        original = 'su8_' + colour + ' <= x"' + value + '";'
        assert text.count(original) == 1
        expression = colours[colour]
        # CRT adapter blacks blanking; match that input policy independently.
        if not adjusted:
            expression += " when s_hb = '0' and s_vb = '0' else (others => '0')"
        text = text.replace(original, 'su8_' + colour + ' <= ' + expression + ';')
    name = 'crt_hq_pattern_' + ('adjusted' if adjusted else 'native')
    bench = root / 'debug' / (name + '_tb.vhd')
    bench.write_text(text)
    sources = [netlist]
    if adjusted:
        sources += ['rtl/video/crt_adjust/crt_adjust.sv', 'rtl/rabbitpunch_crt_adjust.vhd']
    sources += [bench.relative_to(root).as_posix()]
    hashes = {path: sha256(root / path) for path in sources}
    marker = 'CRT_VIDEO_OPTIONS_PASS' if adjusted else 'VIDEO_OPTIONS_PASS'
    result = run_case(name, sources, 'crt_video_options_tb' if adjusted else 'video_options_tb',
                      '10 ms', marker, sim_args=LIBRARIES + geometry, wall_timeout=1200)
    assert hashes == {path: sha256(root / path) for path in sources}
    capture = root / 'debug/baselines' / name / ('hq_pixels.hex' if adjusted else 'pixels.hex')
    pixels = pixels_at(capture, 4 * 64 * 4)
    result.update(source_sha256=hashes, template_sha256=sha256(root / source),
                  log_sha256=sha256(root / result['log']), pixels_sha256=sha256(capture))
    return pixels, result


with ThreadPoolExecutor(max_workers=2) as pool:
    native = pool.submit(fixture, False)
    adjusted = pool.submit(fixture, True)
    expected, native_result = native.result()
    actual, adjusted_result = adjusted.result()
differences = [index for index, pair in enumerate(zip(expected, actual)) if pair[0] != pair[1]]
result = dict(cases=[native_result, adjusted_result], compared_pixels=len(actual),
              differing_pixels=len(differences), first_differences=differences[:16],
              scope='64x4 patterned input, /7 pixel enable, complete 128x8 HQ2x image through enabled CRT horizontal position +8 with size gated off in doubled mode, versus independent native qualified framework with black blanking. Exact algorithm integration comparison; no MAME HQ reference, full native raster, clipping, live transition or physical display claim.')
path = root / ('docs/reference/crt_hq_pattern_checks.json' if not differences else 'debug/crt_hq_pattern_rejected.json')
path.write_text(json.dumps(result, indent=2) + '\n')
if differences:
    raise SystemExit(f'Patterned CRT/HQ2x differs at {len(differences)} pixels; see {path}')
print(f'PASS patterned CRT/HQ2x: {len(actual)} exact known pixels', flush=True)
