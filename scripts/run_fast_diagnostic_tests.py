# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Execute the original main-board diagnostic with qualified fast RAM abstractions."""
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
parser.add_argument('--load-mode', choices=['word','byte','ddr'], default='word')
parser.add_argument('--corrupt', action='store_true', help='Corrupt the checked ROM word; expect DEAD and red replacement stripes')
parser.add_argument('--wall-timeout', type=int, default=1200)
options = parser.parse_args()
if options.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
require_no_jtag('Fast full-image main-board diagnostic')
case = ('corrupt' if options.corrupt else 'known') + ('' if options.load_mode == 'word' else '_' + options.load_mode)
out = root / 'debug/fast_diagnostic' / case
out.mkdir(parents=True, exist_ok=True)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
contract = json.loads((root / 'docs/reference/fast_ram_contract_checks.json').read_text())
assert contract['accepted']
assert sha(root / 'scripts/run_fast_ram_tests.py') == contract['runner_sha256'], 'Requalify the RAM runner first'
for name, expected in contract['native_comparison']['source_sha256'].items():
    if name.replace('\\','/').startswith('rtl/'):
        assert sha(root / name) == expected, 'Native RAM wrapper changed; requalify: ' + name
for name, expected in contract['source_sha256'].items():
    assert sha(root / name) == expected, 'Requalify the logical RAM contract first: ' + name
all_sources = system_sources()
main_sources = all_sources[:all_sources.index('rtl/cpu/t80/T80_Pack.vhd')]
main_sources += ['rtl/rabbitpunch_audio_mixer.vhd', 'rtl/rabbitpunch_system.vhd']
# The sound module is deliberately idle in this main-board-only composition.
input_names = list(dict.fromkeys(main_sources + [
    'scripts/run_fast_diagnostic_tests.py','scripts/build_diagnostic_rom.py',
    'scripts/run_system_download_tests.py','scripts/build_mras.py','scripts/png_rgb.py',
    'scripts/coretools.py','scripts/mra.py','rtl/cpu/fx68k/microrom.mem','rtl/cpu/fx68k/nanorom.mem',
    'sim/fast/rabbitpunch_ram16_model.vhd','sim/fast/rabbitpunch_ram8_model.vhd',
    'sim/board/diagnostic_video_tb.vhd','rtl/rabbitpunch_clock_enables.vhd',
    'rtl/rabbitpunch_raster.vhd','rtl/rabbitpunch_scanline_scheduler.vhd',
    'rtl/rabbitpunch_video_output.vhd','rtl/rabbitpunch_scanout.vhd']))
if options.load_mode != 'word':
    input_names += ['sim/fast/diagnostic_load_source.vhd','rtl/rabbitpunch_load_frontend.vhd',
                    'rtl/rabbitpunch_ddr_copy.vhd','rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv']
input_hashes = {name: sha(root / name) for name in input_names}
firmware = out / 'firmware'
subprocess.check_call([sys.executable,str(root / 'scripts/build_diagnostic_rom.py'),
                       '--output-dir',str(firmware)], **NO_WINDOW)
firmware_metadata = json.loads((firmware / 'manifest.json').read_text())
version = ET.parse(firmware / 'RabbitPunch_Diagnostic.mra').getroot().findtext('mameversion')
assert version == firmware_metadata['mameversion'] and re.fullmatch('[0-9]{4}', version)
image = bytearray((firmware / 'image.bin').read_bytes())
assert len(image) == 0x210000 and image[0x20000:0x20002] == bytes.fromhex('A55A')
if options.corrupt:
    image[0x20001] ^= 1
