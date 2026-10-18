# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Cross-check VHDL-owned HQ2x fixtures with a portable two-state fast backend."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from coretools import NO_WINDOW, core_root, setting
from hwlock import require_no_jtag


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full-raster', action='store_true')
    parser.add_argument('--negative-width', action='store_true', help='Require the retained VHDL row assertion to reject width+1')
    parser.add_argument('--reference-root', type=Path, help='Worktree holding the accepted compact ModelSim captures; default current core')
    args = parser.parse_args()
    if args.full_raster and args.negative_width:
        parser.error('Run the compact negative control separately')
    root = core_root()
    require_no_jtag('Fast VHDL-owned CRT/HQ2x comparison')
    tools = root / '.local/tools'
    ghdl = Path(setting('GHDL_EXE', str(tools / 'ghdl-6.0.0/bin/ghdl.exe')))
    suite = Path(setting('OSS_CAD_ROOT', str(tools / 'oss-cad-suite-20261018/oss-cad-suite')))
    compiler = Path(setting('CXX_BIN', str(tools / 'w64devkit-2.10.1/w64devkit/bin')))
    verilator = suite / 'bin/verilator_bin.exe'
    for tool in (ghdl, verilator, compiler / 'g++.exe', compiler / 'make.exe'):
        if not tool.is_file():
            parser.error(f'Missing portable tool: {tool}')
    width, height = (288, 216) if args.full_raster else (64, 4)
    geometry = ((288,432,352,392,216,256,232,240) if args.full_raster else (64,96,80,88,4,10,6,8))
    label = 'negative_width' if args.negative_width else 'full_raster' if args.full_raster else 'compact'
    out = root / 'debug/fast_crt_hq' / label
    out.mkdir(parents=True, exist_ok=True)
    sources = ['scripts/run_crt_hq_fast_tests.py','sim/video/video_options_tb.vhd',
               'sim/video/crt_video_options_tb.vhd','rtl/rabbitpunch_video_options.vhd',
               'rtl/rabbitpunch_crt_adjust.vhd','rtl/video/crt_adjust/crt_adjust.sv',
               'sys/video_mixer.sv','sys/scandoubler.v','sys/hq2x.sv','sys/video_freezer.sv']
    hashes = {name: sha(root / name) for name in sources}
    if args.full_raster:
        for proof_name in ('compact','negative_width'):
            proof = json.loads((root / f'docs/reference/fast_crt_hq_{proof_name}_checks.json').read_text())
            assert proof['accepted'] and proof['source_sha256'] == hashes, 'Qualify this exact fast runner compactly first'
    env = os.environ.copy()
    env['PATH'] = ';'.join((str(compiler), str(suite / 'bin'), str(suite / 'lib'), env['PATH']))
    env['VERILATOR_ROOT'] = (suite / 'share/verilator').as_posix()
    env['CCACHE_DISABLE'] = '1'
    env['CCACHE_DIR'] = str(root / '.local/tmp/ccache')
    versions = {}
    for name, command in [('ghdl',[str(ghdl),'--version']),('verilator',[str(verilator),'--version']),('cxx',[str(compiler / 'g++.exe'),'--version'])]:
        result = subprocess.run(command,cwd=out,env=env,capture_output=True,text=True,timeout=30,**NO_WINDOW)
        assert result.returncode == 0
        versions[name] = dict(output=result.stdout + result.stderr, executable_sha256=sha(Path(command[0])))
    # This tool-only copy specializes the unused gamma support output. All
    # production instances fix GAMMA=0; bits 20:0 remain constant zero.
    adapter = (root / 'rtl/rabbitpunch_video_options.vhd').read_text()
    assert adapter.count('gamma_bus : inout unsigned(21 downto 0);') == 1
    adapter = adapter.replace('gamma_bus : inout unsigned(21 downto 0);','gamma_bus : in unsigned(21 downto 0);')
    adapter = adapter.replace("su22_gamma(20 downto 0) <= (others => '0');", "su22_gamma <= (others => '0');")
    (out / 'rabbitpunch_video_options.vhd').write_text(adapter)
    mixer = (root / 'sys/video_mixer.sv').read_text()
    start = mixer.index('generate\n\tif(GAMMA && HALF_DEPTH)')
    end = mixer.index('endgenerate', start) + len('endgenerate')
    mixer = mixer[:start] + "\n".join(f"wire [DWIDTH:0] {colour}_in = frz ? 1'd0 : {colour};" for colour in 'RGB') + mixer[end:]
    mixer = ('// MODIFIED 2026-10-18: simulation-only GAMMA=0/HALF_DEPTH=0\n'
             '// Quartus generate-scope normalization; original sys file unchanged.\n' + mixer)
    (out / 'video_mixer_quartus_scope.sv').write_text(mixer)
    cases = []
    for adjusted in ([False] if args.negative_width else (False, True)):
        mode = 'adjusted' if adjusted else 'native'
        name = 'hq_fast_' + mode
        template = 'crt_video_options_tb' if adjusted else 'video_options_tb'
        text = (root / f'sim/video/{template}.vhd').read_text().replace(template,name)
        text = text.replace('use std.env.all;','').replace('use std.textio.all;','')
        text = text.replace('end entity;', '''    port (
        i_clk : in std_logic;
        o_done : out std_logic := '0';
        o_capture : out std_logic := '0';
        ou24_rgb : out unsigned(23 downto 0) := (others => '0')
    );
end entity;''')
        text = text.replace("    signal s_clk : std_logic := '0';\n",'').replace("    s_clk <= not s_clk after 5 ns;\n",'').replace('s_clk','i_clk')
        for colour, old, expression in [('red','31','(sint_x * 13 + sint_y * 71) mod 256'),
                                      ('green','79','((sint_x / 4) * 97 + sint_y * 43) mod 256'),
                                      ('blue','C5','((sint_x + sint_y) mod 2) * 229 + 17')]:
            original = f'su8_{colour} <= x"{old}";'
            assert text.count(original) == 1
            value = f'to_unsigned({expression}, 8)'
            if not adjusted:
                value += " when s_hb = '0' and s_vb = '0' else (others => '0')"
            text = text.replace(original, f'su8_{colour} <= {value};')
        if adjusted:
            text = text.replace("    s_initialize <= '0' after 30 ns;", '''    initialize : process(i_clk)
        variable vint_cycles : natural range 0 to 3 := 0;
    begin
        if (rising_edge(i_clk)) then
            if (vint_cycles < 3) then
                vint_cycles := vint_cycles + 1;
            else
                s_initialize <= '0';
            end if;
        end if;
    end process;''')
            text = text[:text.index('    progress : process')] + 'end architecture;\n'
            text = text.replace('        file v_hq_pixels : text open write_mode is "hq_pixels.hex";\n','').replace('        variable v_line : line;\n','')
            original = '                    write(v_line, to_hstring(su8_output_red & su8_output_green & su8_output_blue));\n                    writeline(v_hq_pixels, v_line);'
            assert text.count(original) == 1
            text = text.replace(original, "                    o_capture <= '1';\n                    ou24_rgb <= su8_output_red & su8_output_green & su8_output_blue;")
        else:
            start = text.index('                assert (su8_output_red = x"31"')
            end = text.index('severity failure;',start) + len('severity failure;')
            text = text[:start] + "                o_capture <= '1';\n                ou24_rgb <= su8_output_red & su8_output_green & su8_output_blue;" + text[end:]
        text = text.replace('    monitor : process\n','    monitor : process(i_clk)\n')
        start = text.index('        wait until falling_edge(i_clk);')
        end = text.index('    end process;',start)
        body = text[start:end].replace('        wait until falling_edge(i_clk);', "        o_capture <= '0';").replace('            finish;', "            o_done <= '1';")
        text = text[:start] + '        if (falling_edge(i_clk)) then\n' + ''.join('    ' + line if line.strip() else line for line in body.splitlines(keepends=True)) + '        end if;\n' + text[end:]
        if args.negative_width:
            original = 'vint_expected_width := 2 * GINT_VISIBLE_WIDTH;'
            assert text.count(original) == 1
            text = text.replace(original, 'vint_expected_width := 2 * GINT_VISIBLE_WIDTH + 1;')
        bench = out / (name + '.vhd')
        bench.write_text(text)
        keys = ('VISIBLE_WIDTH','TOTAL_WIDTH','HORIZONTAL_SYNC_START','HORIZONTAL_SYNC_END','VISIBLE_HEIGHT','TOTAL_HEIGHT','VERTICAL_SYNC_START','VERTICAL_SYNC_END')
        export = [str(ghdl),'--synth','--std=08','--out=verilog','-gGINT_MODE=2'] + [f'-gGINT_{key}={value}' for key,value in zip(keys,geometry)]
        export += [str(out / 'rabbitpunch_video_options.vhd')]
        if adjusted:
            export.append(str(root / 'rtl/rabbitpunch_crt_adjust.vhd'))
        export += [str(bench),'-e',name]
        result = subprocess.run(export,cwd=out,env=env,capture_output=True,text=True,timeout=120,**NO_WINDOW)
        (out / (name + '_export.log')).write_text(result.stderr)
        assert result.returncode == 0, result.stderr
        assert '$fatal' in result.stdout, 'Retained VHDL assertions were not exported'
        (out / (name + '.v')).write_text(result.stdout)
        bridge = out / (name + '_bridge.cpp')
        # No game/test expectations live in C++; this is the simulator clock,
        # capture-file transport and clean exit callback for VHDL assertions.
        bridge.write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Generated clock/file bridge. VHDL owns stimulus and assertions.
