# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Simulation-only negative control for simultaneous rotation buffer advances."""
import hashlib
import json
import re
from coretools import core_root
from run_baselines import run_case
root = core_root()
# Pin the pre-serialization netlist: this is an expected-failure baseline,
# independent of the current fitted adapter and its positive regression.
proof = dict(commit='fc479ee2edbbb640116f89d77b0165d79f2ef5db')
netlist = 'debug/netlists/hdmi_rotation_fc479ee/hdmi_rotation_check.vo'
assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == 'ed7cb1477d6d21a6dfbdea7bf52e10cae5f6962b41463d49a21d77ee781439c9'
template_path = root / 'sim/video/hdmi_rotation_tb.vhd'
template = template_path.read_text()
marker = "            if (s_write = '1') then"
assert template.count(marker) == 1
bench = template.replace(marker, marker + '''
                assert (su32_base(24 downto 23) /= su29_word_address(21 downto 20))
                    report "ROTATION_BUFFER_COLLISION read=" & integer'image(to_integer(su32_base(24 downto 23))) &
                        " write=" & integer'image(to_integer(su29_word_address(21 downto 20))) severity failure;''')
bench_path = root / 'debug/hdmi_rotation_collision_tb.vhd'
bench_path.write_text(bench)
sources = [netlist, bench_path.relative_to(root).as_posix()]
hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
libraries = [item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
try:
    run_case('rotation_collision_probe', sources, 'hdmi_rotation_tb', '1 ms', 'HDMI_ROTATION_PASS', sim_args=libraries, wall_timeout=120)
except SystemExit:
    log_path = root / 'debug/baselines/rotation_collision_probe/result.log'
    log = log_path.read_text()
    match = re.search(r'ROTATION_BUFFER_COLLISION read=\s*(\d+) write=\s*(\d+)', log)
    if not match or match[1] != match[2]:
        raise
else:
    raise SystemExit('Expected negative control did not expose simultaneous-event buffer collision')
assert hashes == {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
result = dict(expected_failure=True, safe_to_connect=False, fitted_commit=proof['commit'],
              read_buffer=int(match[1]), write_buffer=int(match[2]), source_sha256=hashes,
              template_sha256=hashlib.sha256(template_path.read_bytes()).hexdigest(),
              log=log_path.relative_to(root).as_posix(), log_sha256=hashlib.sha256(log_path.read_bytes()).hexdigest(),
              scope='Simulation negative control of unchanged isolated donor: FB_VBL equals source VSYNC, so both buffer selectors advance on the same clock. A visible write targets the advertised read buffer. This does not invalidate pixel-address proofs and is not a measured failure on another core or physical MiSTer. Requires serialized buffer advances and valid-frame publication before production connection.')
(root / 'docs/reference/hdmi_rotation_collision_probe.json').write_text(json.dumps(result, indent=2) + '\n')
print('Observed expected donor read/write buffer collision; production remains disconnected')
