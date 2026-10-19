# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Run both real CPUs, shared SDRAM and continuous video in the qualified fast model."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from coretools import core_root, NO_WINDOW, setting
from hwlock import require_no_jtag
from png_rgb import write_rgb
from run_system_download_tests import system_sources

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game', choices=['rabiolep','rpunch'], default='rabiolep')
parser.add_argument('--frames', type=int, default=1800)
parser.add_argument('--action-frame', type=int, default=1290)
parser.add_argument('--coin-frame', type=int, default=900)
parser.add_argument('--start-frame', type=int, default=990)
parser.add_argument('--reference-root', type=Path, required=True)
parser.add_argument('--wall-timeout', type=int, default=18000)
options = parser.parse_args()
if options.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
require_no_jtag('Bounded live game with both CPUs and continuous scanout')
assert 2 <= options.coin_frame < options.start_frame < options.action_frame < options.frames <= 1800
case = options.game + '_' + str(options.frames) + '_pad'
out = root / 'debug/gameplay_fast' / case
assert not (out / 'run.log').exists(), 'Preserve earlier run artifacts before retrying'
out.mkdir(parents=True, exist_ok=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
contract = json.loads((root / 'docs/reference/fast_ram_loader_contract_checks.json').read_text())
assert contract['accepted']
assert sha(root / 'scripts/run_fast_ram_tests.py') == contract['runner_sha256'], 'Requalify the RAM runner first'
for name, expected in contract['native_comparison']['source_sha256'].items():
    if name.replace('\\','/').startswith('rtl/'):
        assert sha(root / name) == expected, 'Native RAM wrapper changed; requalify: ' + name
for name, expected in contract['source_sha256'].items():
    assert sha(root / name) == expected, 'Requalify the logical RAM contract first: ' + name
all_sources = system_sources()
main_sources = all_sources[:-1] + ['rtl/mame_keys.sv', 'rtl/rabbitpunch_keys.vhd', 'rtl/rabbitpunch_inputs.vhd']
# All production CPU, sound and memory components are retained.
input_names = list(dict.fromkeys(main_sources + [
    'scripts/run_gameplay_tests.py','scripts/run_fast_sound_boot_tests.py',
    'scripts/run_system_download_tests.py','scripts/build_mras.py','scripts/png_rgb.py',
    'scripts/coretools.py','scripts/mra.py','rtl/cpu/fx68k/microrom.mem','rtl/cpu/fx68k/nanorom.mem',
    'sim/fast/rabbitpunch_ram16_model.vhd','sim/fast/rabbitpunch_ram8_model.vhd',
    'sim/fast/gameplay_fast_fixture.vhd','scripts/check_sound_board_boot.py','rtl/rabbitpunch_clock_enables.vhd',
    'rtl/rabbitpunch_raster.vhd','rtl/rabbitpunch_scanline_scheduler.vhd',
    'rtl/rabbitpunch_video_output.vhd','rtl/rabbitpunch_scanout.vhd']))
input_hashes = {name: sha(root / name) for name in input_names}
reference_root = options.reference_root
main_reference = next(row for row in json.loads((reference_root / 'docs/reference/boot_checks.json').read_text()) if row['set'] == options.game)
sound_reference = next(row for row in json.loads((reference_root / 'docs/reference/sound_boot_reference.json').read_text()) if row['set'] == options.game)
parts = [(reference_root / 'debug/rom_regions' / options.game / (name + '.bin')).read_bytes()
         for name in ('maincpu','audiocpu','tiles1','tiles2','sprites','upd')]
assert tuple(map(len, parts)) == (0x40000,0x10000,0x80000,0x80000,0x80000,0x40000)
assert hashlib.sha256(parts[0]).hexdigest() == main_reference['maincpu_sha256']
assert hashlib.sha256(parts[1]).hexdigest() == sound_reference['audiocpu_sha256']
image = b''.join(parts)
(out / 'image_used.bin').write_bytes(image)
physical = [word for word, in struct.iter_unpack('<H', image)]
image_words = 16
mra = next(ET.parse(path) for path in (root / 'releases').glob('*.mra') if ET.parse(path).findtext('setname') == options.game)
dip_bytes = mra.find('switches').get('default').split(',')
dips = int(dip_bytes[0],16) | (int(dip_bytes[1],16) << 8)
package = """-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
package game_program is
    function program_word(iint_address : natural) return unsigned;
end package;
package body game_program is
    function program_word(iint_address : natural) return unsigned is
    begin
        case iint_address is
""" + ''.join(f'            when {index} =>\n                return x"{word:04X}";\n' for index,word in enumerate(physical[:16])) + """            when others =>
                return x"0000";
        end case;
    end function;
end package body;
"""
(out / 'game_program.vhd').write_text(package)
ghdl = Path(setting('GHDL_EXE', str(root / '.local/tools/ghdl-6.0.0/bin/ghdl.exe')))
suite = Path(setting('OSS_CAD_ROOT', str(root / '.local/tools/oss-cad-suite-20261018/oss-cad-suite')))
dev = Path(setting('CXX_BIN', str(root / '.local/tools/w64devkit-2.10.1/w64devkit/bin')))
env = os.environ.copy()
env['PATH'] = ';'.join((str(dev),str(suite / 'bin'),str(suite / 'lib'),env['PATH']))
env['VERILATOR_ROOT'] = (suite / 'share/verilator').as_posix()
env['CCACHE_DISABLE'] = '1'
env['CCACHE_DIR'] = str(root / '.local/tmp/ccache')
tool_paths = {'ghdl':ghdl,'verilator':suite / 'bin/verilator_bin.exe','cxx':dev / 'g++.exe'}
tool_hashes = {name:sha(path) for name,path in tool_paths.items()}
started = time.monotonic()

# Main-board-only export copies.
text=(root/'rtl/rabbitpunch_tiles.vhd').read_text()
text=text.replace('    function bank_number', '    signal su9_selected_scroll_x, su9_selected_scroll_y : unsigned(8 downto 0);\n    function bank_number')
text=text.replace('    end function;\nbegin', '    end function;\nbegin\n    su9_selected_scroll_x <= su9_scroll_x(bank_number(s_foreground));\n    su9_selected_scroll_y <= su9_scroll_y(bank_number(s_foreground));')
text=text.replace('iu9_scroll_x => su9_scroll_x(bank_number(s_foreground))', 'iu9_scroll_x => su9_selected_scroll_x').replace('iu9_scroll_y => su9_scroll_y(bank_number(s_foreground))','iu9_scroll_y => su9_selected_scroll_y')
(out/'rabbitpunch_tiles.vhd').write_text('-- Export-only combinational port-actual normalization; original RTL unchanged.\n'+text)
# Preserve the unsupported T80 path as a fatal boundary, matching the sound qualification.
text = (root / 'rtl/cpu/t80/T80.vhd').read_text()
mask = '(ioq and x"7")'
assert text.count(mask) == 1
text = text.replace(mask, '(ioq and "000000111")')
guard = "    assert not (RESET_n = '1' and DIRSet = '0' and ClkEn = '1' and (((TState = 2 and I_BTR = '1' and IR(0) = '1') or (TState = 1 and I_BTR = '1' and IR(0) = '0')))) report \"FAST_T80_UNSUPPORTED_BLOCK_IO_FLAGS\" severity failure;"
assert text.count('\nbegin\n') == 1
text = text.replace('\nbegin\n', '\nbegin\n' + guard + '\n', 1)
(out / 'T80.vhd').write_text('-- Modified tool-only T80 copy; affected unsupported block-I/O path must trap.\n' + text)

# Versioned VHDL owns the raster, stimulus, checks and trace outputs.
sources = [p for p in main_sources if p.endswith('.vhd')]
sources = [p.replace('rtl/rabbitpunch_ram16.vhd','sim/fast/rabbitpunch_ram16_model.vhd').replace('rtl/rabbitpunch_ram8.vhd','sim/fast/rabbitpunch_ram8_model.vhd') for p in sources]
sources = [str((out/'rabbitpunch_tiles.vhd').relative_to(root)) if p=='rtl/rabbitpunch_tiles.vhd' else str((out/'T80.vhd').relative_to(root)) if p=='rtl/cpu/t80/T80.vhd' else p for p in sources]
sources += ['rtl/rabbitpunch_clock_enables.vhd','rtl/rabbitpunch_raster.vhd','rtl/rabbitpunch_scanline_scheduler.vhd','rtl/rabbitpunch_video_output.vhd','rtl/rabbitpunch_scanout.vhd',str((out/'game_program.vhd').relative_to(root)),'sim/fast/gameplay_fast_fixture.vhd']
args=[str(ghdl),'--synth','--latches','--std=08','-fsynopsys','--out=verilog','-gGINT_ACTION_FRAME='+str(options.action_frame),'-gGINT_COIN_FRAME='+str(options.coin_frame),'-gGINT_START_FRAME='+str(options.start_frame),'-gGINT_CAPTURE_FRAME='+str(options.frames),'-gGINT_DIP_DEFAULT='+str(dips)]+[str(root/p) for p in sources]+['-e','gameplay_fast_fixture']
r=subprocess.run(args,cwd=out,capture_output=True,text=True,timeout=300,**NO_WINDOW)
(out/'gameplay_fast_fixture.v').write_text(r.stdout);(out/'export.log').write_text(r.stderr)
(out/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
assert r.returncode == 0, r.stderr
print('PASS VHDL fast live-game export',flush=True)

# Restore transparent bidirectional port associations in generated Verilog.
p=out/'gameplay_fast_fixture.v';raw=p.read_text();(out/'gameplay_fast_fixture_raw.v').write_text(raw)
if (out/'verilate.log').exists():(out/'verilate_dq_alias_rejected.log').write_text((out/'verilate.log').read_text())
records=[]
def normalize(match):
    text=match[0]
    if not re.search(r'inout\s+\[15:0\]\s+iou16_sdram_data\b',text):return text
    found=re.findall(r'^  wire \[15:0\] (\\\S+(?:\.SDRAM_DQ|\.iou16_sdram_data)) ;\n',text,re.M)
    assert len(found)==1,found
    child=found[0]
    text=text.replace('  wire [15:0] '+child+' ;\n','')
    text=re.sub(r'^  assign iou16_sdram_data = [^\n]+//\(module output\)\n','',text,flags=re.M)
    text=re.sub(r'^  assign [^\n]+// \(inout - (?:port|read)\)\n','',text,flags=re.M)
    text=text.replace(child+' ','iou16_sdram_data')
    assert not re.search(r'^  assign iou16_sdram_data\b',text,re.M)
    records.append(dict(module=re.search(r'module\s+(\S+)',text)[1],child_alias=child))
    return '// Tool-only inout passthrough normalization; original VHDL unchanged.\n'+text
fixed=re.sub(r'module\s+.*?endmodule',normalize,raw,flags=re.S)
assert len(records)==4,records
assert fixed.count('.SDRAM_DQ(iou16_sdram_data)')==1
p.write_text(fixed)
(out/'dq_alias_normalization.json').write_text(json.dumps(dict(records=records,raw_sha256=hashlib.sha256(raw.encode()).hexdigest(),normalized_sha256=hashlib.sha256(fixed.encode()).hexdigest(),scope='Restore direct bidirectional port associations in generated Verilog; four original VHDL levels directly associate their single inout with the child. Raw exporter produced one-way output chains with unused read aliases. No production VHDL/vendor changes; requires diagnostic readback qualification.'),indent=2)+'\n')
print('Normalized transparent DQ aliases:',records)

# Compile unchanged vendor components and the generated transport bridge.
for name in ('microrom.mem','nanorom.mem'):
    target=out/'rtl/cpu/fx68k'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/'rtl/cpu/fx68k'/name,target)
# Generated wiring only: all stimulus and assertions stay in the VHDL fixture.
(out/'fast_game_top.sv').write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Generated wiring-only simulation boundary, not a production source.
module fast_game_top(
    input i_clk, input i_chip_clk,
    output o_complete, output o_capture,
    output o_audio_sample, output [15:0] ou16_left_pcm, output [15:0] ou16_right_pcm,
    output [15:0] ou16_mono_pcm, output [8:0] ou9_adpcm_pcm, output o_adpcm_busy,
    output o_main_write, output [23:0] ou24_main_address,
    output [15:0] ou16_main_mask, output [15:0] ou16_main_data,
    output o_sound_write, output [15:0] ou16_sound_address, output [7:0] ou8_sound_data,
    output [23:0] ou24_rgb, output [31:0] ou32_cpu_writes, output [31:0] ou32_sound_writes,
    output [15:0] ou16_frame_count, output [11:0] ou12_maximum_row_clocks
);
wire [15:0] dq;
wire [12:0] address;
wire [1:0] bank;
wire chip_select, write_n, row_n, column_n;
gameplay_fast_fixture fixture (
    .i_clk(i_clk),
    .iou16_sdram_data(dq),
    .ou13_sdram_address(address),
    .ou2_sdram_bank(bank),
    .o_sdram_chip_select(chip_select),
    .o_sdram_write_n(write_n),
    .o_sdram_row_n(row_n),
    .o_sdram_column_n(column_n),
    .o_main_write(o_main_write),
    .ou24_main_address(ou24_main_address),
    .ou16_main_mask(ou16_main_mask),
    .ou16_main_data(ou16_main_data),
    .o_sound_write(o_sound_write),
    .ou16_sound_address(ou16_sound_address),
    .ou8_sound_data(ou8_sound_data),
    .o_audio_sample(o_audio_sample),
    .ou16_left_pcm(ou16_left_pcm),
    .ou16_right_pcm(ou16_right_pcm),
    .ou16_mono_pcm(ou16_mono_pcm),
    .ou9_adpcm_pcm(ou9_adpcm_pcm),
    .o_adpcm_busy(o_adpcm_busy),
    .o_complete(o_complete),
    .o_capture(o_capture),
    .ou24_rgb(ou24_rgb),
    .ou32_sound_writes(ou32_sound_writes),
    .ou16_frame_count(ou16_frame_count),
    .ou12_maximum_row_clocks(ou12_maximum_row_clocks),
    .ou32_cpu_writes(ou32_cpu_writes)
);
sdram_chip_model_wide chip (
    .clk(i_chip_clk),
    .SDRAM_DQ(dq),
    .SDRAM_A(address),
    .SDRAM_BA(bank),
    .SDRAM_nCS(chip_select),
    .SDRAM_nWE(write_n),
    .SDRAM_nRAS(row_n),
    .SDRAM_nCAS(column_n)
);
endmodule
''')
paths=[p for p in main_sources if p.endswith(('.v','.sv'))]
obj=out/'obj';bridge=out/'clock_bridge.cpp'
args=[str(suite/'bin/verilator_bin.exe'),'--cc','--exe',bridge.as_posix(),'--assert','--no-assert-case','-Wno-fatal','-Wno-ENUMVALUE','--no-timing','--timescale','1ps/1ps','--top-module','fast_game_top','--Mdir',obj.as_posix(),'-o','sim.exe','-CFLAGS','-O2 -DVL_USER_FATAL',(out/'fast_game_top.sv').as_posix(),(out/'gameplay_fast_fixture.v').as_posix()]+[(root/p).as_posix() for p in paths]
with (out/'verilate.log').open('w') as log:r=subprocess.run(args,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=300,**NO_WINDOW)
print('Fast live-game Verilation',r.returncode,flush=True)
if r.returncode:raise SystemExit((out/'verilate.log').read_text()[-7000:])
header=(obj/'Vfast_game_top___024root.h').read_text()
fields=re.findall(r'\b(\w*chip__DOT__mem)\s*;',header);assert len(fields)==1,fields
bridge.write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Clock, image/capture transport only. VHDL owns stimulus and assertions.
#include "Vfast_game_top.h"
#include "Vfast_game_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file,int line,const char*,const char* message) {
    std::fprintf(stderr,"VHDL_ASSERTION: %s:%d: %s\\n",file,line,message);std::exit(1);
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Vfast_game_top model;
    FILE* audio=std::fopen("audio_samples.txt","w");if(!audio)return 3;
    FILE* pixels=std::fopen("pixels.hex","w");
    if(!pixels) return 3;
    model.i_clk=0;model.i_chip_clk=0;model.eval();
    FILE* input=std::fopen("image_used.bin","rb");if(!input)return 3;
    for(unsigned index=0;index<1081344;index++) {
        unsigned lo=std::fgetc(input),hi=std::fgetc(input);
        model.rootp->'''+fields[0]+'''[index]=lo|(hi<<8);
    }
    std::fclose(input);
    FILE* main_trace=std::fopen("rtl_main_writes.txt","w");
    FILE* sound_trace=std::fopen("rtl_sound_writes.txt","w");
    if(!main_trace || !sound_trace)return 3;
    for(unsigned cycle=0;cycle<'''+str((options.frames+4)*774144+1000000)+''';cycle++) {
        model.i_clk=1;model.eval();
        if(model.o_main_write) std::fprintf(main_trace,"%06X %04X %04X\\n",unsigned(model.ou24_main_address),unsigned(model.ou16_main_mask),unsigned(model.ou16_main_data));
        if(model.o_sound_write) std::fprintf(sound_trace,"%04X FF %02X\\n",unsigned(model.ou16_sound_address),unsigned(model.ou8_sound_data));
        if(model.o_audio_sample) std::fprintf(audio,"%u %04X %04X %04X %03X %u %u\\n",cycle,unsigned(model.ou16_left_pcm),unsigned(model.ou16_right_pcm),unsigned(model.ou16_mono_pcm),unsigned(model.ou9_adpcm_pcm),unsigned(model.o_adpcm_busy),unsigned(model.ou16_frame_count));
        if(model.o_capture) std::fprintf(pixels,"%06X\\n",unsigned(model.ou24_rgb));
        if((cycle%500000)==0) {std::printf("cycle=%u cpu_writes=%u\\n",cycle,unsigned(model.ou32_cpu_writes));std::fflush(stdout);}
        if(model.o_complete) {
            FILE* image=std::fopen("loaded_image.bin","wb");if(!image)return 3;
            for(unsigned index=0;index<1081344;index++) {
                unsigned word=model.rootp->'''+fields[0]+'''[index];
                std::fputc(word&255,image);std::fputc((word>>8)&255,image);
            }
            std::fclose(audio);std::fclose(image);std::fclose(main_trace);std::fclose(sound_trace);model.final();std::fclose(pixels);
            std::printf("FAST_GAME_COMPLETE cycles=%u cpu_writes=%u sound_writes=%u frames=%u max_row_clocks=%u\\n",cycle+1,unsigned(model.ou32_cpu_writes),unsigned(model.ou32_sound_writes),unsigned(model.ou16_frame_count),unsigned(model.ou12_maximum_row_clocks));return 0;
        }
        Verilated::timeInc(5357);model.i_chip_clk=1;model.eval();
        Verilated::timeInc(5357);model.i_clk=0;model.eval();
        Verilated::timeInc(5357);model.i_chip_clk=0;model.eval();
        Verilated::timeInc(5357);
    }
    std::fclose(pixels);return 2;
}
''')
with (out/'build.log').open('w') as log:r=subprocess.run([str(dev/'make.exe'),'-C',obj.as_posix(),'-f','Vfast_game_top.mk','-j1'],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=options.wall_timeout,**NO_WINDOW)
print('Fast live-game build',r.returncode,flush=True)
if r.returncode:raise SystemExit((out/'build.log').read_text()[-5000:])
with (out/'run.log').open('w') as log:r=subprocess.run([str(obj/'sim.exe')],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=options.wall_timeout,**NO_WINDOW)
print('Fast live-game run',r.returncode,flush=True);print((out/'run.log').read_text()[-2500:])



