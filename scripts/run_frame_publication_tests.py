# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check presentation frame validity, queue drain and load/overflow recovery."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ['rtl/rabbitpunch_frame_publication.vhd', 'sim/video/frame_publication_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = run_case('frame_publication', sources, 'frame_publication_tb', '100 us', 'FRAME_PUBLICATION_PASS')
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
              scope='Isolated VHDL presentation-validity control with four-pixel frames. Complete/drained publication, startup and post-load frame alignment, first-overwrite invalidation, short/long/mixed-slot rejection, queue-busy rejection, immediate load/overflow blank/flush, overflow recovery and enable/game-ready gates. Not connected to the real rotator/queue/DDR and not yet fitted; no hardware or latency claim.')
(root / 'docs/reference/frame_publication_checks.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
