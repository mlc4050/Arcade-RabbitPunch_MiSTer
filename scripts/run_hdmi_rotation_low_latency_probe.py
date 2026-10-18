# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Preserve the known two-buffer collision as an isolated negative control."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root = core_root()
netlist = 'debug/netlists/hdmi_rotation_0f4eefc/hdmi_rotation_check.vo'
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == 'adea57c6e471c3ef50d946347d00974ec7a367979bb787adce04b31a5d9cd31c'
sources = [netlist, 'sim/video/hdmi_rotation_buffers_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver')
             for item in ('-L', name)]
name = 'rotation_low_latency_collision_probe'
try:
    run_case(name, sources, 'hdmi_rotation_buffers_tb', '5 ms', 'HDMI_ROTATION_BUFFERS_PASS',
             sim_args=libraries + ['-gGBOOL_LOW_LATENCY=true', '-gGINT_FRAMEBUFFER_PHASE=-2'], wall_timeout=120)
except SystemExit:
    log = root / 'debug/baselines' / name / 'result.log'
    transcript = log.read_text(encoding='utf-8')
    if 'Rotation advertised the buffer currently being written' not in transcript or 'ROTATION_UNKNOWN_' in transcript:
        raise
else:
    raise SystemExit('Expected two-buffer collision did not reproduce')
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = dict(expected_failure=True, commit='0f4eefc8d71cb323a26505958375d187ff763a46',
              framebuffer_phase=-2, low_latency_request=True, source_sha256=hashes,
              log=log.relative_to(root).as_posix(), log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
              scope='Initialized between-edge stimulus; advertised read slot equals a visible write slot in the legacy two-buffer path when FB blank leads source VS by two clocks. Requires a verified genlock/beam-racing contract for low-latency mode. Not a physical fault claim. Production connection remains disabled; safe triple buffering is the supported bring-up policy.')
(root / 'docs/reference/hdmi_rotation_low_latency_probe.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print('EXPECTED NEGATIVE CONTROL: legacy two-buffer read/write collision', flush=True)
