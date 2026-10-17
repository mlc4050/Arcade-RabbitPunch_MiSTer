# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Boot main-CPU diagnostics copied from modeled DDR through the real SDRAM subsystem."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
from run_system_download_tests import system_sources
root=core_root()
sources=system_sources()[:-1]+['rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','sim/board/system_ddr_tb.vhd']
result=run_case('system_ddr',sources,'system_ddr_tb','1 ms','SYSTEM_DDR_PASS',wall_timeout=240)
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Native DDR PHY/copy engine plus VHDL credit adapter into production logical system download, cached SDRAM controller/chip model and executing fx68k: two 64-byte images, CAFE/BEEF native RAM writes, warm replacement, pause inspection and soft reset without recopy; modeled DDR interface, audio enables/video idle; no HPS trigger, full-image bandwidth, DDR arbitration/physical timing or game boot proof')
(root/'docs/reference/system_ddr_checks.json').write_text(json.dumps(result,indent=2)+'\n')
