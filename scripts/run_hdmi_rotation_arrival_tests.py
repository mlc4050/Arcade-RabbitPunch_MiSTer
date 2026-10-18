# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Arrival checks of the unchanged rotation donor; no production connection."""
import hashlib
import json
import subprocess
import sys
from coretools import NO_WINDOW
from coretools import core_root
from run_baselines import run_case
root = core_root()
donor = root / 'rtl/video/rotation/screen_rotate_two.sv'
assert hashlib.sha256(donor.read_bytes()).hexdigest() == 'a704b114cc7d7c1684eb273ab98b436350a3ffb957b350fad975bb322ba11f9e'
subprocess.run([sys.executable, str(root / 'scripts/run_netlist_tests.py'), 'hdmi_rotation'], check=True, **NO_WINDOW)
first = json.loads((root / 'docs/reference/hdmi_rotation_netlist_checks.json').read_text())
netlist = 'debug/netlists/hdmi_rotation_' + first['commit'][:7] + '/hdmi_rotation_check.vo'
sources = [netlist, 'sim/video/hdmi_rotation_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
first.update(counterclockwise=False, pixels=128)
libraries = [item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
results = [first]
for direction in ('true',):
    result = run_case('rotation_arrival_' + direction, sources, 'hdmi_rotation_tb', '1 ms',
                      'HDMI_ROTATION_PASS', sim_args=libraries + ['-gGBOOL_COUNTERCLOCKWISE=' + direction], wall_timeout=120)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(counterclockwise=direction == 'true', pixels=128, source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
(root / 'docs/reference/hdmi_rotation_arrival_checks.json').write_text(json.dumps(dict(cases=results,
    scope='Quartus functional netlist of unchanged donor plus descriptive VHDL boundary. 16x8 nonuniform image at /7 enables: all CW/CCW DDR pixel addresses, colours, byte masks, unique pixels, framebuffer dimensions/stride/base and stable write-buffer selection after measurement warm-up. DDR busy is always zero, loader disconnected; no backpressure safety, full-size image, frame latency or physical output proof.'), indent=2) + '\n')
