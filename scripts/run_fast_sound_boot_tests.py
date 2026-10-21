# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Qualify a supplemental fast sound startup model against pinned native/MAME traces."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from coretools import core_root, setting, NO_WINDOW
from hwlock import require_no_jtag
from run_system_download_tests import system_sources
from check_sound_board_boot import compare_startup, read_trace


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', type=Path)
    parser.add_argument('--native-reference-root', type=Path)
    parser.add_argument('--negative-block-io', action='store_true')
    parser.add_argument('--set', choices=['rabiolep', 'rpunch'], default='rabiolep')
    args = parser.parse_args()
    root = core_root()
    reference_root = args.reference_root or root
    native_root = args.native_reference_root or root
    require_no_jtag('Fast sound startup qualification')
    out = root / 'debug/fast_audio' / ('block_io_negative' if args.negative_block_io else args.set)
    out.mkdir(parents=True, exist_ok=True)
    reference = next(row for row in json.loads((reference_root / 'docs/reference/sound_boot_reference.json').read_text()) if row['set'] == args.set)
    native = next(row for row in json.loads((native_root / 'docs/reference/sound_board_native_reset_checks.json').read_text()) if row['set'] == args.set)
    rom = reference_root / 'debug/rom_regions' / args.set / 'audiocpu.bin'
    expected = reference_root / reference['trace']
    native_trace = native_root / 'debug/baselines' / ('sound_board_native_' + args.set) / 'rtl_sound_writes.txt'
    assert sha(rom) == reference['audiocpu_sha256']
    assert sha(expected) == reference['trace_sha256']
    assert sha(native_trace) == native['rtl_trace_sha256']
    contract_path = root / 'docs/reference/fast_ram_contract_checks.json'
    contract = json.loads(contract_path.read_text())
    assert contract['accepted'] and sha(root / 'scripts/run_fast_ram_tests.py') == contract['runner_sha256']
    for name, digest in contract['source_sha256'].items():
        assert sha(root / name) == digest
    for name, digest in contract['native_comparison']['source_sha256'].items():
        if name.startswith('rtl/'):
            assert sha(root / name) == digest
    sources = system_sources()
    sources = sources[sources.index('rtl/cpu/t80/T80_Pack.vhd'):sources.index('rtl/rabbitpunch_upd7759_control.vhd')]
    # Exclude the disconnected sample engine while retaining the real sound board and JT51.
    sources = [name for name in sources if not name.startswith('rtl/sound/jt7759/')]
    source_names = sources + ['sim/fast/rabbitpunch_ram8_model.vhd', 'sim/fast/sound_fast_fixture.vhd',
                              'scripts/run_fast_sound_boot_tests.py', 'scripts/check_sound_board_boot.py',
                              'scripts/run_system_download_tests.py', 'scripts/coretools.py']
    hashes = {name: sha(root / name) for name in source_names}
    stimulus = rom.read_bytes()
    if args.negative_block_io:
        program = bytes.fromhex('31FFFF 010001 2100F8 EDA2 76')
        stimulus = program + bytes(65536 - len(program))
    (out / 'audio_rom.hex').write_text(''.join(f'{byte:02x}\n' for byte in stimulus))
    text = (root / 'rtl/cpu/t80/T80.vhd').read_text()
    mask = '(ioq and x"7")'
    branch = "if (TState = 2 and I_BTR = '1' and IR(0) = '1') or (TState = 1 and I_BTR = '1' and IR(0) = '0') then"
    assert text.count(mask) == 1 and text.count(branch) == 1
    text = text.replace(mask, '(ioq and "000000111")')
    condition = branch[3:-5]
    guard = '    assert not (RESET_n = \'1\' and DIRSet = \'0\' and ClkEn = \'1\' and (' + condition + ')) report "FAST_T80_UNSUPPORTED_BLOCK_IO_FLAGS" severity failure;'
    assert text.count('\nbegin\n') == 1
    text = text.replace('\nbegin\n', '\nbegin\n' + guard + '\n', 1)
    (out / 'T80.vhd').write_text('-- Modified tool-only copy: explicit nine-bit mask for export; affected block-I/O flag path MUST trap.\n' + text)
    vhdl = [name for name in sources if name.endswith('.vhd')]
    vhdl = [(out / 'T80.vhd') if name == 'rtl/cpu/t80/T80.vhd' else
            root / 'sim/fast/rabbitpunch_ram8_model.vhd' if name == 'rtl/rabbitpunch_ram8.vhd' else root / name for name in vhdl]
    vhdl.append(root / 'sim/fast/sound_fast_fixture.vhd')
    ghdl = Path(setting('GHDL_EXE'))
    suite = Path(setting('OSS_CAD_ROOT'))
    dev = Path(setting('CXX_BIN'))
    env = os.environ.copy()
    env['PATH'] = ';'.join([str(dev), str(suite / 'bin'), str(suite / 'lib'), env['PATH']])
    env['VERILATOR_ROOT'] = (suite / 'share/verilator').as_posix()
    env['CCACHE_DISABLE'] = '1'
    env['CCACHE_DIR'] = str(root / '.local/tmp/ccache')
    tools = {'ghdl': ghdl, 'verilator': suite / 'bin/verilator_bin.exe', 'cxx': dev / 'g++.exe'}
    tool_hashes = {name: sha(path) for name, path in tools.items()}
    started = time.monotonic()
    result = subprocess.run([str(ghdl), '--synth', '--std=08', '-fsynopsys', '--latches', '--out=verilog'] +
                            [str(path) for path in vhdl] + ['-e', 'sound_fast_fixture'],
                            cwd=out, capture_output=True, text=True, timeout=300, **NO_WINDOW)
    (out / 'fixture.v').write_text(result.stdout)
    (out / 'export.log').write_text(result.stderr)
    assert result.returncode == 0, result.stderr[-4000:]
    trap_line = text[:text.index('assert not (RESET_n')].count('\n') + 2
    assert re.search(r'T80\.vhd:' + str(trap_line) + r':[^\n]* \*/\n  always @\*\n    if \([^\n]+\)\n      \$fatal', result.stdout), 'Unsupported-path fatal trap lost during export'
    trap_marker = re.search(r'T80\.vhd:' + str(trap_line) + r':[\s\S]{0,120}\$fatal\(1, "([^"]+)"', result.stdout)[1]
    bridge = out / 'clock_bridge.cpp'
    bridge.write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Clock and trace transport only; VHDL owns stimulus/assertions.
