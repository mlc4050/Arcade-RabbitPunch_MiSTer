"""Check isolated CRT adapter bypass, all read-enable rates and size gating."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root=core_root()
sources=['rtl/video/crt_adjust/crt_adjust.sv','rtl/rabbitpunch_crt_adjust.vhd','sim/video/crt_adjust_control_tb.vhd']
manifest=json.loads((root/'docs/reference/vendor_manifest.json').read_text(encoding='utf-8'))
entry=next(row for row in manifest['files'] if row['target']==sources[0])
assert hashlib.sha256((root/sources[0]).read_bytes()).hexdigest()==entry['sha256']
hashes={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
result=run_case('crt_adjust_control',sources,'crt_adjust_control_tb','1 ms','CRT_ADJUST_CONTROL_PASS',wall_timeout=120)
assert hashes=={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources}
result.update(source_sha256=hashes,log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Isolated unchanged CRT Adjust with VHDL adapter: every-clock native bypass, 32 signed horizontal-size read-enable densities and size-disable gate. No active-image geometry, row latency, routed implementation or CRT hardware proof; not connected to production.')
(root/'docs/reference/crt_adjust_control_checks.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
