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
first.update(counterclockwise=False, pixels=128, framebuffer_phase=0, low_latency=False)
libraries = [item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
results = [first]
cases = [('true' if low else 'false', False, phase, low)
         for phase in (-2,-1,0,1,2) for low in (False,True) if phase != 0 or low]
cases += [('false',True,0,False),('true',True,0,False)]
for direction, full, phase, low in cases:
    result = run_case('rotation_arrival_' + direction + ('_full' if full else '') + '_phase' + str(phase) + ('_low' if low else ''), sources, 'hdmi_rotation_tb', '100 ms',
                      'HDMI_ROTATION_PASS', sim_args=libraries + ['-gGBOOL_COUNTERCLOCKWISE=' + direction, '-gGINT_FRAMEBUFFER_PHASE=' + str(phase), '-gGBOOL_LOW_LATENCY=' + str(low).lower()] + (['-gGINT_VISIBLE_WIDTH=288', '-gGINT_VISIBLE_HEIGHT=216', '-gGINT_TOTAL_WIDTH=432', '-gGINT_TOTAL_HEIGHT=256', '-gGINT_HORIZONTAL_SYNC_START=352', '-gGINT_HORIZONTAL_SYNC_END=392', '-gGINT_VERTICAL_SYNC_START=232', '-gGINT_VERTICAL_SYNC_END=240'] if full else []), wall_timeout=1800)
    assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    result.update(counterclockwise=direction == 'true', pixels=62208 if full else 128, full_raster=full, framebuffer_phase=phase, low_latency=low, source_sha256=hashes,
                  log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest())
    results.append(result)
    (root / "debug/hdmi_rotation_arrival_partial_checks.json").write_text(json.dumps(results, indent=2) + "\n")
(root / 'docs/reference/hdmi_rotation_arrival_checks.json').write_text(json.dumps(dict(cases=results,
    scope='Quartus functional netlist of unchanged donor plus descriptive VHDL boundary. 16x8 controls and full 288x216 images in the 432x256 native raster at /7 enables: all CW/CCW DDR pixel addresses, colours, byte masks, unique pixels, framebuffer dimensions/stride/base and stable write-buffer selection after measurement warm-up. VHDL adapter serializes coincident source/destination buffer advances; every visible write must target a buffer distinct from the advertised read buffer. Compact cases cover FB_VBL phases -2..+2 system clocks and both low-latency/triple-buffer modes. DDR busy is always zero, loader disconnected; no backpressure safety, frame latency or physical output proof.'), indent=2) + '\n')