#include "Vsound_fast_fixture.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file,int line,const char*,const char* message) {
    std::fprintf(stderr,"VHDL_ASSERTION: %s:%d: %s\\n",file,line,message);std::exit(1);
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Vsound_fast_fixture model;
    FILE* trace=std::fopen("rtl_sound_writes.txt","w");if(!trace)return 3;
    model.i_clk=0;model.eval();
    for(unsigned cycle=0;cycle<20000000;cycle++) {
        model.i_clk=1;model.eval();
        if(model.o_write) std::fprintf(trace,"%04X FF %02X\\n",unsigned(model.ou16_address),unsigned(model.ou8_data));
        if(model.o_complete) {
            std::fclose(trace);model.final();std::printf("FAST_SOUND_COMPLETE cycles=%u\\n",cycle+1);return 0;
        }
        Verilated::timeInc(10417);model.i_clk=0;model.eval();Verilated::timeInc(10417);
    }
    std::fclose(trace);return 2;
}
''')
    obj = out / 'obj'
    command = [str(tools['verilator']), '--cc', '--exe', bridge.as_posix(), '--assert', '--no-assert-case',
               '-Wno-fatal', '--no-timing', '--timescale', '1ps/1ps', '--top-module', 'sound_fast_fixture',
               '--Mdir', obj.as_posix(), '-o', 'sim.exe', '-CFLAGS', '-O2 -DVL_USER_FATAL',
               (out / 'fixture.v').as_posix()] + [(root / name).as_posix() for name in sources if name.endswith(('.v', '.sv'))]
    for label, command in [('verilate', command), ('build', [str(dev / 'make.exe'), '-C', obj.as_posix(), '-f', 'Vsound_fast_fixture.mk', '-j1']),
                           ('run', [str(obj / 'sim.exe')])]:
        with (out / (label + '.log')).open('w') as log:
            result = subprocess.run(command, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600, **NO_WINDOW)
        print(label, result.returncode, flush=True)
        if label == 'run' and args.negative_block_io:
            rejected_log = (out / 'run.log').read_text()
            assert result.returncode == 1 and trap_marker in rejected_log, rejected_log
            assert int(re.search(r'\[(\d+)\] %Fatal', rejected_log)[1]) > 0, 'Guard failed before executing the test'
            assert hashes == {name: sha(root / name) for name in source_names}
            report = dict(accepted=True, expected_rejection=True, source_sha256=hashes,
                          tool_sha256=tool_hashes, trap_marker=trap_marker,
                          stimulus_sha256=hashlib.sha256(stimulus).hexdigest(),
                          generated_sha256={path.relative_to(out).as_posix(): sha(path) for path in out.iterdir() if path.is_file()},
                          scope='Original tiny Z80 INI program must trip the reset-gated unsupported block-I/O flag guard after time zero. All explicit HDL assertions enabled. This is an expected rejection, not a supported-instruction or game-ROM pass.')
            (root / 'docs/reference/fast_sound_blockio_guard_checks.json').write_text(json.dumps(report, indent=2) + '\n')
            print('PASS unsupported block-I/O guard rejected the executing INI test', flush=True)
            return
        assert result.returncode == 0, (out / (label + '.log')).read_text()[-5000:]
    log = (out / 'run.log').read_text()
    assert 'FAST_SOUND_COMPLETE' in log
    actual = read_trace(out / 'rtl_sound_writes.txt')
    comparison = compare_startup(read_trace(expected), actual, native_reset=True)
    native_comparison = compare_startup(read_trace(native_trace), actual, native_reset=True)
    assert hashes == {name: sha(root / name) for name in source_names}
    assert tool_hashes == {name: sha(path) for name, path in tools.items()}
    report = dict(accepted=True, set=args.set, source_sha256=hashes, tool_sha256=tool_hashes,
                  cycles=int(re.search(r'FAST_SOUND_COMPLETE cycles=(\d+)', log)[1]),
                  elapsed_seconds=time.monotonic() - started, mame_comparison=comparison,
                  native_comparison=native_comparison, rom_sha256=sha(rom),
                  mame_trace_sha256=sha(expected), native_trace_sha256=sha(native_trace),
                  rtl_trace_sha256=sha(out / 'rtl_sound_writes.txt'), ram_contract_sha256=sha(contract_path),
                  generated_sha256={path.relative_to(out).as_posix(): sha(path) for path in out.iterdir() if path.is_file()},
                  scope='Supplemental two-state T80/sound-bus/JT51 startup, qualified logical RAM and delayed behavioral ROM transport. Native CPU reset, no CPU/RAM deposit. Every address/mask and peripheral value compared with pinned native ModelSim and MAME startup; only the four separately audited bootstrap stack-save positions may differ. Tool-only T80 copy enables latch export and replaces an unequal-width legacy mask solely to permit compilation; the affected block-I/O flag path has an explicit fatal trap retained in the exported HDL. Unsupported instructions cannot silently pass. No general CPU equivalence, command/sample/SDRAM, physical/audio or long game-run proof.')
    (root / f'docs/reference/fast_sound_boot_{args.set}_checks.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS fast sound startup', args.set, len(actual), 'ordered writes', flush=True)


if __name__ == '__main__':
    main()
