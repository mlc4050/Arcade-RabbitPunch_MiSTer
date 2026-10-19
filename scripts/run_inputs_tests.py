# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare pad/key board mapping with live MAME vectors and check raw DIP loading."""
import hashlib
import json
import xml.etree.ElementTree as ET
from coretools import core_root
from run_baselines import run_case
root=core_root()
references=json.loads((root/'docs/reference/input_vectors.json').read_text())
assert {row['set']:row['dips_default'] for row in references}=={'rabiolep':0,'rpunch':0x2000}
assert references[0]['cases']==references[1]['cases']
for path in (root/'releases/_dev').glob('*.mra'):
    tree=ET.parse(path)
    assert tree.find('buttons').get('names').split(',')==['Fire/Punch','Missile','-','-','-','-','Start','Coin','Pause','Service','Test']
out=root/'debug/baselines/inputs'
out.mkdir(parents=True,exist_ok=True)
vectors=out/'input_vectors.hex'
vectors.write_text(''.join(f"{row['joy0']:08X} {row['joy1']:08X} {row['key']:03X} {row['pause']:02X} {row['player1']:02X} {row['player2']:02X} {row['service']:02X}\n" for row in references[0]['cases']))
sources=['rtl/mame_keys.sv','rtl/rabbitpunch_keys.vhd','rtl/rabbitpunch_inputs.vhd','sim/board/inputs_tb.vhd']
result=run_case('inputs',sources,'inputs_tb','1 ms','INPUTS_PASS')
result.update(source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    vectors_sha256=hashlib.sha256(vectors.read_bytes()).hexdigest(),reference_sha256=hashlib.sha256((root/'docs/reference/input_vectors.json').read_bytes()).hexdigest(),
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Pad and inherited MAME-default key decoder mapped to actual live MAME active-high P1/P2/SERVICE vectors for both sets; exact MRA button slots, service/test distinction, reserved controls, event toggles and held-pad/key union; 512 raw DIP byte values, per-set MRA defaults, index/address/strobe filtering; no physical pad, pause latch, native HPS-to-system or game-play proof')
(root/'docs/reference/inputs_checks.json').write_text(json.dumps(result,indent=2)+'\n')