# Original ROM regions stay private. The model preloads only the external chip ROM image.
assert r.returncode == 0, (out / 'run.log').read_text()[-2500:]
from check_sound_board_boot import compare_startup, read_trace
main_trace = reference_root / 'debug/boot_writes' / options.game / 'mame_writes.txt'
assert sha(main_trace) == main_reference['mame_trace_sha256']
sound_trace = reference_root / sound_reference['trace']
assert sha(sound_trace) == sound_reference['trace_sha256']
expected = [tuple(int(word,16) for word in line.split()) for line in main_trace.read_text().splitlines()][:10000]
actual = [tuple(int(word,16) for word in line.split()) for line in (out / 'rtl_main_writes.txt').read_text().splitlines()]
assert actual[:10000] == expected and len(actual) >= 10000, 'Live main startup prefix differs from MAME'
sound_actual = read_trace(out / 'rtl_sound_writes.txt')
comparison = compare_startup(read_trace(sound_trace)[:4096], sound_actual[:4096], native_reset=True)
pixels = (out / 'pixels.hex').read_text().splitlines()
assert len(pixels) == 62208
rgb = bytes.fromhex(''.join(pixels))
write_rgb(out / 'video.png',288,216,rgb)
assert (out / 'loaded_image.bin').read_bytes() == image
assert input_hashes == {name:sha(root/name) for name in input_names}
assert tool_hashes == {name:sha(path) for name,path in tool_paths.items()}
log = (out/'run.log').read_text()
maximum_row_clocks = int(re.search(r'max_row_clocks=(\d+)',log)[1])
assert 0 < maximum_row_clocks <= 3024
for name in ('microrom.mem','nanorom.mem'):
    assert sha(out/'rtl/cpu/fx68k'/name) == input_hashes['rtl/cpu/fx68k/'+name]
