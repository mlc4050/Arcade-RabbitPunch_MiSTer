# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check read-only probe packets and saturating counters without opening JTAG."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root = core_root()
sources = ['rtl/rabbitpunch_debug.vhd', 'sim/board/debug_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = run_case('debug', sources, 'debug_tb', '10 us', 'DEBUG_PASS')
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(source_sha256=hashes,
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Read-only registered identity/status/address packet, enabled frame/pixel counting, separate CPU request/write events, sound/sample events, underflow edges and reduced-width saturation; JTAG IP disabled, no physical probe claim')
(root / 'docs/reference/debug_checks.json').write_text(json.dumps(result, indent=2) + '\n')