(out / 'image_used.bin').write_bytes(image)
physical = [word for word, in struct.iter_unpack('<H', image)]
assert all(word != 0x5A3C for word in physical), 'Chosen nonzero poison must differ at every image word'
image_words = len(physical)
sparse = [(index,word) for index,word in enumerate(physical) if word]
package = """-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
-- Sparse original diagnostic image from the independently assembled inline MRA.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
package diagnostic_program is
    function program_word(iint_address : natural) return unsigned;
end package;
package body diagnostic_program is
    function program_word(iint_address : natural) return unsigned is
    begin
        case iint_address is
""" + ''.join(f'            when {index} =>\n                return x"{word:04X}";\n' for index,word in sparse) + """            when others =>
                return x"0000";
        end case;
    end function;
end package body;
"""
(out / 'diagnostic_program.vhd').write_text(package)
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
text=(root/'rtl/rabbitpunch_system.vhd').read_text()
start=text.index('    audio : entity work.rabbitpunch_audio')
end=text.index('    roms : entity work.rabbitpunch_roms',start)
idle='''    -- Fast main-board diagnostic only: audio is idle and excluded.
    s_audio_paused <= '1';
    s_sound_command_read <= '0';
    s_audio_request <= '0';
    su16_audio_address <= (others => '0');
    s_sample_request <= '0';
    su18_sample_address <= (others => '0');
    su9_sample_pcm <= (others => '0');
    o_adpcm_busy <= '0';
    su16_fm_left <= (others => '0');
    su16_fm_right <= (others => '0');
    s_fm_sample_marker <= '0';
    ou8_audio_view_data <= (others => '0');
    o_audio_debug_request <= '0';
    o_audio_debug_write <= '0';
    ou16_audio_debug_address <= (others => '0');
    ou8_audio_debug_data <= (others => '0');
'''
text=text[:start]+idle+text[end:]
(out/'rabbitpunch_system_main_only.vhd').write_text('-- Fast diagnostic-only composition; production audio unchanged and separately verified.\n'+text)
for name in ('rabbitpunch_tiles.vhd','rabbitpunch_system_main_only.vhd'):
    path = out / name
    path.write_text('-- SPDX-License-Identifier: GPL-3.0-or-later\n-- Copyright (C) 2026 RabbitPunch contributors\n' + path.read_text())

