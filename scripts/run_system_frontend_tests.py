# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Boot byte-streamed and HPS-staged DDR diagnostics through the logical system."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
from run_system_download_tests import system_sources
root=core_root()
sources=system_sources()[:-1]+['rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','sim/board/system_frontend_tb.vhd']
result=run_case('system_frontend',sources,'system_frontend_tb','1 ms','SYSTEM_FRONTEND_PASS',wall_timeout=300)
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='HPS-signal frontend with native DDR PHY/copier into production system word loader, cached SDRAM/chip model and executing fx68k: three 64-byte DDR images and one direct byte image, CAFE/BEEF native RAM writes, reset-release gating, no soft-reset recopy, hot replacement and rejected partial byte image plus DDR recovery; modeled HPS/DDR signals, audio/video idle, no real hps_io/DDR ownership/physical timing or game-boot proof')
(root/'docs/reference/system_frontend_checks.json').write_text(json.dumps(result,indent=2)+'\n')
