# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare generated state-capable VHDL with pristine synthesis-mode JT51."""
import hashlib
import json
import argparse
from pathlib import Path
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-dir', type=Path, default=Path('rtl/state/generated'))
    parser.add_argument('--case', default='fm_netlist_state')
    args = parser.parse_args()
    assert args.case.replace('_', '').isalnum()
    model_dir = (root/args.model_dir).resolve()
    assert model_dir.drive.upper() == 'D:'
    metadata = json.loads((model_dir/'jt51_state_netlist.json').read_text())
    assert metadata['state_bits'] == 4016 and metadata['state_words'] == 126
    for name, expected in metadata['source_sha256'].items():
        assert hashlib.sha256((root/name).read_bytes()).hexdigest() == expected, name
    generated = (model_dir/'jt51_state_netlist.vhd').relative_to(root).as_posix()
    assert hashlib.sha256((root/generated).read_bytes()).hexdigest() == metadata['generated_sha256']
    sources = list(metadata['source_sha256'])+[generated, 'sim/state/fm_netlist_state_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result = run_case(args.case, sources, 'fm_netlist_state_tb', '11 ms',
                      'FM_NETLIST_STATE_PASS', wall_timeout=1200,
                      verilog_defines=())
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result.update(source_sha256=hashes,
                  log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
                  scope='Generated VHDL from pristine synthesis-mode JT51 JSON. Native '
                  'comparison uses the pristine four-state model without global initreg '
                  'overrides; enabled reset clocks and real timer load writes establish '
                  'the exercised startup state. Generated FPGA-zero initialization is '
                  'not assumed identical at power-up. '
                  'Nonzero feedback tone, both running timers and pending IRQ, all4016bits '
                  'freeze/scan round trip, timer-clear perturbation, three immediate4096clock '
                  'continuations including status/IRQ/sample/raw/fullstereoPCM. No formal '
                  'equivalence, complete register/voice corpus, Quartus timing, production '
                  'integration or full-game savestate qualification.')
    (root/('docs/reference/'+args.case+'_checks.json')).write_text(
        json.dumps(result, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
