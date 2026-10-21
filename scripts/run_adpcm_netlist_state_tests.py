# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare generated state-capable VHDL with its independent native chip."""
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
    parser.add_argument('--case', default='adpcm_netlist_state')
    args = parser.parse_args()
    assert args.case.replace('_', '').isalnum()
    model_dir = (root/args.model_dir).resolve()
    assert model_dir.drive.upper() == 'D:'
    metadata = json.loads((model_dir/'jt7759_state_netlist.json').read_text())
    for name, expected in metadata['source_sha256'].items():
        assert hashlib.sha256((root/name).read_bytes()).hexdigest() == expected, name
    generated = (model_dir/'jt7759_state_netlist.vhd').relative_to(root).as_posix()
    assert hashlib.sha256((root/generated).read_bytes()).hexdigest() == metadata['generated_sha256']
    corrected = 'rtl/rabbitpunch_upd7759_control.vhd' in metadata['source_sha256']
    assert metadata['state_bits'] == (189 if corrected else 192)
    sources = list(dict.fromkeys([*metadata['source_sha256'],
        'rtl/rabbitpunch_upd7759_control.vhd',
        'sim/state/rabbitpunch_corrected_adpcm_reference.vhd',
        generated, 'sim/state/adpcm_netlist_state_tb.vhd']))
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result = run_case(args.case, sources, 'adpcm_netlist_state_tb', '3 ms',
                      'ADPCM_NETLIST_STATE_PASS', wall_timeout=180,
                      sim_args=('-gGBOOL_CORRECTED='+str(corrected).lower(),
                                '-gGINT_STATE_BITS='+str(metadata['state_bits'])),
                      verilog_defines=(), vlog_options=('+initreg=r+0', '+initmem=r+0'))
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result.update(source_sha256=hashes, state_bits=metadata['state_bits'], corrected_silence=corrected,
                  log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
                  scope=('Generated VHDL from corrected VHDL controller plus unchanged JT7759 imports. '
                         'Independent reference is the ea4c83e native VHDL wrapper with passive DRQ output. '
                         if corrected else 'Generated VHDL from pristine synthesis-mode JT7759 JSON. ')+
                  'Native comparison uses explicit FPGA-zero initial register/RAM '
                  'contract, without SIMULATION-only divider seeds. Nonzero synthetic '
                  'standalone sample, throttled ROM, every meaningful state bit freeze/scan round trip, '
                  'three immediate4096clock continuations including ROM/DRQ/busy/PCM. '
                  'No formal equivalence, real ROM corpus, slave mode, Quartus timing, '
                  'production integration or full game savestate qualification.')
    (root/('docs/reference/'+args.case+'_checks.json')).write_text(
        json.dumps(result, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
