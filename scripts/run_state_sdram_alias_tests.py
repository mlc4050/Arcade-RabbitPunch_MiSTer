# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare native and exported seven-stage DQ readback without a game model."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import shutil

from coretools import core_root
from run_baselines import run_case
from run_state_game_diagnostic import require_window, run


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore_aliases(raw):
    records = []

    def module(match):
        text = original = match[0]
        name = re.search(r'^module\s+(\w+)', text)[1]
        if '(inout -' in text:
            assert name.startswith(('rabbitpunch_sdram_', 'state_sdram_alias_stage_')), name
            assert re.search(r'inout\s+\[15:0\]\s+iou16_sdram_data\b', text)
            ports = re.findall(r'^  assign ([^\n]+) = ([^\n]+); // \(inout - port\)\n', text, re.M)
            reads = re.findall(r'^  assign ([^\n]+) = ([^\n]+); // \(inout - read\)\n', text, re.M)
            assert len(ports) == len(reads) == 1
            parent, child = [value.strip() for value in ports[0]]
            read, source = [value.strip() for value in reads[0]]
            assert source == 'iou16_sdram_data' and child.startswith('\\')
            assert len(re.findall(re.escape(read)+r'(?=\s)', text)) == 2
            assert len(re.findall(re.escape(parent)+r'(?=\s)', text)) == 3
            text, count = re.subn(r'^  assign iou16_sdram_data = '+re.escape(parent)+r' ; //\(module output\)\n', '', text, flags=re.M)
            assert count == 1
            text, count = re.subn(r'^  assign [^\n]+// \(inout - (?:port|read)\)\n', '', text, flags=re.M)
            assert count == 2
            declaration = '  wire [15:0] '+child+' ;\n'
            assert text.count(declaration) == 1
            text = text.replace(declaration, '')
            assert text.count(child+' ') == 1
            text = text.replace(child+' ', 'iou16_sdram_data')
            records.append(dict(module=name, kind='transparent_stage'))
        elif name == 'state_sdram_alias_eval':
            assert text.count('.SDRAM_DQ()') == text.count('.iou16_sdram_data()') == 1
            aliases = ('\\chip.SDRAM_DQ', '\\chain.iou16_sdram_data')
            for alias in aliases:
                declaration = '  wire [15:0] '+alias+' ;\n'
                assert text.count(declaration) == 1
                assert len(re.findall(re.escape(alias)+r'(?=\s)', text)) == 1
                text = text.replace(declaration, '')
            assert not re.search(r'\bsu16_dq\b', text)
            # Add the shared net inside the body, immediately before its first wire.
            position = re.search(r'^  (?:wire|reg) ', text, re.M).start()
            text = text[:position]+'  wire [15:0] alias_eval_dq;\n'+text[position:]
            text = text.replace('.SDRAM_DQ()', '.SDRAM_DQ(alias_eval_dq)')
            text = text.replace('.iou16_sdram_data()', '.iou16_sdram_data(alias_eval_dq)')
            records.append(dict(module=name, kind='shared_top_wire'))
        if text != original:
            records[-1].update(original_sha256=hashlib.sha256(original.encode()).hexdigest(),
                               normalized_sha256=hashlib.sha256(text.encode()).hexdigest())
        return text

    fixed = re.sub(r'^module\s+\w+\b.*?^endmodule\b', module, raw, flags=re.M | re.S)
    assert len([row for row in records if row['kind'] == 'transparent_stage']) == 7
    assert len(records) == 8 and '(inout -' not in fixed
    return fixed, records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_window()
    root = core_root()
    case = 'state_sdram_alias_'+args.label
    out = root/'debug'/case
    assert not out.exists(), 'Preserve prior attempts'
    out.mkdir(parents=True)
    sources = ['rtl/rabbitpunch_sdram_types.vhd', 'rtl/memory/sdram/sdram.sv',
        'rtl/rabbitpunch_sdram.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv',
        'sim/state/state_sdram_alias_stage.vhd', 'sim/state/state_sdram_alias_eval.vhd',
        'sim/state/state_sdram_alias_tb.vhd']
    transport = 'sim/fast/state_sdram_alias_transport.cpp'
    hashes = {name: sha(root/name) for name in sources+[transport]}
    for name in hashes:
        snapshot = out/'inputs'/name
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/name, snapshot)
    (out/'attempt.json').write_text(json.dumps(dict(accepted=False, source_sha256=hashes,
        runner_sha256=sha(Path(__file__))), indent=2)+'\n')
    native = run_case(case, sources, 'state_sdram_alias_tb', '1001 us',
                      'STATE_SDRAM_ALIAS_PASS', wall_timeout=300, verilog_defines=())
    tools = Path('D:/git/Arcade-RabbitPunch_MiSTer/.local/tools')
    suite = tools/'oss-cad-suite-20261018/oss-cad-suite'
    dev = tools/'w64devkit-2.10.1/w64devkit/bin'
    ghdl = tools/'ghdl-6.0.0/bin/ghdl.exe'
    env = dict(os.environ)
    env['PATH'] = ';'.join((str(dev), str(suite/'bin'), str(suite/'lib'), env['PATH']))
    env['VERILATOR_ROOT'] = (suite/'share/verilator').as_posix()
    env['CCACHE_DISABLE'] = '1'
    vhdl = [str(out/'inputs'/name) for name in sources[:-1] if name.endswith('.vhd')]
    result = run([str(ghdl), '--synth', '--std=08', '--out=verilog']+vhdl+
                 ['-e', 'state_sdram_alias_eval'], out, 'export', 120, env)
    (out/'raw.v').write_text(result.stdout, newline='\n')
    fixed, aliases = restore_aliases(result.stdout)
    (out/'normalized.v').write_text(fixed, newline='\n')
    (out/'alias_audit.json').write_text(json.dumps(dict(accepted=False,
        records=aliases, raw_sha256=sha(out/'raw.v'),
        normalized_sha256=sha(out/'normalized.v')), indent=2)+'\n')
    sv = [str(out/'inputs'/name) for name in sources if name.endswith('.sv')]
    command = [str(suite/'bin/verilator_bin.exe'), '--cc', '--exe', str(out/'inputs'/transport),
        '--assert', '--no-assert-case', '-Wno-fatal', '--no-timing', '--timescale', '1ps/1ps',
        '--top-module', 'state_sdram_alias_eval', '--Mdir', str(out/'obj'), '-o', 'sim.exe',
        '-CFLAGS', '-O2 -DVL_USER_FATAL', str(out/'normalized.v')]+sv
    run([value.replace('\\', '/') for value in command], out, 'verilate', 120, env)
    run([str(dev/'make.exe'), '-C', str(out/'obj'), '-f', 'Vstate_sdram_alias_eval.mk', '-j2'],
        out, 'build', 300, env)
    run([str(out/'obj/sim.exe')], out, 'run', 120, env)
    native_trace = root/'debug/baselines'/case/'alias_trace.txt'
    lines = native_trace.read_text().splitlines()
    exported_lines = (out/'alias_trace.txt').read_text().splitlines()
    difference = next((dict(line=index, records=[left, right])
        for index, (left, right) in enumerate(itertools.zip_longest(lines, exported_lines), 1)
        if left != right), None)
    (out/'comparison.json').write_text(json.dumps(dict(equal=difference is None,
        native_sha256=sha(native_trace), exported_sha256=sha(out/'alias_trace.txt'),
        first_difference=difference), indent=2)+'\n')
    assert difference is None, 'Native/export command or data continuation differs: '+str(difference)
    native_bytes = native_trace.read_bytes().replace(b'\r\n', b'\n')
    exported_bytes = (out/'alias_trace.txt').read_bytes().replace(b'\r\n', b'\n')
    assert native_bytes == exported_bytes, 'Trace byte formatting differs beyond Windows newlines'
    assert sum(line.startswith('R ') for line in lines) == 192
    writes = sum((int(fields[4], 16) & ~int(fields[5], 16) & 7).bit_count()
                 for line in lines if (fields := line.split())[0] == 'C')
    assert writes == 256
    assert hashes == {name: sha(root/name) for name in hashes}, 'Source changed during test'
    receipt = dict(accepted=True, source_sha256=hashes, native=native,
        runner_sha256=sha(Path(__file__)), native_trace_sha256=sha(native_trace),
        native_log_sha256=sha(root/native['log']),
        exported_trace_sha256=sha(out/'alias_trace.txt'), raw_sha256=sha(out/'raw.v'),
        newline_normalized_trace_sha256=hashlib.sha256(native_bytes).hexdigest(),
        normalized_sha256=sha(out/'normalized.v'),
        trace_clocks=sum(line.startswith('C ') for line in lines), writes=writes, burst_reads=192,
        scope='Native and exported VHDL sequencer, six transparent inout stages '
              'and the unchanged real adapter/controller/chip. Ordinary writes '
              'initialize512 bytes in four distinct64-bit patterns;192 burst '
              'reads use all three ports simultaneously. Every initialized '
              'clock compares requests, ready, valid, physical commands and '
              'all valid read data byte exactly after CRLF/LF normalization. Seven DQ associations and '
              'their shared top wire are restored by a restricted structural '
              'audit. No game state deposits, RAM abstraction, CPU/event monitor, '
              'whole-game, fitted timing or hardware qualification. Address/bank '
              'are excluded only for NOP, refresh and burst termination; DQM, '
              'select and command timing remain visible on every clock.')
    (root/'docs/reference'/(case+'_checks.json')).write_text(json.dumps(receipt, indent=2)+'\n')
    print('PASS native/export seven-stage DQ trace '+receipt['native_trace_sha256'])


if __name__ == '__main__':
    main()
