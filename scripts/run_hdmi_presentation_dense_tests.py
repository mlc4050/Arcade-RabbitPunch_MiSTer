# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Score all native pixels with a compressed raster to bound Starter netlist cost."""
import argparse
import json
from coretools import core_root
from crt_hq_reference import LIBRARIES, sha256
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fitted', action='store_true')
parser.add_argument('--wall-timeout', type=int, default=1800)
args = parser.parse_args()
if args.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
if args.fitted:
    proof = json.loads((root / 'docs/reference/hdmi_presentation_netlist_checks.json').read_text())
    netlist = 'debug/netlists/hdmi_presentation_' + proof['commit'][:7] + '/hdmi_presentation_check.vo'
    assert sha256(root / netlist) == proof['netlist_sha256']
    sources = [netlist]
else:
    sources = []
    for name in ('hdmi_rotation', 'video_aspect'):
        proof = json.loads((root / 'docs/reference' / (name + '_netlist_checks.json')).read_text())
        netlist = 'debug/netlists/' + name + '_' + proof['commit'][:7] + '/' + name + '_check.vo'
        assert sha256(root / netlist) == proof['netlist_sha256']
        sources.append(netlist)
    sources += ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
                'rtl/rabbitpunch_rotation_transport.vhd', 'rtl/rabbitpunch_hdmi_presentation.vhd']

reference = json.loads((root / 'docs/reference/hdmi_presentation_checks.json').read_text())
template = root / 'debug/hdmi_presentation_tb.vhd'
assert sha256(template) == reference['cases'][0]['source_sha256'][template.relative_to(root).as_posix()]
text = template.read_text()
if args.fitted:
    original = '        generic map (\n            GINT_FRAME_PIXELS => GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT\n        )\n'
    assert text.count(original) == 1
    text = text.replace(original, '')
for original, replacement, expected in [
    ("s_pixel_enable <= '1' when sint_phase = 6 else '0';", "s_pixel_enable <= '1';", 1),
    ('if (sint_phase = 6) then', 'if (true) then', 1),
    ("s_busy <= '1' when sint_stall_phase < 96 or\n        (sint_stall_phase >= 256 and sint_stall_phase < 320) else '0';",
     "s_busy <= '1' when sint_stall_phase < 4 else '0';", 1),
    ('vint_test_frame : natural := 3;', 'vint_test_frame : natural := 4;', 1),
    ('sint_frames >= 3', 'sint_frames >= 4', 2),
    ('sint_frames <= 3 + GINT_TEST_FRAMES', 'sint_frames <= 4 + GINT_TEST_FRAMES', 1),
    ('sint_frames = 3 + GINT_TEST_FRAMES', 'sint_frames = 4 + GINT_TEST_FRAMES', 1),
    ('wait for 1 ms;', 'wait for 100 us;', 1),
]:
    assert text.count(original) == expected, original
    text = text.replace(original, replacement)
# Busy overlaps an unstoppable visible source. Complete accepted-image checks
# therefore also require real queued packets rather than empty direct forwarding.
marker = '    signal sint_stall_phase : natural range 0 to 511 := 0;'
assert text.count(marker) == 1
text = text.replace(marker, marker + '\n    signal sint_visible_stalls : natural := 0;')
marker = '            if (sint_stall_phase = 511) then'
text = text.replace(marker, '''            if (s_busy = '1' and s_data_enable = '1') then
                sint_visible_stalls <= sint_visible_stalls + 1;
            end if;
''' + marker)
marker = '                    report "HDMI_PRESENTATION_PASS frames="'
assert text.count(marker) == 1
text = text.replace(marker, '''                    assert (sint_visible_stalls > 0)
                        report "Dense fixture never queued visible traffic behind DDR busy" severity failure;
''' + marker)
suffix = '_fitted' if args.fitted else '_rtl'
bench = root / ('debug/hdmi_presentation_dense' + suffix + '_tb.vhd')
bench.write_text(text)
sources.append(bench.relative_to(root).as_posix())
hashes = {name: sha256(root / name) for name in sources}
geometry = ['-gGINT_VISIBLE_WIDTH=288', '-gGINT_VISIBLE_HEIGHT=216', '-gGINT_TOTAL_WIDTH=304',
            '-gGINT_TOTAL_HEIGHT=224', '-gGINT_HORIZONTAL_SYNC_START=296', '-gGINT_HORIZONTAL_SYNC_END=300',
            '-gGINT_VERTICAL_SYNC_START=220', '-gGINT_VERTICAL_SYNC_END=222', '-gGINT_TEST_FRAMES=1']
results = []
for direction in (False, True):
    result = run_case('hdmi_presentation_dense' + suffix + '_' + ('ccw' if direction else 'cw'),
        sources, 'hdmi_rotation_buffers_tb', '100 ms', 'HDMI_PRESENTATION_PASS',
        sim_args=LIBRARIES + geometry + ['-gGBOOL_COUNTERCLOCKWISE=' + str(direction).lower()],
        wall_timeout=args.wall_timeout)
    assert hashes == {name: sha256(root / name) for name in sources}
    result.update(counterclockwise=direction, pixels=62208, scored_frames=1, warmup_frames=4,
                  source_sha256=hashes, log_sha256=sha256(root / result['log']))
    results.append(result)
    (root / ('debug/hdmi_presentation_dense' + suffix + '_partial_checks.json')).write_text(json.dumps(results, indent=2) + '\n')
report = dict(cases=results, fitted=args.fitted, fitted_commit=proof['commit'] if args.fitted else None,
              visible=[288, 216], total=[304, 224], pixel_divider=1, busy_cycles_per_512=4,
              template_sha256=sha256(template),
              scope='Compressed synthetic stimulus, not production raster or /7 cadence: all 62208 unique native pixels, exact CW/CCW DDR addresses/colours/byte masks, safe known buffer slots, advancing reads, queue drain and complete-image publication. Four-cycle DDR stalls overlap visible traffic and require queued packets. Fixed 62208-pixel fitted guard is unchanged. Functional netlist without SDF when fitted; otherwise controller RTL around qualified donor/aspect netlists. Production raster/stall proofs remain separate; no full-shell, executing-game, physical or measured latency claim.')
(root / ('docs/reference/hdmi_presentation_dense' + suffix + '_checks.json')).write_text(json.dumps(report, indent=2) + '\n')
