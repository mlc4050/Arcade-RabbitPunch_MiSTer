# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check native/direct bypass and unchanged framework scanline video modes."""
import argparse
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--netlist', required=True, help='Quartus functional netlist relative to core root')
args = parser.parse_args()
root = core_root()
sources = [args.netlist, 'sim/video/video_options_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
results = []
for mode in range(7):
    result = run_case(f'video_options_{mode}', sources, 'video_options_tb', '25 ms',
                      'VIDEO_OPTIONS_PASS', sim_args=libraries + [f'-gGINT_MODE={mode}'], wall_timeout=180)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(mode=mode, source_sha256=hashes,
        log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
        scope='Quartus-generated functional netlist, no SDF; native/direct bypass every clock; framework forced doubling, HQ2x and scanline modes with real /7 clock enables and full raster; flat-field RGB and visible line widths after two startup frames; no detailed HQ edge-filter or physical-output proof')
    results.append(result)
    (root / 'debug/video_options_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n')
(root / 'docs/reference/video_options_checks.json').write_text(json.dumps(results, indent=2) + '\n')
