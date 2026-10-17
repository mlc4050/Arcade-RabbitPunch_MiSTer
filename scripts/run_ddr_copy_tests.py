# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check the native DDR copier plus descriptive ready/valid word boundary."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/rabbitpunch_layout.vhd','rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','sim/memory/ddr_copy_tb.vhd']
manifest=json.loads((root/'docs/reference/vendor_manifest.json').read_text())
for name in sources[1:3]:
    row=next(row for row in manifest['files'] if row['target']==name)
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==row['sha256']
result=run_case('ddr_copy',sources,'ddr_copy_tb','1 ms','DDR_COPY_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Unchanged native DDR PHY and Psikyo word-copy engine with descriptive VHDL one-word credit adapter: two 64-byte images, DDR-side busy and variable replies, data-pin spoil outside valid, word-side stalls/stability, address/byte lanes and warm restart; behavioral DDR backend only, no HPS/physical DDR/SDRAM loader/system integration proof')
(root/'docs/reference/ddr_copy_checks.json').write_text(json.dumps(result,indent=2)+'\n')
