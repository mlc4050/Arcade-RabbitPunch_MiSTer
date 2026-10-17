# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check byte-stream/DDR mode selection and HPS reset-release copy control."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/rabbitpunch_layout.vhd','rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','sim/memory/load_frontend_tb.vhd']
result=run_case('load_frontend',sources,'load_frontend_tb','1 ms','LOAD_FRONTEND_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='VHDL HPS-signal frontend plus actual native DDR PHY/copier and word-credit wrapper: metadata filtering, DDR-only copy after reset release, no soft-reset recopy, direct-byte pairing including same-edge first byte, backpressure, short/nonsequential rejection, overlapping-download old-copy drain and fresh recovery; behavioral DDR/word sink, no real hps_io or system/physical DDR proof')
(root/'docs/reference/load_frontend_checks.json').write_text(json.dumps(result,indent=2)+'\n')
