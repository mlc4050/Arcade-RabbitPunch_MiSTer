# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check fixed-latency pixel metadata and explicit underflow handling."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ['rtl/rabbitpunch_video_output.vhd', 'sim/video/video_output_tb.vhd']
result = run_case('video_output', sources, 'video_output_tb', '20 us', 'VIDEO_OUTPUT_PASS')
result.update(source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Fixed five-system-clock output delay against a four-edge behavioral RGB source: sparse pixel cadence, sync/blank metadata, missing response, mismatched coordinates, source error, not-ready black fallback, sticky fault and reset flush; no physical raster or native video latency proof')
(root / 'docs/reference/video_output_checks.json').write_text(json.dumps(result, indent=2) + '\n')
