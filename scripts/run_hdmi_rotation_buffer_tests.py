# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check isolated rotation slot safety and read progress over multiple frames."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compact-only', action='store_true')
args = parser.parse_args()
root = core_root()
proof = json.loads((root / 'docs/reference/hdmi_rotation_netlist_checks.json').read_text(encoding='utf-8'))
netlist = 'debug/netlists/hdmi_rotation_' + proof['commit'][:7] + '/hdmi_rotation_check.vo'
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == proof['netlist_sha256']
sources = [netlist, 'sim/video/hdmi_rotation_buffers_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver')
             for item in ('-L', name)]
geometry = ['-gGINT_VISIBLE_WIDTH=288', '-gGINT_VISIBLE_HEIGHT=216', '-gGINT_TOTAL_WIDTH=432',
            '-gGINT_TOTAL_HEIGHT=256', '-gGINT_HORIZONTAL_SYNC_START=352', '-gGINT_HORIZONTAL_SYNC_END=392',
            '-gGINT_VERTICAL_SYNC_START=232', '-gGINT_VERTICAL_SYNC_END=240']
cases = [(False, phase, low, False) for phase in (-2, -1, 0, 1, 2) for low in (False, True)]
if not args.compact_only:
    cases += [(direction, 0, False, True) for direction in (False, True)]
results = []
for direction, phase, low, full in cases:
    name = 'rotation_buffers_' + ('ccw' if direction else 'cw') + '_phase' + str(phase) + ('_request_low' if low else '') + ('_full' if full else '')
    generics = ['-gGBOOL_COUNTERCLOCKWISE=' + str(direction).lower(), '-gGINT_FRAMEBUFFER_PHASE=' + str(phase),
                '-gGBOOL_LOW_LATENCY=' + str(low).lower()]
    result = run_case(name, sources, 'hdmi_rotation_buffers_tb', '100 ms', 'HDMI_ROTATION_BUFFERS_PASS',
                      sim_args=libraries + generics + (geometry if full else []), wall_timeout=600)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(commit=proof['commit'], counterclockwise=direction, framebuffer_phase=phase,
                  low_latency_request=low, actual_buffer_policy='triple', frames=3,
                  pixels=3 * (62208 if full else 128), source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / 'debug/hdmi_rotation_buffers_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
(root / 'docs/reference/hdmi_rotation_buffers_checks.json').write_text(json.dumps(dict(cases=results,
    scope='Fitted isolated VHDL event serializer plus unchanged rotation donor in safe triple-buffer mode. Three complete scored frames per case: every pixel address/colour/mask, known slot indices, no visible write to the advertised read slot, and at least one read-slot change per frame. VS/FB_VBL stimulus changes between clock edges; compact phases -2..+2 system clocks, including coincident events. Low-latency requests deliberately retain triple buffering. Full native CW/CCW geometry included unless compact-only. No valid-image publication, queue-drain/loader handoff, arbitrary phase/frequency, measured latency or hardware proof.'), indent=2) + '\n', encoding='utf-8')
