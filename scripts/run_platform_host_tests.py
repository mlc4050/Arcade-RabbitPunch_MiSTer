# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Drive the actual synthesized HPS parser into the RTL logical platform."""
import hashlib
import json
import subprocess
from coretools import core_root, NO_WINDOW
from run_baselines import run_case
from run_platform_tests import platform_sources

root = core_root()
reference = json.loads((root / 'docs/reference/host_netlist_checks.json').read_text())
netlist = next(name for name in reference['source_sha256'] if name.endswith('.vo'))
if not (root / netlist).exists():
    raise SystemExit('Build the host target at the recorded host commit and run run_host_tests.py to regenerate its private functional netlist')
if hashlib.sha256((root / netlist).read_bytes()).hexdigest() != reference['netlist_sha256']:
    raise SystemExit('Archived host netlist differs from the verified host netlist')
for name in ('sys/hps_io.sv', 'rtl/rabbitpunch_host.vhd', 'rtl/rabbitpunch_config.vhd', 'rtl/synth_check/host/host_check.vhd'):
    expected = subprocess.run(['git', 'show', reference['commit'] + ':' + name], cwd=root,
                              capture_output=True, check=True, **NO_WINDOW).stdout
    if (root / name).read_bytes().replace(b'\r\n', b'\n') != expected.replace(b'\r\n', b'\n'):
        raise SystemExit('Host source changed since the archived netlist: ' + name)
sources = platform_sources()[:-1] + [netlist, 'sim/board/platform_host_tb.vhd']
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver') for item in ('-L', name)]
result = run_case('platform_host', sources, 'platform_host_tb', '1 ms', 'PLATFORM_HOST_PASS',
                  sim_args=libraries, wall_timeout=300)
result.update(host_netlist_commit=reference['commit'], host_netlist_sha256=reference['netlist_sha256'],
    source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Native unchanged hps_io via checked Quartus functional netlist drives raw UIO/FIO command strobes into the RTL logical platform and actual fx68k/SDRAM/chip model: input/DIP CPU reads, DDR and byte loads, pause/reload/reset and partial-image recovery. Behavioral HPS master and DDR staging, audio/video idle; no physical ARM bridge, shared DDR mux, raster/PLL or electrical timing proof')
(root / 'docs/reference/platform_host_checks.json').write_text(json.dumps(result, indent=2) + '\n')
