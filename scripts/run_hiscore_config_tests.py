# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ['rtl/rabbitpunch_hiscore_config.vhd', 'sim/board/hiscore_config_tb.vhd']
result = run_case('hiscore_config', sources, 'hiscore_config_tb', '100 us', 'HISCORE_CONFIG_PASS')
result.update(source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    scope='Standard 24-byte hiscore metadata parser: both captured MAME geometries, full-width wait endianness, strict descriptor support, truncation/reorder/overflow rejection, unrelated file-index isolation and ROM-generation clear. No production persistence integration.')
(root / 'docs/reference/hiscore_config_checks.json').write_text(json.dumps(result, indent=2) + '\n')
