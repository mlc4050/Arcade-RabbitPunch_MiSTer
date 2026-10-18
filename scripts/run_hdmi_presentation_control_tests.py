# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check safe HDMI mode changes and rotated aspect/integer metadata."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = []
for name, filename in [('hdmi_rotation', 'hdmi_rotation_check.vo'), ('video_aspect', 'video_aspect_check.vo')]:
    proof = json.loads((root / 'docs/reference' / (name + '_netlist_checks.json')).read_text(encoding='utf-8'))
    netlist = 'debug/netlists/' + name + '_' + proof['commit'][:7] + '/' + filename
    assert hashlib.sha256((root / netlist).read_bytes()).hexdigest() == proof['netlist_sha256']
    sources.append(netlist)
sources += ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
            'rtl/rabbitpunch_rotation_transport.vhd', 'rtl/rabbitpunch_hdmi_presentation.vhd', 'sim/video/hdmi_presentation_control_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
libraries = [item for name in ('cyclonev_ver', 'altera_ver', 'altera_lnsim_ver', 'lpm_ver', 'sgate_ver') for item in ('-L', name)]
result = run_case('hdmi_presentation_controls', sources, 'hdmi_presentation_control_tb', '5 ms',
                  'HDMI_PRESENTATION_CONTROL_PASS', sim_args=libraries, wall_timeout=900)
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
              scope='Complete controller RTL around qualified donor/aspect netlists. Retains existing exact native aspect/full/custom/four-integer/resize/direct/invalid-scale checks; adds frame-boundary CW/CCW/None and reserved selection, old-image invalidation, mode hold/queue flush during loader ownership, direct-video native override, 3:4 normal aspect, unchanged custom selector encoding, and four rotated integer modes versus an independent transposed qualified-aspect instance with output bounds. No pixel-image, full-shell or physical monitor proof in this test.')
(root / 'docs/reference/hdmi_presentation_control_checks.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