# VHDL-owned stimulus and assertions.
s=(root/'sim/board/diagnostic_video_tb.vhd').read_text()
s=s.replace('diagnostic_video_tb','diagnostic_fast_fixture').replace('use std.env.all;','').replace('use std.textio.all;','use work.diagnostic_program.all;')
s=s.replace('GINT_DOWNLOAD_WORDS : positive := 16;',f'GINT_DOWNLOAD_WORDS : positive := {image_words};')
s=s.replace('end entity;', '''    port (
        i_clk : in std_logic;
        iou16_sdram_data : inout unsigned(15 downto 0);
        ou13_sdram_address : out unsigned(12 downto 0);
        ou2_sdram_bank : out unsigned(1 downto 0);
        o_sdram_chip_select : out std_logic;
        o_sdram_write_n : out std_logic;
        o_sdram_row_n : out std_logic;
        o_sdram_column_n : out std_logic;
        o_complete : out std_logic := '0';
        o_capture : out std_logic := '0';
        ou24_rgb : out unsigned(23 downto 0) := (others => '0');
        ou16_bitmap_words : out unsigned(15 downto 0) := (others => '0')
    );
end entity;''')
start=s.index('    component sdram_chip_model_wide');end=s.index('    signal s_download',start)
s=s[:start]+s[end:]
s=s.replace('    signal s_download', '    signal s_main_phase_enable, s_fractional_sound, s_fractional_ym, s_fractional_half, s_fractional_adpcm : std_logic;\n    signal s_download', 1)
s=s.replace('    signal su16_dq : unsigned(15 downto 0);\n','').replace('su16_dq','iou16_sdram_data').replace('s_clk','i_clk')
# Preserve the real enables/scanout, replacing only the analog PLL source with
# the external simulator clock. Chip pin clock belongs to generated wiring.
start=s.index('    s_reference_clk <=');end=s.index('    enables : entity',start)
s=s[:start]+'''    ou13_sdram_address <= su13_sdram_address;
    ou2_sdram_bank <= su2_bank;
    o_sdram_chip_select <= s_chip;
    o_sdram_write_n <= s_write_n;
    o_sdram_row_n <= s_row_n;
    o_sdram_column_n <= s_column_n;
'''+s[end:]
start=s.index('    chip : sdram_chip_model_wide');end=s.index('    monitor : process',start);s=s[:start]+s[end:]
s=s.replace('        file v_progress : text open write_mode is "progress.txt";\n','').replace('        file v_pixels : text open write_mode is "pixels.hex";\n','').replace('        variable v_line : line;\n','')
s=s.replace('            if (GBOOL_EXPECT_FAILURE) then', "            o_capture <= '0';\n            ou16_bitmap_words <= to_unsigned(vint_bitmap_words, 16);\n            if (GBOOL_EXPECT_FAILURE) then",1)
s=s.replace('                    hwrite(v_line, su8_output_red & su8_output_green & su8_output_blue);\n                    writeline(v_pixels, v_line);', "                    o_capture <= '1';\n                    ou24_rgb <= su8_output_red & su8_output_green & su8_output_blue;")
s=s.replace('                    finish;', "                    o_complete <= '1';")
start=s.index('            if (vint_progress = 47999) then');end=s.index('        end if;\n    end process;',start)
s=s[:start]+s[end:]
start=s.index('    stimulus : process');s=s[:start]+'''    -- Complete sparse original image traverses the production download interface.
    stimulus : process(i_clk)
        type t_download_state is (STATE_START, STATE_WAIT_READY, STATE_DROP_VALID, STATE_DRAIN, STATE_DELAY, STATE_RUN);
        variable styp_download_state : t_download_state := STATE_START;
        variable vint_word : natural range 0 to GINT_DOWNLOAD_WORDS - 1 := 0;
        variable vint_delay : natural range 0 to 9334 := 0;
    begin
        if (rising_edge(i_clk)) then
            case styp_download_state is
                when STATE_START =>
                    s_download <= '1';
                    styp_download_state := STATE_WAIT_READY;
                when STATE_WAIT_READY =>
                    if (s_word_ready = '1') then
                        su27_address <= to_unsigned(vint_word * 2, 27);
                        su16_data <= program_word(vint_word, GBOOL_EXPECT_FAILURE);
                        s_word_valid <= '1';
                        styp_download_state := STATE_DROP_VALID;
                    end if;
                when STATE_DROP_VALID =>
                    s_word_valid <= '0';
                    if (vint_word = GINT_DOWNLOAD_WORDS - 1) then
                        s_download <= '0';
                        styp_download_state := STATE_DRAIN;
                    else
                        vint_word := vint_word + 1;
                        styp_download_state := STATE_WAIT_READY;
                    end if;
                when STATE_DRAIN =>
                    if (s_ready = '1') then
                        assert (s_image_valid = '1' and s_error = '0')
                            report "Fast diagnostic image failed load validation" severity failure;
                        styp_download_state := STATE_DELAY;
                    end if;
                when STATE_DELAY =>
                    if (vint_delay = 9334) then
                        s_run <= '1';
                        styp_download_state := STATE_RUN;
                    else
                        vint_delay := vint_delay + 1;
                    end if;
                when STATE_RUN =>
                    null;
            end case;
        end if;
    end process;
end architecture;
'''
# State-machine variables follow the user's variable convention, with t_ type.
s=s.replace('variable styp_download_state','variable v_download_state').replace('styp_download_state','v_download_state')
s=s.replace('program_word(vint_word, GBOOL_EXPECT_FAILURE)','program_word(vint_word)')
s=s.replace("            if (s_ready = '1') then", "            assert (s_sound_pending = '0') report \"Fast main-board diagnostic excludes sound commands\" severity failure;\n            if (s_ready = '1') then",1)
if options.load_mode != 'word':
    s=s.replace('    signal s_download', '    signal s_frontend_complete : std_logic;\n    signal s_download', 1)
    start=s.index('    -- Complete sparse original image')
    s=s[:start]+"""    frontend_source : entity work.diagnostic_load_source
        generic map (
            GBOOL_DDR_MODE => """+str(options.load_mode == 'ddr').lower()+"""
        )
        port map (
            i_clk => i_clk,
            i_word_ready => s_word_ready,
            o_download_active => s_download,
            o_word_valid => s_word_valid,
            ou27_word_byte_address => su27_address,
            ou16_word_data => su16_data,
            o_complete => s_frontend_complete
        );
    release_cpu : process(i_clk)
        variable vint_delay : natural range 0 to 9334 := 0;
    begin
        if (rising_edge(i_clk)) then
            if (s_frontend_complete = '1' and s_ready = '1') then
                assert (s_image_valid = '1' and s_error = '0')
                    report "Frontend-loaded diagnostic image failed validation" severity failure;
                if (vint_delay = 9334) then
                    s_run <= '1';
                else
                    vint_delay := vint_delay + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
"""
(out/'diagnostic_fast_fixture.vhd').write_text(s)
# Input copies from the successful main-only export remain explicitly scoped.
sources=[p for p in main_sources if p.endswith('.vhd')]
sources=[p.replace('rtl/rabbitpunch_ram16.vhd','sim/fast/rabbitpunch_ram16_model.vhd').replace('rtl/rabbitpunch_ram8.vhd','sim/fast/rabbitpunch_ram8_model.vhd') for p in sources]
sources=[str((out/'rabbitpunch_tiles.vhd').relative_to(root)) if p=='rtl/rabbitpunch_tiles.vhd' else str((out/'rabbitpunch_system_main_only.vhd').relative_to(root)) if p=='rtl/rabbitpunch_system.vhd' else p for p in sources]
sources+=['rtl/rabbitpunch_clock_enables.vhd','rtl/rabbitpunch_raster.vhd','rtl/rabbitpunch_scanline_scheduler.vhd','rtl/rabbitpunch_video_output.vhd','rtl/rabbitpunch_scanout.vhd',str((out/'diagnostic_program.vhd').relative_to(root)),str((out/'diagnostic_fast_fixture.vhd').relative_to(root))]
if options.load_mode != 'word':
    sources[-1:-1] = ['rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','sim/fast/diagnostic_load_source.vhd']
