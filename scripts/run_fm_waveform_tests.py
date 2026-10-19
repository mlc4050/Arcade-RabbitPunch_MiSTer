# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare 256 keyed JT51 PCM samples between native ModelSim and fast export."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
from coretools import core_root, setting, NO_WINDOW
from run_baselines import run_case
from hwlock import require_no_jtag

root=core_root()
require_no_jtag('Keyed FM waveform cross-simulator qualification')
out=root/'debug/fm_waveform_fast'
assert not out.exists(), 'Retain waveform qualification artifacts immutably'
out.mkdir(parents=True)
manifest=json.loads((root/'docs/reference/vendor_manifest.json').read_text())
vendor=[row for row in manifest['files'] if row['target'].startswith(('rtl/sound/jt51/','sim/vendor/jt51/')) and row['target'].endswith('.v')]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
for row in vendor:
    assert sha(root/row['target'])==row['sha256'],row['target']
sources=[row['target'] for row in vendor]+['rtl/rabbitpunch_clock_enables.vhd','rtl/rabbitpunch_ym2151.vhd','sim/sound/fm_waveform_fixture.vhd']
inputs=sources+['sim/sound/fm_waveform_tb.vhd','scripts/run_fm_waveform_tests.py','scripts/run_baselines.py']
before={name:sha(root/name) for name in inputs}
native=run_case('fm_waveform_native',sources+['sim/sound/fm_waveform_tb.vhd'],'fm_waveform_tb','30 ms','FM_WAVEFORM_PASS',wall_timeout=1800)
native_pcm=root/'debug/baselines/fm_waveform_native/pcm.txt'
expected=native_pcm.read_text().splitlines()
assert len(expected)==256
ghdl=Path(setting('GHDL_EXE'))
suite=Path(setting('OSS_CAD_ROOT'))
dev=Path(setting('CXX_BIN'))
tools={'ghdl':ghdl,'verilator':suite/'bin/verilator_bin.exe','cxx':dev/'g++.exe'}
tool_hashes={name:sha(path) for name,path in tools.items()}
env=os.environ.copy()
env['PATH']=';'.join((str(dev),str(suite/'bin'),str(suite/'lib'),env['PATH']))
env['VERILATOR_ROOT']=(suite/'share/verilator').as_posix()
env['CCACHE_DISABLE']='1'
env['CCACHE_DIR']=str(root/'.local/tmp/ccache')
args=[str(ghdl),'--synth','--std=08','--out=verilog']+[str(root/p) for p in sources if p.endswith('.vhd')]+['-e','fm_waveform_fixture']
r=subprocess.run(args,cwd=out,capture_output=True,text=True,timeout=120,**NO_WINDOW)
(out/'export.log').write_text(r.stderr)
(out/'fm_waveform_fixture.v').write_text(r.stdout)
assert r.returncode==0,r.stderr[-3000:]
bridge=out/'clock_transport.cpp'
bridge.write_text('''// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// Clock and sample-file transport only; VHDL owns tone stimulus and assertions.
#include "Vfm_waveform_fixture.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
double sc_time_stamp(){return 0.0;}
void vl_fatal(const char* file,int line,const char*,const char* message) {
    std::fprintf(stderr,"VHDL_ASSERTION: %s:%d: %s\\n",file,line,message);std::exit(1);
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Vfm_waveform_fixture model;
    FILE* samples=std::fopen("pcm.txt","w");if(!samples)return 3;
    model.i_clk=0;model.eval();
    for(unsigned cycle=0;cycle<1400000;cycle++) {
        model.i_clk=1;model.eval();
        Verilated::timeInc(10714);model.i_clk=0;model.eval();
        if(model.o_sample) std::fprintf(samples,"%04X %04X %04X %04X\\n",unsigned(model.ou16_left),unsigned(model.ou16_right),unsigned(model.ou16_full_left),unsigned(model.ou16_full_right));
        if(model.o_complete){std::fclose(samples);model.final();std::printf("FM_FAST_COMPLETE clocks=%u\\n",cycle+1);return 0;}
        Verilated::timeInc(10714);
    }
    std::fclose(samples);return 2;
}
''')
obj=out/'obj'
args=[str(suite/'bin/verilator_bin.exe'),'--cc','--exe',bridge.as_posix(),'--assert','--no-assert-case','-Wno-fatal','--no-timing','--timescale','1ps/1ps','--top-module','fm_waveform_fixture','--Mdir',obj.as_posix(),'-o','sim.exe','-CFLAGS','-O2 -DVL_USER_FATAL',(out/'fm_waveform_fixture.v').as_posix()]+[(root/row['target']).as_posix() for row in vendor]
with (out/'verilate.log').open('w') as log:
    r=subprocess.run(args,cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120,**NO_WINDOW)
assert r.returncode==0,(out/'verilate.log').read_text()[-3000:]
with (out/'build.log').open('w') as log:
    r=subprocess.run([str(dev/'make.exe'),'-C',obj.as_posix(),'-f','Vfm_waveform_fixture.mk','-j1'],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=300,**NO_WINDOW)
assert r.returncode==0,(out/'build.log').read_text()[-3000:]
with (out/'run.log').open('w') as log:
    r=subprocess.run([str(obj/'sim.exe')],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120,**NO_WINDOW)
assert r.returncode==0,(out/'run.log').read_text()[-3000:]
actual=(out/'pcm.txt').read_text().splitlines()
assert actual==expected,'Fast keyed PCM differs from native ModelSim; retain artifacts'
assert before=={name:sha(root/name) for name in inputs},'Waveform inputs changed during test'
report=dict(accepted=True,samples=256,channels=4,nonzero_left=sum(int(row.split()[0],16)!=0 for row in actual),
    native=native,native_log_sha256=sha(root/native['log']),native_pcm_sha256=sha(native_pcm),fast_pcm_sha256=sha(out/'pcm.txt'),
    source_sha256=before,tool_sha256=tool_hashes,
    generated_sha256={p.relative_to(out).as_posix():sha(p) for p in out.iterdir() if p.is_file()},
    scope='Explicitly initialized and keyed channel-zero four-carrier JT51 tone under production fractional enables; unchanged vendor logic and descriptive VHDL wrapper. Native four-state ModelSim versus GHDL/Verilator: all 256 samples in raw stereo and full-resolution stereo must match exactly, be known, symmetric and nonzero. No MAME waveform, game audio, analog gain, resampling or physical audible claim.')
(root/'docs/reference/fm_waveform_cross_tool_checks.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS keyed FM: 256 samples x four PCM outputs exactly match native ModelSim')
