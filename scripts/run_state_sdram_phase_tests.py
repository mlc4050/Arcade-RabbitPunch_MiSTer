# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Evaluate read-only SDRAM phase convergence with the native controller/chip."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from coretools import core_root
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--concurrent-clients', action='store_true')
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    root = core_root()
    case = 'state_sdram_phase_'+args.label
    out = root/'debug/baselines'/case
    assert not out.exists(), 'Preserve previous attempts'
    out.mkdir(parents=True)
    sources = ['rtl/rabbitpunch_sdram_types.vhd', 'rtl/memory/sdram/sdram.sv',
        'rtl/rabbitpunch_sdram.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv',
        'rtl/state/rabbitpunch_state_sdram_phase.vhd', 'sim/state/state_sdram_phase_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name in sources:
        target = out/'inputs'/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, target)
    (out/'attempt.json').write_text(json.dumps(dict(accepted=False, source_sha256=hashes), indent=2)+'\n')
    result = run_case(case, sources, 'state_sdram_phase_tb', '101 ms',
        'STATE_SDRAM_PHASE_PASS', wall_timeout=600, verilog_defines=(),
        sim_args=('-gGBOOL_CONCURRENT_CLIENTS='+str(args.concurrent_clients).lower(),))
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result.update(accepted=True, source_sha256=hashes,
        concurrent_clients=args.concurrent_clients,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Native unchanged SDRAM controller/adapter/chip,5357ps shifted clock '
              'and capture adjustment1.163 initial delay cases; four normal writes '
              'and'+str(1956 if args.concurrent_clients else 1304)+' exact normal burst readbacks after read-only phase streaming. '
              'Compare ready/valid and command timing for256 clocks after release; '
              '16 cancellation edges around accepted-read completion retain ownership '
              'and suppress private replies, then return exactly one normal reply. '
              'Refresh chip-select parity excluded. No game integration, '
              'FPGA timing or whole-game continuation qualification.')
    (root/'docs/reference'/('state_sdram_phase_'+args.label+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
