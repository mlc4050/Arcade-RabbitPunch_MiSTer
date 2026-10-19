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
parser.add_argument('--frames', type=int, default=120)
parser.add_argument('--reference-root', type=Path, required=True)
parser.add_argument('--load-mode', choices=['word','byte','ddr'], default='word')
parser.add_argument('--corrupt', action='store_true', help='Corrupt the checked ROM word; expect DEAD and red replacement stripes')
parser.add_argument('--wall-timeout', type=int, default=1200)
options = parser.parse_args()
if options.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
require_no_jtag('Fast full-image main-board diagnostic')
assert options.load_mode == 'word' and not options.corrupt
assert 2 <= options.frames <= 1800
case = options.game + '_' + str(options.frames)
out = root / 'debug/fast_game' / case
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
main_sources = all_sources[:-1]
# All production CPU, sound and memory components are retained.
input_names = list(dict.fromkeys(main_sources + [
    'scripts/run_fast_game_tests.py','scripts/run_fast_sound_boot_tests.py',
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
package diagnostic_program is
    function program_word(iint_address : natural) return unsigned;
end package;
package body diagnostic_program is
    function program_word(iint_address : natural) return unsigned is
    begin
        case iint_address is
""" + ''.join(f'            when {index} =>\n                return x"{word:04X}";\n' for index,word in enumerate(physical[:16])) + """            when others =>
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
# Preserve the unsupported T80 path as a fatal boundary, matching the sound qualification.
text = (root / 'rtl/cpu/t80/T80.vhd').read_text()
mask = '(ioq and x"7")'
assert text.count(mask) == 1
text = text.replace(mask, '(ioq and "000000111")')
guard = "    assert not (RESET_n = '1' and DIRSet = '0' and ClkEn = '1' and (((TState = 2 and I_BTR = '1' and IR(0) = '1') or (TState = 1 and I_BTR = '1' and IR(0) = '0')))) report \"FAST_T80_UNSUPPORTED_BLOCK_IO_FLAGS\" severity failure;"
assert text.count('\nbegin\n') == 1
text = text.replace('\nbegin\n', '\nbegin\n' + guard + '\n', 1)
(out / 'T80.vhd').write_text('-- Modified tool-only T80 copy; affected unsupported block-I/O path must trap.\n' + text)

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
s=s.replace('        o_complete : out std_logic', "        o_main_write : out std_logic := '0';\n        ou24_main_address : out unsigned(23 downto 0);\n        ou16_main_mask : out unsigned(15 downto 0);\n        ou16_main_data : out unsigned(15 downto 0);\n        o_sound_write : out std_logic := '0';\n        ou16_sound_address : out unsigned(15 downto 0);\n        ou8_sound_data : out unsigned(7 downto 0);\n" + '        o_complete : out std_logic', 1)
s=s.replace('CINT_DIP_DEFAULT : natural := 0;', 'CINT_DIP_DEFAULT : natural := ' + str(dips) + ';')
start=s.index('    monitor : process')
end=s.index('    -- Complete sparse original image', start)
s=s[:start] + '    monitor : process(i_clk)\n        variable vint_pixels : natural range 0 to 62208 := 0;\n        variable vint_frames, vint_main, vint_lines, vint_render_cycles : natural := 0;\n        variable v_rendering, v_capture : boolean := false;\n        variable vu16_mask : unsigned(15 downto 0);\n    begin\n        if (rising_edge(i_clk)) then\n            o_capture <= \'0\';\n            o_main_write <= \'0\';\n            o_sound_write <= \'0\';\n            ou16_bitmap_words <= to_unsigned(vint_main mod 65536, 16);\n            if (s_ready = \'1\') then\n                assert (s_error = \'0\' and s_underflow = \'0\') report "Live game load/scanout failure" severity failure;\n            end if;\n            if (s_line_valid = \'1\' and s_line_ready = \'1\') then\n                assert (not v_rendering) report "Overlapping live game rows" severity failure;\n                v_rendering := true;\n                vint_render_cycles := 0;\n            end if;\n            if (v_rendering) then\n                vint_render_cycles := vint_render_cycles + 1;\n            end if;\n            if (s_line_done = \'1\') then\n                assert (v_rendering and vint_render_cycles <= 3024) report "Live game row missed its deadline" severity failure;\n                v_rendering := false;\n                vint_lines := vint_lines + 1;\n            end if;\n            if (s_run = \'1\') then\n                if (s_cpu_request = \'1\' and s_cpu_write = \'1\') then\n                    o_main_write <= \'1\';\n                    ou24_main_address <= su24_cpu_address and x"0FFFFF";\n                    vu16_mask := (others => \'0\');\n                    if (su2_cpu_bytes(0) = \'1\') then\n                        vu16_mask(7 downto 0) := (others => \'1\');\n                    end if;\n                    if (su2_cpu_bytes(1) = \'1\') then\n                        vu16_mask(15 downto 8) := (others => \'1\');\n                    end if;\n                    ou16_main_mask <= vu16_mask;\n                    ou16_main_data <= su16_cpu_data and vu16_mask;\n                    vint_main := vint_main + 1;\n                end if;\n                if (s_audio_request = \'1\' and s_audio_write = \'1\') then\n                    o_sound_write <= \'1\';\n                    ou16_sound_address <= su16_audio_address;\n                    ou8_sound_data <= su8_audio_data;\n                end if;\n                if (s_vblank_start = \'1\') then\n                    vint_frames := vint_frames + 1;\n                end if;\n                if (s_output_enable = \'1\' and s_output_active = \'1\') then\n                    if (vint_frames >= FRAME_NUMBER and vint_pixels = 0 and su9_output_x = 8 and su8_output_y = 0) then\n                        v_capture := true;\n                    end if;\n                    if (v_capture and vint_pixels < 62208) then\n                        assert (su9_output_x = 8 + vint_pixels mod 288 and su8_output_y = vint_pixels / 288)\n                            report "Live game capture coordinate ordering mismatch" severity failure;\n                        o_capture <= \'1\';\n                        ou24_rgb <= su8_output_red & su8_output_green & su8_output_blue;\n                        vint_pixels := vint_pixels + 1;\n                        if (vint_pixels = 62208) then\n                            o_complete <= \'1\';\n                            s_pause <= \'1\';\n                        end if;\n                    end if;\n                end if;\n            end if;\n        end if;\n    end process;\n'.replace('FRAME_NUMBER',str(options.frames)) + s[end:]
(out/'diagnostic_fast_fixture.vhd').write_text(s)
# Input copies from the successful main-only export remain explicitly scoped.
sources=[p for p in main_sources if p.endswith('.vhd')]
sources=[p.replace('rtl/rabbitpunch_ram16.vhd','sim/fast/rabbitpunch_ram16_model.vhd').replace('rtl/rabbitpunch_ram8.vhd','sim/fast/rabbitpunch_ram8_model.vhd') for p in sources]
sources=[str((out/'rabbitpunch_tiles.vhd').relative_to(root)) if p=='rtl/rabbitpunch_tiles.vhd' else p for p in sources]
sources=[str((out/'T80.vhd').relative_to(root)) if p=='rtl/cpu/t80/T80.vhd' else p for p in sources]
sources+=['rtl/rabbitpunch_clock_enables.vhd','rtl/rabbitpunch_raster.vhd','rtl/rabbitpunch_scanline_scheduler.vhd','rtl/rabbitpunch_video_output.vhd','rtl/rabbitpunch_scanout.vhd',str((out/'diagnostic_program.vhd').relative_to(root)),str((out/'diagnostic_fast_fixture.vhd').relative_to(root))]
if options.load_mode != 'word':
    sources[-1:-1] = ['rtl/rabbitpunch_ddr_copy.vhd','rtl/rabbitpunch_load_frontend.vhd','sim/fast/diagnostic_load_source.vhd']
args=[str(ghdl),'--synth','--latches','--std=08','-fsynopsys','--out=verilog','-gGBOOL_EXPECT_FAILURE='+str(options.corrupt).lower()]+[str(root/p) for p in sources]+['-e','diagnostic_fast_fixture']
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
    output o_main_write, output [23:0] ou24_main_address,
    output [15:0] ou16_main_mask, output [15:0] ou16_main_data,
    output o_sound_write, output [15:0] ou16_sound_address, output [7:0] ou8_sound_data,
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
    .o_main_write(o_main_write),
    .ou24_main_address(ou24_main_address),
    .ou16_main_mask(ou16_main_mask),
    .ou16_main_data(ou16_main_data),
    .o_sound_write(o_sound_write),
    .ou16_sound_address(ou16_sound_address),
    .ou8_sound_data(ou8_sound_data),
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
paths=[p for p in main_sources if p.endswith(('.v','.sv'))]
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
        if(model.o_capture) std::fprintf(pixels,"%06X\\n",unsigned(model.ou24_rgb));
        if((cycle%500000)==0) {std::printf("cycle=%u bitmap_words=%u\\n",cycle,unsigned(model.ou16_bitmap_words));std::fflush(stdout);}
        if(model.o_complete) {
            FILE* image=std::fopen("loaded_image.bin","wb");if(!image)return 3;
            for(unsigned index=0;index<1081344;index++) {
                unsigned word=model.rootp->'''+fields[0]+'''[index];
                std::fputc(word&255,image);std::fputc((word>>8)&255,image);
            }
            std::fclose(image);std::fclose(main_trace);std::fclose(sound_trace);model.final();std::fclose(pixels);
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
report = dict(accepted=True,set=options.game,frames=options.frames,main_writes=len(actual),sound_writes=len(sound_actual),
    mame_main_prefix=10000,mame_sound_comparison=comparison,pixels=62208,
    nonblack_pixels=sum(int(pixel,16)!=0 for pixel in pixels),image_sha256=sha(out/'image_used.bin'),
    rgb_sha256=hashlib.sha256(rgb).hexdigest(),source_sha256=input_hashes,tool_sha256=tool_hashes,
    scope='Supplemental two-state bounded live real-ROM execution with both CPUs, JT51/JT7759, shared SDRAM and native raster/rendering. Qualified logical on-chip RAM; synthetic system/chip clocks; external chip ROM image preloaded, original 32-byte header downloaded, no CPU/RAM deposits. Ordered main/sound startup prefixes compared to MAME, four audited reset stack-byte positions exposed; capture coordinates, row deadlines and no underflow checked. Unsupported T80 block-I/O flag path traps. Frame RGB is a capture, not a temporally aligned MAME image proof; no game playability, audible audio, physical hardware or full-image loader claim.')
(root / f'docs/reference/fast_game_{case}_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS bounded live game',options.game,options.frames,'frames',report['nonblack_pixels'],'nonblack pixels',flush=True)