audio_lines = [line.split() for line in (out/'audio_samples.txt').read_text().splitlines()]
assert len(audio_lines) > options.frames * 900
sample_cycles = [int(row[0]) for row in audio_lines]
intervals = [b-a for a,b in zip(sample_cycles,sample_cycles[1:])]
assert set(intervals) <= {746,747}, set(intervals)
channels = [[int(row[index],16) for row in audio_lines] for index in (1,2,3,4)]
import wave
with wave.open(str(out/'mono.wav'),'wb') as wav:
    wav.setparams((1,2,62500,0,'NONE','not compressed'))
    wav.writeframes(b''.join(value.to_bytes(2,'little') for value in channels[2]))
assert any(channels[2]), 'Completed live test produced no mixed PCM activity'
audio_report = dict(samples=len(audio_lines),sample_rate_hz=62500,minimum_interval_clocks=min(intervals),maximum_interval_clocks=max(intervals),
    nonzero={name:sum(value!=0 for value in values) for name,values in zip(('fm_left','fm_right','mono','adpcm'),channels)},
    adpcm_busy_samples=sum(int(row[5])!=0 for row in audio_lines),pcm_sha256=sha(out/'audio_samples.txt'),wav_sha256=sha(out/'mono.wav'),
    scope='Actual mixed mono, raw FM stereo and ADPCM PCM observed from the executing system. This prevents unused sound output pruning. Native-clock sample cadence checked; no independent waveform or physical audible comparison yet.')
