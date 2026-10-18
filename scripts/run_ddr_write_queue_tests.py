# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Exercise ordered presentation writes through stalls, overflow, wraps and reset."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ['rtl/rabbitpunch_ddr_write_queue.vhd', 'sim/video/ddr_write_queue_tb.vhd']
hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
result = run_case('ddr_write_queue', sources, 'ddr_write_queue_tb', '1 ms', 'DDR_WRITE_QUEUE_PASS')
assert hashes == {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources}
result.update(source_sha256=hashes, log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Isolated unsigned VHDL RTL queue: exact 512-packet stalled capacity, sticky overflow without overwriting accepted packets, independent ordered scoreboard through 8000 pseudo-random cycles including simultaneous enqueue/dequeue and pointer wraparound, stable stalled outputs, reset discards pending presentation writes. No fitted memory/timing, rotator ownership, loader isolation or physical DDR proof; disconnected from production.')
(root / 'docs/reference/ddr_write_queue_checks.json').write_text(json.dumps(result, indent=2) + '\n')
