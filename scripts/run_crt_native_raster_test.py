"""Replay the fitted CRT adapter with the exact provisional native raster."""
import hashlib
import json
from pathlib import Path
from coretools import core_root
from run_baselines import run_case

root=core_root()
fit=json.loads((root/'debug/crt_adjust_synth.json').read_text(encoding='utf-8'))
commit=fit['commit']
netlist=root/'debug/netlists'/('crt_adjust_'+commit[:7])/'crt_adjust_check.vo'
assert netlist.is_file()
template=root/'sim/video/crt_adjust_geometry_tb.vhd'
text=template.read_text(encoding='utf-8')
for old,new in (("sint_y >= GINT_TEST_FRAME_LINES - 4 and sint_y < GINT_TEST_FRAME_LINES - 2", "sint_y >= 232 and sint_y < 240"),
                ("sint_vsync_width >= 6037 and sint_vsync_width <= 6059", "sint_vsync_width >= 24181 and sint_vsync_width <= 24203")):
    assert text.count(old)==1,old
    text=text.replace(old,new)
bench=root/'debug/crt_native_raster_tb.vhd'
bench.write_text(text,encoding='utf-8')
sources=[netlist.relative_to(root).as_posix(),bench.relative_to(root).as_posix()]
hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
template_hash=hashlib.sha256(template.read_bytes()).hexdigest()
libraries=[item for name in ('cyclonev_ver','altera_ver','altera_lnsim_ver','lpm_ver','sgate_ver') for item in ('-L',name)]
result=run_case('gate_crt_native_raster',sources,'crt_adjust_geometry_tb','100 ms','CRT_ADJUST_GEOMETRY_PASS',
    sim_args=libraries+['-gGINT_TEST_FRAME_LINES=256','-gGINT_VISIBLE_LINES=216'],wall_timeout=1800)
assert hashes=={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
assert template_hash==hashlib.sha256(template.read_bytes()).hexdigest()
result.update(fit_commit=commit,source_sha256=hashes,template_sha256=template_hash,
    pixels=62208,visible=[288,216],total=[432,256],horizontal_sync=[352,392],vertical_sync=[232,240],
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Synthesized CRT adapter with exact provisional native beam geometry and /7 enable; all source pixels, first/last visible rows and sync periods checked after warm-up. Clock counts are functional; routed timing is checked separately. No setting-change, extreme-size clipping, combined effects or monitor proof; disconnected from production.')
(root/'docs/reference/crt_adjust_native_raster_netlist_checks.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
