# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare complete native images through the fitted HDMI presentation controller."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
proof = json.loads((root / 'docs/reference/hdmi_presentation_netlist_checks.json').read_text(encoding='utf-8'))
netlist = 'debug/netlists/hdmi_presentation_' + proof['commit'][:7] + '/hdmi_presentation_check.vo'
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == proof['netlist_sha256']
rtl = json.loads((root / 'docs/reference/hdmi_presentation_checks.json').read_text(encoding='utf-8'))
template = root / 'debug/hdmi_presentation_tb.vhd'
assert hashlib.sha256(template.read_bytes()).hexdigest() == rtl['cases'][0]['source_sha256'][template.relative_to(root).as_posix()]
text = template.read_text(encoding='utf-8')
generic_map = '        generic map (\n            GINT_FRAME_PIXELS => GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT\n        )\n'
assert text.count(generic_map) == 1
bench = root / 'debug/hdmi_presentation_netlist_pixels_tb.vhd'
bench.write_text(text.replace(generic_map, ''), encoding='utf-8')
sources = [netlist, bench.relative_to(root).as_posix()]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver') for item in ('-L', name)]
geometry = ['-gGINT_VISIBLE_WIDTH=288', '-gGINT_VISIBLE_HEIGHT=216', '-gGINT_TOTAL_WIDTH=432',
            '-gGINT_TOTAL_HEIGHT=256', '-gGINT_HORIZONTAL_SYNC_START=352', '-gGINT_HORIZONTAL_SYNC_END=392',
            '-gGINT_VERTICAL_SYNC_START=232', '-gGINT_VERTICAL_SYNC_END=240', '-gGINT_TEST_FRAMES=1']
results = []
for direction in (False, True):
    result = run_case('hdmi_presentation_fitted_' + ('ccw' if direction else 'cw'), sources,
        'hdmi_rotation_buffers_tb', '100 ms', 'HDMI_PRESENTATION_PASS', sim_args=libraries + geometry +
        ['-gGBOOL_COUNTERCLOCKWISE=' + str(direction).lower()], wall_timeout=1800)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(commit=proof['commit'], counterclockwise=direction, frames=1, pixels=62208, source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / 'debug/hdmi_presentation_netlist_pixels_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
(root / 'docs/reference/hdmi_presentation_netlist_pixels_checks.json').write_text(json.dumps(dict(cases=results,
    template_sha256=hashlib.sha256(template.read_bytes()).hexdigest(),
    scope='Complete fitted controller with optimized 512x80 packet RAM and production 62208-pixel validity count. Each CW/CCW case checks one complete native 288x216 image after warmup, all DDR pixel addresses/colours/byte masks, known safe buffer slots, read progress, queue drain, 3:4 metadata and publication only after a complete image, under bounded DDR stalls. Functional netlist without SDF; routed timing is separate. Not a full MiSTer fit, executing game, arbitrary phase/frequency, hardware or measured-latency proof.'), indent=2) + '\n', encoding='utf-8')
