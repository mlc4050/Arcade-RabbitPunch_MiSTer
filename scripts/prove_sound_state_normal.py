# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Prove the generated VHDL's normal-mode output/next-state/reset functions.

Both designs are cut at every corresponding flop. Shared arbitrary state and
inputs feed a combinational equivalence miter. Proving all outputs, next-state
bits and async reset conditions establishes a one-step correspondence for every
state, rather than relying on waveform coverage or guessed matching flop names.
The synthesis frontends and two-state logic semantics remain trusted boundaries.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chip', choices=('jt51', 'jt7759'), required=True)
    parser.add_argument('--yosys', type=Path, required=True)
    parser.add_argument('--ghdl', type=Path, required=True)
    parser.add_argument('--frontend-timeout', type=int, default=180,
                        help='Seconds allowed for lowering generated Verilog (default: 180)')
    parser.add_argument('--proof-timeout', type=int, default=180)
    parser.add_argument('--model-dir', type=Path, default=Path('rtl/state/generated'))
    parser.add_argument('--native-netlist', type=Path,
                        help='Independent lowered source JSON; default the original chip inventory')
    parser.add_argument('--tag')
    parser.add_argument('--structural-merge', action='store_true',
                        help='Run optional equiv_struct before independent output-cone proofs')
    args = parser.parse_args()
    require_no_jtag('RabbitPunch sound state normal-mode proof')
    assert 1 <= args.frontend_timeout <= 1200
    assert 1 <= args.proof_timeout <= 1200
    tag = args.tag or args.chip
    assert tag.replace('_', '').isalnum()
    root = core_root()
    generated = (root/args.model_dir/(args.chip+'_state_netlist.vhd')).resolve()
    assert generated.drive.upper() == 'D:'
    metadata = json.loads(generated.with_suffix('.json').read_text())
    assert hashlib.sha256(generated.read_bytes()).hexdigest() == metadata['generated_sha256']
    native_path = (root/args.native_netlist).resolve() if args.native_netlist else root/'debug/state_netlist'/(args.chip+'_gates')/'netlist.json'
    assert hashlib.sha256(native_path.read_bytes()).hexdigest() == metadata['lowered_netlist_sha256']
    for name, digest in metadata['source_sha256'].items():
        assert hashlib.sha256((root/name).read_bytes()).hexdigest() == digest, name
    out = root/'debug/state_proof'/tag
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['PATH'] = os.pathsep.join((str(args.yosys.parent), str(args.yosys.parent.parent/'lib'),
                                  str(args.ghdl.parent), env.get('PATH', '')))

    def command(name, arguments, stdout=None):
        result = subprocess.run(list(map(str, arguments)), cwd=out, env=env,
                                capture_output=True, text=True,
                                timeout=(args.frontend_timeout if name == 'gate' else
                                         args.proof_timeout if name == 'prove' else 180), **NO_WINDOW)
        (out/(name+'.log')).write_text(result.stderr+(result.stdout if stdout is None else ''), encoding='utf-8')
        if stdout:
            (out/stdout).write_text(result.stdout, encoding='utf-8')
        assert result.returncode == 0, (name, result.stderr[-2000:], result.stdout[-2000:])

    native_module = json.loads(native_path.read_text())['modules'][args.chip]
    # Tie scan controls before lowering. Otherwise GHDL's generated scan mux
    # network dominates native Verilog parsing although it is outside this
    # normal-mode proof. Retain every original input/output and corresponding Q.
    proof_entity = metadata['entity']+'_normal_proof'
    declarations, associations = [], []
    for original, port in native_module['ports'].items():
        name = metadata['ports'][original]
        width = len(port['bits'])
        kind = 'std_logic' if width == 1 else f'unsigned({width-1} downto 0)'
        direction = 'in' if port['direction'] == 'input' else 'out'
        declarations.append(f'        {name} : {direction} {kind}')
        associations.append(f'            {name} => {name}')
    associations += ["            i_state_hold => '0'", "            i_state_write => '0'",
                     "            iu16_state_word_address => (others => '0')",
                     "            iu32_state_write_data => (others => '0')",
                     '            ou32_state_read_data => open']
    wrapper = out/'normal_proof.vhd'
    wrapper.write_text('library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n'
                       'entity '+proof_entity+' is\n    port (\n'+';\n'.join(declarations)+
                       '\n    );\nend entity;\narchitecture rtl of '+proof_entity+' is\nbegin\n'
                       '    chip : entity work.'+metadata['entity']+'\n        port map (\n'+
                       ',\n'.join(associations)+'\n        );\nend architecture;\n', encoding='utf-8')
    command('ghdl', [args.ghdl, '--synth', '--std=08', '--no-formal', '--out=verilog', generated,
                     wrapper, '-e', proof_entity], 'generated.v')
    script = out/'gate.ys'
    script.write_text('read_verilog generated.v\nhierarchy -check -top '+proof_entity+
                      '\nproc\nflatten\nmemory_map\ntechmap\nopt_clean\nwrite_json gate.json\n', encoding='utf-8')
    command('gate', [args.yosys, '-ql', out/'gate_yosys.log', '-s', script])
    gold = copy.deepcopy(native_module)
    gate = json.loads((out/'gate.json').read_text())['modules'][proof_entity]
    internal_names = {}
    for label, item in gate['netnames'].items():
        match = re.search(r'(?:^|[._])(s_net_\d+|su\d+_nets)$', label)
        if match:
            name = match.group(1)
            assert name not in internal_names or internal_names[name] == item['bits'], name
            internal_names[name] = item['bits']
    def internal_bits(name):
        assert name in internal_names, ('Missing corresponding state net', name)
        return internal_names[name]
    if metadata.get('net_style', 'vector') == 'vector':
        carrier = re.search(r'signal (su\d+_nets) : unsigned', generated.read_text()).group(1)
        gate_bits = internal_bits(carrier)
        corresponding_bits = [gate_bits[item['q']] for item in metadata['state']]
    else:
        corresponding_bits = [internal_bits('s_net_'+str(item['q']))[0]
                              for item in metadata['state']]
    gate_flops = {}
    for name, cell in gate['cells'].items():
        if 'DFF' in cell['type']:
            assert len(cell['connections']['Q']) == 1
            gate_flops[cell['connections']['Q'][0]] = (name, cell)
    assert len(gate_flops) == metadata['state_bits'], 'Unexpected additional/merged VHDL state'
    gate_order = [gate_flops[bit][0] for bit in corresponding_bits]
    assert len(set(gate_order)) == metadata['state_bits']
    gold_order = [item['cell'] for item in metadata['state']]
    for original, descriptive in metadata['ports'].items():
        gold['ports'][descriptive] = gold['ports'].pop(original)

    def cut(module, order):
        current, next_state, resets, reset_values = [], [], [], []
        clock = module['ports']['i_clk']['bits'][0]
        for name in order:
            cell = module['cells'].pop(name)
            kind, pins = cell['type'], cell['connections']
            assert kind in ('$_DFF_P_', '$_DFF_PP0_', '$_DFF_PP1_'), kind
            assert pins['C'] == [clock], 'Clock correspondence failed'
            current += pins['Q']
            next_state += pins['D']
            resets += pins.get('R', ['0'])
            reset_values += [kind[-2] if 'R' in pins else '0']
        count = len(current)
        for name, direction, values in [
                ('iux_corresponding_state', 'input', current),
                ('oux_next_state', 'output', next_state),
                ('oux_reset_asserted', 'output', resets),
                ('oux_reset_value', 'output', reset_values)]:
            assert len(values) == count
            module['ports'][name] = dict(direction=direction, bits=values)
        return module

    gold, gate = cut(gold, gold_order), cut(gate, gate_order)
    for name, module in [('gold', gold), ('gate', gate)]:
        assert not any('DFF' in cell['type'] or 'LATCH' in cell['type'] for cell in module['cells'].values())
        (out/(name+'_cut.json')).write_text(json.dumps(dict(modules={name: module})), encoding='utf-8')
    script = out/'prove.ys'
    # Prove independent output cones. A monolithic OR-of-all-differences miter
    # timed out for JT51 despite its shallow one-step correspondence.
    script.write_text('read_json gold_cut.json\nread_json gate_cut.json\n'
                      'equiv_make gold gate equiv\nhierarchy -top equiv\n'
                      'opt_clean\n'+('equiv_struct\n' if args.structural_merge else '')+
                      'equiv_simple -short\n'
                      'equiv_status -assert\n', encoding='utf-8')
    command('prove', [args.yosys, '-ql', out/'proof.log', '-s', script])
    log = (out/'proof.log').read_text()
    assert 'Equivalence successfully proven!' in log, 'Missing formal success marker'
    report = dict(chip=args.chip, accepted=True, state_bits=metadata['state_bits'],
                  strategy='structural_merge_then_output_cones' if args.structural_merge else 'direct_output_cones',
                  generated_sha256=metadata['generated_sha256'], source_sha256=metadata['source_sha256'],
                  generator_sha256=metadata['generator_sha256'], yosys=metadata['yosys'],
                  prover_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  proof_log_sha256=hashlib.sha256((out/'proof.log').read_bytes()).hexdigest(),
                  scope='Two-state normal-mode combinational proof under identical arbitrary '
                  'corresponding flop state and arbitrary native inputs: all original output '
                  'bits, every flop D input and async reset condition/value. Positive clock '
                  'and complete state correspondence checked. Scan controls tied inactive. '
                  'The scan-write protocol assertion is omitted by GHDL --no-formal; '
                  'it is inactive with scan controls tied off. Synthesis frontends/primitive '
                  'mapping are trusted. Not a proof of power-up '
                  'identity, scan mode, analog timing, Quartus fitness or full game states.')
    (root/('docs/reference/'+tag+'_state_normal_proof.json')).write_text(
        json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('PROVED', args.chip, metadata['state_bits'], 'state bits; all output/next/reset functions', flush=True)


if __name__ == '__main__':
    main()
