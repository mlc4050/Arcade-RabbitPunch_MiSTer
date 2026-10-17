# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare native ADPCM decoded values with tables from pinned MAME 0.289."""
import hashlib
import json
import re
from coretools import core_root
from run_baselines import run_case
root=core_root()
reference=root/'.local/reference/mame0289/src/devices/sound/upd7759.cpp'
assert hashlib.sha256(reference.read_bytes()).hexdigest() == 'd3b1989df8a94a0ab5b5b48bfdefd495f6599415f0a1b78f98151f0d5ef6f99e', 'Pinned MAME 0.289 decoder source changed'
text=reference.read_text()
steps=[int(value) for value in re.findall(r'-?\d+', text.split('static const int upd775x_step[16][16] =',1)[1].split('};',1)[0])]
states=[int(value) for value in re.findall(r'-?\d+', text.split('static const int upd775x_state_table[16] =',1)[1].split('};',1)[0])]
assert len(steps)==256 and len(states)==16
sources=['rtl/sound/jt7759/hdl/jt7759_adpcm.v','sim/sound/adpcm_decode_tb.vhd']
manifest=json.loads((root/'docs/reference/vendor_manifest.json').read_text())
entry=next(row for row in manifest['files'] if row['target']==sources[0])
assert hashlib.sha256((root/sources[0]).read_bytes()).hexdigest()==entry['sha256']
out=root/'debug/baselines/adpcm_decode'
out.mkdir(parents=True,exist_ok=True)
vectors=out/'adpcm_steps.txt'
vectors.write_text(''.join(f'{value}\n' for value in steps+states))
result=run_case('adpcm_decode',sources,'adpcm_decode_tb','1 ms','ADPCM_DECODE_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    mame_version='0.289',mame_source='src/devices/sound/upd7759.cpp',mame_source_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),
    vectors_sha256=hashlib.sha256(vectors.read_bytes()).hexdigest(),
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Unchanged native JT7759 nibble decoder: all 256 state/nibble cases agree with pinned MAME deltas/state transitions while sample remains in nine-bit range; native positive/negative saturation tested separately because MAME update_adpcm does not clamp there; disabled-enable hold and reset; no whole-chip stream timing or resampled game waveform proof')
(root/'docs/reference/adpcm_decode_checks.json').write_text(json.dumps(result,indent=2)+'\n')