args=[str(ghdl),'--synth','--std=08','-fsynopsys','--out=verilog','-gGBOOL_EXPECT_FAILURE='+str(options.corrupt).lower()]+[str(root/p) for p in sources]+['-e','diagnostic_fast_fixture']
r=subprocess.run(args,cwd=out,capture_output=True,text=True,timeout=300,**NO_WINDOW)
(out/'diagnostic_fast_fixture.v').write_text(r.stdout);(out/'export.log').write_text(r.stderr)
(out/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
assert r.returncode == 0, r.stderr
print('PASS VHDL fast diagnostic export',flush=True)

# Restore transparent bidirectional port associations in generated Verilog.
p=out/'diagnostic_fast_fixture.v';raw=p.read_text();(out/'diagnostic_fast_fixture_raw.v').write_text(raw)
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
(out/'fast_diagnostic_top.sv').write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Generated wiring-only simulation boundary, not a production source.
module fast_diagnostic_top(
    input i_clk, input i_chip_clk,
    output o_complete, output o_capture,
    output [23:0] ou24_rgb, output [15:0] ou16_bitmap_words
);
wire [15:0] dq;
wire [12:0] address;
wire [1:0] bank;
wire chip_select, write_n, row_n, column_n;
diagnostic_fast_fixture fixture (
    .i_clk(i_clk),
    .iou16_sdram_data(dq),
    .ou13_sdram_address(address),
    .ou2_sdram_bank(bank),
    .o_sdram_chip_select(chip_select),
    .o_sdram_write_n(write_n),
    .o_sdram_row_n(row_n),
    .o_sdram_column_n(column_n),
    .o_complete(o_complete),
    .o_capture(o_capture),
    .ou24_rgb(ou24_rgb),
    .ou16_bitmap_words(ou16_bitmap_words)
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
paths=['rtl/cpu/fx68k/fx68k.sv','rtl/cpu/fx68k/fx68kAlu.sv','rtl/cpu/fx68k/uaddrPla.sv','rtl/jtframe/jtframe_draw.v','rtl/memory/sdram/sdram.sv','sim/vendor/sdram/sdram_chip_model_wide.sv']
if options.load_mode != 'word':
    paths += ['rtl/memory/ddram/ddram_phy.sv','rtl/memory/ddram/rom_loader.sv']
obj=out/'obj';bridge=out/'clock_bridge.cpp'
args=[str(suite/'bin/verilator_bin.exe'),'--cc','--exe',bridge.as_posix(),'--assert','--no-assert-case','-Wno-fatal','-Wno-ENUMVALUE','--no-timing','--timescale','1ps/1ps','--top-module','fast_diagnostic_top','--Mdir',obj.as_posix(),'-o','sim.exe','-CFLAGS','-O2 -DVL_USER_FATAL',(out/'fast_diagnostic_top.sv').as_posix(),(out/'diagnostic_fast_fixture.v').as_posix()]+[(root/p).as_posix() for p in paths]
with (out/'verilate.log').open('w') as log:r=subprocess.run(args,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=300,**NO_WINDOW)
print('Fast diagnostic Verilation',r.returncode,flush=True)
if r.returncode:raise SystemExit((out/'verilate.log').read_text()[-7000:])
header=(obj/'Vfast_diagnostic_top___024root.h').read_text()
fields=re.findall(r'\b(\w*chip__DOT__mem)\s*;',header);assert len(fields)==1,fields
bridge.write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Clock, image/capture transport only. VHDL owns stimulus and assertions.
#include "Vfast_diagnostic_top.h"
#include "Vfast_diagnostic_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file,int line,const char*,const char* message) {
    std::fprintf(stderr,"VHDL_ASSERTION: %s:%d: %s\\n",file,line,message);std::exit(1);
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Vfast_diagnostic_top model;
    FILE* pixels=std::fopen("pixels.hex","w");
    if(!pixels) return 3;
    model.i_clk=0;model.i_chip_clk=0;model.eval();
    // Adversarial SDRAM precondition, not ROM data or board/CPU state.
    for(unsigned index=0;index<1081344;index++) model.rootp->'''+fields[0]+'''[index]=0x5A3C;
    for(unsigned cycle=0;cycle<60000000;cycle++) {
        model.i_clk=1;model.eval();
        if(model.o_capture) std::fprintf(pixels,"%06X\\n",unsigned(model.ou24_rgb));
        if((cycle%500000)==0) {std::printf("cycle=%u bitmap_words=%u\\n",cycle,unsigned(model.ou16_bitmap_words));std::fflush(stdout);}
        if(model.o_complete) {
            FILE* image=std::fopen("loaded_image.bin","wb");if(!image)return 3;
            for(unsigned index=0;index<1081344;index++) {
                unsigned word=model.rootp->'''+fields[0]+'''[index];
                std::fputc(word&255,image);std::fputc((word>>8)&255,image);
            }
            std::fclose(image);model.final();std::fclose(pixels);
            std::printf("FAST_DIAGNOSTIC_COMPLETE cycles=%u bitmap_words=%u\\n",cycle+1,unsigned(model.ou16_bitmap_words));return 0;
        }
        Verilated::timeInc(5357);model.i_chip_clk=1;model.eval();
        Verilated::timeInc(5357);model.i_clk=0;model.eval();
        Verilated::timeInc(5357);model.i_chip_clk=0;model.eval();
        Verilated::timeInc(5357);
    }
    std::fclose(pixels);return 2;
}
''')
with (out/'build.log').open('w') as log:r=subprocess.run([str(dev/'make.exe'),'-C',obj.as_posix(),'-f','Vfast_diagnostic_top.mk','-j1'],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=options.wall_timeout,**NO_WINDOW)
print('Fast diagnostic build',r.returncode,flush=True)
if r.returncode:raise SystemExit((out/'build.log').read_text()[-5000:])
with (out/'run.log').open('w') as log:r=subprocess.run([str(obj/'sim.exe')],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=options.wall_timeout,**NO_WINDOW)
print('Fast diagnostic run',r.returncode,flush=True);print((out/'run.log').read_text()[-2500:])



# Independent complete-image and native RGB oracles.
assert r.returncode == 0, (out / 'run.log').read_text()[-2500:]
log = (out / 'run.log').read_text()
assert 'FAST_DIAGNOSTIC_COMPLETE' in log and 'bitmap_words=32768' in log
loaded = (out / 'loaded_image.bin').read_bytes()
assert loaded == image, 'Full image differs after overwriting nonzero SDRAM poison'
pixels = (out / 'pixels.hex').read_text().splitlines()
assert len(pixels) == 62208 and all(re.fullmatch('[0-9A-F]{6}',pixel) for pixel in pixels)
rgb = bytes.fromhex(''.join(pixels))
row = bytes.fromhex('FF0000 00FF00 0000FF ' + ('FF0000' if options.corrupt else 'FFFFFF')) * 72
assert rgb == row * 216, 'Native diagnostic RGB differs from independent stripe oracle'
write_rgb(out / 'video.png',288,216,rgb)
assert input_hashes == {name: sha(root / name) for name in input_names}
assert tool_hashes == {name:sha(path) for name,path in tool_paths.items()}
for name in ('microrom.mem','nanorom.mem'):
    assert sha(out / 'rtl/cpu/fx68k' / name) == input_hashes['rtl/cpu/fx68k/' + name]
report = dict(accepted=True,load_mode=options.load_mode,mameversion=version,corrupt_rom=options.corrupt,downloaded_bytes=len(image),
    initial_sdram_word='5A3C',poison_differs_from_every_loaded_word=True,
    bitmap_words=32768,pixels=62208,differing_pixels=0,image_sha256=sha(out / 'image_used.bin'),
    readback_sha256=sha(out / 'loaded_image.bin'),rgb_sha256=hashlib.sha256(rgb).hexdigest(),
    cycles=int(re.search(r'FAST_DIAGNOSTIC_COMPLETE cycles=(\d+)',log)[1]),
    row_budget_clocks=3024,elapsed_seconds=time.monotonic()-started,
    source_sha256=input_hashes,tool_sha256=tool_hashes,ram_contract_sha256=sha(root / 'docs/reference/fast_ram_contract_checks.json'),
    generated_sha256={path.relative_to(out).as_posix():sha(path) for path in out.iterdir() if path.is_file()},
    dq_alias_normalization=json.loads((out / 'dq_alias_normalization.json').read_text()),
    scope='Supplemental two-state main-board diagnostic with separately qualified logical on-chip RAMs, idle/excluded sound, synthetic 21428-ps system period and 5357-ps chip-clock phase. Every external SDRAM image word starts at nonzero poison distinct from its required value. All 0x210000 original firmware bytes traverse the selected loader path and production word-loader/SDRAM controller and unchanged chip command model; exact complete readback, real fx68k executed full bitmap fill, ROM branch, drained signature inspection and native 288x216 image pass retained VHDL and independent Python checks. Generated copies normalize combinational tile-port expressions and bidirectional aliases; production/vendor RTL is unchanged. Vendor reset-time unique-case checks are disabled separately from retained explicit VHDL assertions. No CPU/board-RAM state deposit or ROM preload; not native Intel RAM, PLL, four-state, physical HPS/DDR, audio, game-ROM gameplay, SDF/electrical or physical hardware proof.')
if options.load_mode != 'word':
    report['frontend'] = dict(byte_download=options.load_mode == 'byte',ddr_staging=options.load_mode == 'ddr',
        accepted_words=image_words,ddr_reads=image_words // 4 if options.load_mode == 'ddr' else 0,
        scope='Actual HPS-signal frontend, DDR copier and unchanged DDR PHY/rom_loader with behavioral delayed DDR replies, periodic busy, spoiled invalid pins and per-word VHDL assertions. No hps_io parser, real HPS or physical DDR proof.')
(root / f'docs/reference/fast_diagnostic_{case}_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'PASS fast diagnostic {case}: full poisoned-image readback, 32768 executed bitmap words, 62208 exact RGB pixels',flush=True)
