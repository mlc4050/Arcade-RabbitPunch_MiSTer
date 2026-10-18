# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Run actual four-state DDR/byte frontend over the complete image address range."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ['rtl/rabbitpunch_layout.vhd', 'rtl/memory/ddram/ddram_phy.sv',
           'rtl/memory/ddram/rom_loader.sv', 'rtl/rabbitpunch_ddr_copy.vhd',
           'rtl/rabbitpunch_load_frontend.vhd', 'sim/fast/diagnostic_pattern.vhd',
           'sim/fast/diagnostic_load_source.vhd', 'sim/memory/load_frontend_full_tb.vhd']
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = run_case('load_frontend_full', sources, 'load_frontend_full_tb', '100 ms',
                  'LOAD_FRONTEND_FULL_PASS', wall_timeout=1200)
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(accepted=True, source_sha256=hashes,
              runner_sha256=hashlib.sha256((root / 'scripts/run_load_frontend_full_tests.py').read_bytes()).hexdigest(),
              log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
              bytes_per_mode=2162688, words_per_mode=1081344, ddr_reads=270336,
              scope='Native four-state ModelSim, actual HPS-signal frontend/DDR copier and unchanged DDR PHY/rom_loader, nonuniform high-address-dependent pattern across the full image, independent ordered sink, periodic and long sink stalls, DDR busy/variable response delays and invalid-pin poison. No hps_io parser, system SDRAM, executing CPU or physical DDR/HPS proof.')
(root / 'docs/reference/load_frontend_full_checks.json').write_text(json.dumps(result, indent=2) + '\n')
