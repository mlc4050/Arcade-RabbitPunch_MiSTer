# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Test loader priority, queued-write discard and clean frame restart."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ['rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
           'rtl/rabbitpunch_rotation_transport.vhd', 'sim/video/rotation_transport_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = run_case('rotation_transport', sources, 'rotation_transport_tb', '100 us', 'ROTATION_TRANSPORT_PASS')
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
              scope='Actual VHDL queue/publication/loader mux with synthetic four-pixel frames and loader commands. Ordered presentation writes, immediate loader priority and invalidation, takeover with pending pixels, delayed read response, loader command fields, queue discard, post-load frame-boundary restart and recovery. Caller holds loader ownership through response drain. Not the actual load frontend or rotator, not yet fitted or connected to production.')
(root / 'docs/reference/rotation_transport_checks.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
