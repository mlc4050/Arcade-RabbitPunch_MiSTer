"""Verify full-width CRT source-pixel order including first/last visible rows."""
import hashlib,json
from coretools import core_root
from run_baselines import run_case
root=core_root()
sources=['rtl/video/crt_adjust/crt_adjust.sv','rtl/rabbitpunch_crt_adjust.vhd','sim/video/crt_adjust_geometry_tb.vhd']
hashes={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
results=[]
for name,size,pos in [('normal',0,0),('right8',0,8),('left8',0,89),('wider2',2,0),('narrower2',30,0)]:
    result=run_case('crt_adjust_geometry_'+name,sources,'crt_adjust_geometry_tb','2 ms','CRT_ADJUST_GEOMETRY_PASS',
        sim_args=('-gGU5_HORIZONTAL_SIZE='+format(size,'05b'),'-gGU7_HORIZONTAL_POSITION='+format(pos,'07b')),wall_timeout=120)
    assert hashes=={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
    result.update(source_sha256=hashes,horizontal_size_index=size,horizontal_position_index=pos,rows=6,pixels=1728,
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest())
    results.append(result)
report=dict(cases=results,scope='Isolated CRT Adjust with corrected VBlank row tags: 288 visible/432 total pixels at /7 enable, six visible/twelve total rows, normal and +/-8 position, +/-2 size. Every source pixel and first/last visible rows checked after warm-up. No vertical-shift, extreme-size clipping, routed fit or physical CRT proof; disconnected from production.')
(root/'docs/reference/crt_adjust_geometry_checks.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
