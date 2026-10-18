# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check native/direct bypass and unchanged framework scanline video modes."""
import argparse
import hashlib
import json
import shutil
import subprocess
from build_staged import quartus_child_environment
from coretools import quartus_bin, NO_WINDOW
from hwlock import require_no_jtag
from pathlib import Path
from coretools import core_root
from run_baselines import run_case

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--netlist', help='Existing Quartus functional netlist relative to core root; default exports the staged video-options fit')
parser.add_argument('--only', type=int, choices=range(7), help='One mode for diagnostics; report remains private')
args = parser.parse_args()
root = core_root()
stage = root / 'build'
built_commit = (stage / 'BUILT_COMMIT').read_text().split()[0]
if args.netlist is None:
    require_no_jtag('video-options functional netlist export')
    if (stage / '.build_running').exists():
        raise SystemExit('Wait for the staged fit to finish before exporting its database')
    project = stage / 'rtl/synth_check/video_options'
    compile_log = (stage / 'q_video_options_check.log').read_text(errors='replace')
    if 'Full Compilation was successful' not in compile_log:
        raise SystemExit('Video-options compilation did not finish successfully')
    destination = root / 'debug/netlists' / f'video_options_{built_commit[:7]}'
    destination.mkdir(parents=True, exist_ok=True)
    with (destination / 'export.log').open('w') as log:
        exported = subprocess.run([str(quartus_bin(root) / 'quartus_eda.exe'), 'video_options_check',
            '--simulation', '--functional=on', '--tool=modelsim', '--format=verilog'],
            cwd=project, env=quartus_child_environment(root), stdout=log, stderr=subprocess.STDOUT,
            timeout=120, **NO_WINDOW)
    if exported.returncode:
        raise SystemExit(f'Netlist export failed: {destination / "export.log"}')
    netlist = destination / 'video_options_check.vo'
    shutil.copy2(project / 'simulation/modelsim/video_options_check.vo', netlist)
else:
    netlist = (root / args.netlist).resolve()
if not netlist.is_relative_to(root.resolve()) or not netlist.is_file():
    parser.error('Netlist must be an existing generated file within this D-drive core checkout')
sources = [netlist.relative_to(root).as_posix(), 'sim/video/video_options_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
results = []
for mode in ([args.only] if args.only is not None else range(7)):
    result = run_case(f'video_options_{mode}', sources, 'video_options_tb', '25 ms',
                      'VIDEO_OPTIONS_PASS', sim_args=libraries + [f'-gGINT_MODE={mode}'], wall_timeout=180)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(mode=mode, fitted_commit=built_commit, source_sha256=hashes,
        log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
        scope='Quartus-generated functional netlist, no SDF; native/direct bypass every clock; framework forced doubling, HQ2x and scanline modes with real /7 clock enables and full raster; flat-field RGB and visible line widths after two startup frames; no detailed HQ edge-filter or physical-output proof')
    results.append(result)
    (root / 'debug/video_options_partial_checks.json').write_text(json.dumps(results, indent=2) + '\n')
if args.only is None:
    (root / 'docs/reference/video_options_checks.json').write_text(json.dumps(results, indent=2) + '\n')