report = dict(accepted=True,audio=audio_report,coin_frame=options.coin_frame,start_frame=options.start_frame,action_frame=options.action_frame,set=options.game,frames=options.frames,maximum_row_clocks=maximum_row_clocks,
    cycles=int(re.search(r'FAST_GAME_COMPLETE cycles=(\d+)',log)[1]),elapsed_seconds=time.monotonic()-started,
    log_sha256=sha(out/'run.log'),ram_contract_sha256=sha(root/'docs/reference/fast_ram_loader_contract_checks.json'),
    mame_main_trace_sha256=sha(main_trace),mame_sound_trace_sha256=sha(sound_trace),
    rtl_main_trace_sha256=sha(out/'rtl_main_writes.txt'),rtl_sound_trace_sha256=sha(out/'rtl_sound_writes.txt'),
    generated_sha256={path.relative_to(out).as_posix():sha(path) for path in out.iterdir() if path.is_file()},main_writes=len(actual),sound_writes=len(sound_actual),
    mame_main_prefix=10000,mame_sound_comparison=comparison,pixels=62208,
    nonblack_pixels=sum(int(pixel,16)!=0 for pixel in pixels),image_sha256=sha(out/'image_used.bin'),
    rgb_sha256=hashlib.sha256(rgb).hexdigest(),source_sha256=input_hashes,tool_sha256=tool_hashes,
    scope='Supplemental two-state bounded live real-ROM execution with both CPUs, JT51/JT7759, shared SDRAM and native raster/rendering. Qualified logical on-chip RAM; synthetic system/chip clocks; external chip ROM image preloaded, original 32-byte header downloaded, no CPU/RAM deposits. Ordered main/sound startup prefixes compared to MAME, four audited reset stack-byte positions exposed; capture coordinates, row deadlines and no underflow checked. Unsupported T80 block-I/O flag path traps. Frame RGB is a capture, not a temporally aligned MAME image proof; scripted coin/start/shoot/missile and motion stimulus, actual PCM captured; no independent waveform, playability, physical hardware or full-image loader claim.')
(root / f'docs/reference/gameplay_fast_{case}_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS bounded live game',options.game,options.frames,'frames',report['nonblack_pixels'],'nonblack pixels',flush=True)