#include "V''' + name + '''.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file,int line,const char*,const char* message) {
    std::fprintf(stderr,"VHDL_ASSERTION: %s:%d: %s\\n",file,line,message);
    std::exit(1);
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    V''' + name + ''' model;
    FILE* pixels=std::fopen("''' + name + '''_pixels.hex","w");
    if(!pixels) return 3;
    model.i_clk=0;model.eval();
    for(unsigned cycle=0;cycle<4000000;cycle++) {
        Verilated::timeInc(5);model.i_clk=1;model.eval();
        Verilated::timeInc(5);model.i_clk=0;model.eval();
        if(model.o_capture) std::fprintf(pixels,"%06X\\n",unsigned(model.ou24_rgb));
        if(model.o_done) { model.final();std::fclose(pixels);std::printf("BRIDGE_DONE cycles=%u\\n",cycle+1);return 0; }
    }
    std::fclose(pixels);return 2;
}
''')
        build_sources = [(out / (name + '.v')).as_posix(),(out / 'video_mixer_quartus_scope.sv').as_posix()] + [(root / item).as_posix() for item in ('sys/scandoubler.v','sys/hq2x.sv','sys/video_freezer.sv','rtl/video/crt_adjust/crt_adjust.sv')]
        build = [str(verilator),'--cc','--exe',bridge.as_posix(),'--build','-j','1','--assert','-Wno-fatal','-Wno-PROCASSWIRE','--no-timing','--top-module',name,'--Mdir',(out / ('obj_' + name)).as_posix(),'-o','sim.exe','-CFLAGS','-O2 -DVL_USER_FATAL',*build_sources]
        with (out / (name + '_build.log')).open('w') as log:
            built = subprocess.run(build,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=900,**NO_WINDOW)
        assert built.returncode == 0, f'Build failed; see {out / (name + "_build.log")}'
        started = time.monotonic()
        result = subprocess.run([str(out / ('obj_' + name) / 'sim.exe')],cwd=out,env=env,capture_output=True,text=True,timeout=120,**NO_WINDOW)
        elapsed = time.monotonic() - started
        (out / (name + '_run.log')).write_text(result.stdout + result.stderr)
        if args.negative_width:
            assert result.returncode == 1 and 'VHDL_ASSERTION:' in result.stderr and 'assertion failure' in (result.stdout + result.stderr)
            cases.append(dict(case=mode,expected_assertion_observed=True,returncode=result.returncode,run_seconds=elapsed))
            continue
        assert result.returncode == 0 and 'BRIDGE_DONE' in result.stdout, result.stdout + result.stderr
        capture = out / (name + '_pixels.hex')
        pixels = capture.read_text().splitlines()
        assert len(pixels) == 4 * width * height
        assert all(len(p)==6 and all(c in '0123456789ABCDEF' for c in p) for p in pixels)
        if not args.full_raster:
            reference_root = args.reference_root or root
            prior = json.loads((root / 'docs/reference/crt_hq_pattern_checks.json').read_text())['cases'][int(adjusted)]
            reference = reference_root / 'debug/baselines' / ('crt_hq_pattern_' + mode) / ('hq_pixels.hex' if adjusted else 'pixels.hex')
            assert sha(reference) == prior['pixels_sha256']
            assert pixels == reference.read_text().splitlines(), 'Fast model differs from qualified compact capture'
        cases.append(dict(case=mode,pixels=len(pixels),run_seconds=elapsed,pixels_sha256=sha(capture),returncode=result.returncode))
        print(f'PASS {label} {mode}: {len(pixels)} known pixels in {elapsed:.3f} seconds',flush=True)
    if not args.negative_width:
        assert (out / 'hq_fast_native_pixels.hex').read_bytes() == (out / 'hq_fast_adjusted_pixels.hex').read_bytes()
    assert hashes == {name: sha(root / name) for name in sources}
    generated = {path.relative_to(out).as_posix():sha(path) for path in out.iterdir() if path.is_file()}
    report = dict(accepted=True,cases=cases,source_sha256=hashes,generated_sha256=generated,tools=versions,
                  visible=[width,height],output=[2*width,2*height],full_raster=args.full_raster,negative_width=args.negative_width,
                  scope='Two-state Verilator RTL model from generated VHDL fixtures and adapters, fixed-GAMMA-zero export, explicit simulation-only Quartus generate-scope normalization and unchanged original vendor sources. VHDL stimulus/geometry assertions retained; generated C++ transports only clocks/files and clean assertion exit. Compact pixels must match pinned ModelSim/Quartus captures; full raster additionally requires that exact runner compact pass and wrong-width assertion control. No four-state, full fitted-netlist, SDF, absolute-frequency, clipping/live-transition, physical-output or MAME-HQ accuracy claim.')
    (root / f'docs/reference/fast_crt_hq_{label}_checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS fast CRT/HQ2x ' + label,flush=True)


if __name__ == '__main__':
    main()

