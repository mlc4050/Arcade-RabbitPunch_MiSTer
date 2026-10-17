# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Run the unchanged original DDR PHY donor test before adaptation."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
manifest=json.loads((root/'docs/reference/vendor_manifest.json').read_text())
sources=['rtl/memory/ddram/ddram_phy.sv','sim/vendor/ddram/ddram_model.sv','sim/vendor/ddram/tb_ddram_phy.sv']
for source in sources:
    entry=next(row for row in manifest['files'] if row['target']==source)
    assert hashlib.sha256((root/source).read_bytes()).hexdigest()==entry['sha256']
result=run_case('ddram_phy_donor',sources,'tb_ddram_phy','1 ms','PASS: ddram_phy matches expected behavior at all tested latencies')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Unchanged original DDR PHY/model/test from pinned Psikyo donor: single-byte lane writes, full-granule readback, consecutive reads and next-cycle reuse at model latencies 6/13; no physical HPS DDR or copy-loader integration proof')
(root/'docs/reference/ddram_donor_checks.json').write_text(json.dumps(result,indent=2)+'\n')
