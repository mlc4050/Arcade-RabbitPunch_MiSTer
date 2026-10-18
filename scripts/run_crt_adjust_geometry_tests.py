"""Verify full-width CRT source-pixel order including first/last visible rows."""
import argparse,hashlib,json,re
from pathlib import Path
from coretools import core_root
from run_baselines import run_case
parser=argparse.ArgumentParser()
parser.add_argument('--netlist',type=Path,help='Use the current fitted CRT functional netlist instead of implementation RTL')
parser.add_argument('--full-height',action='store_true',help='Check all 216 visible rows in the production 256-line raster')
args=parser.parse_args()
root=core_root()
sources=['rtl/video/crt_adjust/crt_adjust.sv','rtl/rabbitpunch_crt_adjust.vhd','sim/video/crt_adjust_geometry_tb.vhd']
libraries=[]
fit_commit=None
if args.netlist:
    fit=json.loads((root/'debug/crt_adjust_synth.json').read_text(encoding='utf-8'))
    fit_commit=fit['commit']
    expected=(root/'debug/netlists'/('crt_adjust_'+fit_commit[:7])/'crt_adjust_check.vo').resolve()
    assert (root/args.netlist).resolve()==expected and expected.is_file()
    sources=[expected.relative_to(root).as_posix(),sources[-1]]
    libraries=[item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
hashes={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
results=[]
cases=[('normal',0,0,0,12),('right8',0,8,0,12),('left8',0,89,0,12),('wider2',2,0,0,12),('narrower2',30,0,0,12),('production256',0,0,0,256),('down1',0,0,1,256),('up1',0,0,63,256)]
visible_lines=216 if args.full_height else 6
if args.full_height:
    cases=[('full216',0,0,0,256)]
for name,size,pos,shift,lines in cases:
    result=run_case(('gate_' if args.netlist else '')+'crt_adjust_geometry_'+name,sources,'crt_adjust_geometry_tb','100 ms','CRT_ADJUST_GEOMETRY_PASS',
        sim_args=libraries+['-gGU5_HORIZONTAL_SIZE='+format(size,'05b'),'-gGU7_HORIZONTAL_POSITION='+format(pos,'07b'),'-gGU6_VERTICAL_SHIFT='+format(shift,'06b'),'-gGINT_TEST_FRAME_LINES='+str(lines),'-gGINT_VISIBLE_LINES='+str(visible_lines)],wall_timeout=300)
    assert hashes=={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
    result.update(source_sha256=hashes,horizontal_size_index=size,horizontal_position_index=pos,rows=visible_lines,pixels=288*visible_lines,
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest())
    log=(root/result['log']).read_text(encoding='utf-8')
    metrics={key:int(value) for key,value in re.findall(r'(hperiod|hwidth|vperiod|vwidth|vphase)=\s*(\d+)',log)}
    assert len(metrics)==5
    result.update(vertical_shift_index=shift,frame_lines=lines,sync_metrics=metrics)
    results.append(result)
if not args.full_height:
    normal_phase=results[-3]['sync_metrics']['vphase']
    assert (results[-2]['sync_metrics']['vphase']-normal_phase)%774144==3024
    assert (normal_phase-results[-1]['sync_metrics']['vphase'])%774144==3024
report=dict(cases=results,fit_commit=fit_commit,full_height=args.full_height,scope='Isolated unchanged CRT Adjust and VHDL adapter with corrected VBlank tags: 288 visible/432 total pixels at /7 enable. Each listed case records visible and total rows; the DUT uses its production 256-line generic. Exact source-pixel order, row boundaries, sync periods and bounded sync-width quantization are checked after warm-up. Non-full-height suite also checks position, size and exact +/-1-line vertical phase changes. No extreme-size clipping, setting-change or physical CRT proof; disconnected from production.')
stem='crt_adjust_geometry'+('_netlist' if args.netlist else '')+('_full_height' if args.full_height else '')+'_checks.json'
(root/'docs/reference'/stem).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
