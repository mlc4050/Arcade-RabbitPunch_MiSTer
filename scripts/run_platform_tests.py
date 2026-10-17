# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Boot byte-streamed and HPS-staged DDR diagnostics through the logical system."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
from run_system_download_tests import system_sources


def platform_sources():
    return system_sources()[:-1]+['rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv','rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','rtl/mame_keys.sv','rtl/rabbitpunch_keys.vhd','rtl/rabbitpunch_inputs.vhd','rtl/rabbitpunch_pause.vhd','rtl/rabbitpunch_controls.vhd','rtl/rabbitpunch_config.vhd','rtl/rabbitpunch_platform.vhd','sim/board/platform_tb.vhd']

def main():
    root=core_root()
    sources=platform_sources()
    result=run_case('platform',sources,'platform_tb','1 ms','PLATFORM_PASS',wall_timeout=300)
    result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Logical platform with host byte/DDR frontend, controls, game system and actual fx68k/SDRAM/chip model: two 64-byte DDR programs, one direct byte program and rejected partial-image recovery; CPU reads both player/service ports and downloaded DIP word into native RAM, pad/keyboard/OSD pause, held-key reload and soft-reset DIP preservation. Host and DDR signals modeled; audio/video clocks idle; no physical raster/PLL/hps_io/DDR ownership proof')
    (root/'docs/reference/platform_checks.json').write_text(json.dumps(result,indent=2)+'\n')

if __name__ == "__main__":
    main()
