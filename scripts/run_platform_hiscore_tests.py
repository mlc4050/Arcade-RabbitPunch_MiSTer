# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
import hashlib
import json
import xml.etree.ElementTree as ET
from coretools import core_root
from run_baselines import run_case
from run_platform_tests import platform_sources
root=core_root()
out=root/'debug/baselines/platform_hiscore'
out.mkdir(parents=True,exist_ok=True)
reference=json.loads((root/'docs/reference/hiscore_reference.json').read_text())
parts=[]
metadata=[]
metadata_reference=[]
for row in reference:
    initial=(root/'debug/hiscore_reference'/row['set']/'initial.bin').read_bytes()
    assert hashlib.sha256(initial).hexdigest()==row['initial_sha256']
    saved=bytes(value^((index*17+0x5a)&255) for index,value in enumerate(initial))
    parts.extend([initial,saved])
    title='Rabio Lepus (Japan)' if row['set']=='rabiolep' else 'Rabbit Punch (US)'
    mra=ET.parse(root/'releases/_dev'/f'{title}.mra').getroot()
    config=bytes.fromhex(mra.find("rom[@index='3']/part").text)
    assert len(config)==24 and int(mra.find("nvram[@index='4']").get('size'))==row['length']
    assert int.from_bytes(config[16:20],'big')==row['address']
    metadata_reference.append({'set':row['set'],'mra_config_sha256':hashlib.sha256(config).hexdigest(),
        'simulation_start_wait_cycles':30,'simulation_check_wait_cycles':19})
    # Accelerate only the polling waits; retain every descriptor/geometry byte.
    metadata.append((30).to_bytes(4,'big')+(19).to_bytes(2,'big')+config[6:])
(out/'scores.hex').write_text(''.join(f'{value:02x}\n' for part in parts for value in part))
(out/'metadata.hex').write_text(''.join(f'{value:02x}\n' for block in metadata for value in block))
sources=platform_sources()[:-1]+['sim/board/platform_hiscore_tb.vhd']
result=run_case('platform_hiscore',sources,'platform_hiscore_tb','3 ms','PLATFORM_HISCORE_PASS',wall_timeout=300)
result.update(metadata=metadata_reference,metadata_sha256=hashlib.sha256((out/'metadata.hex').read_bytes()).hexdigest(),
    source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
    vectors_sha256=hashlib.sha256((out/'scores.hex').read_bytes()).hexdigest(),
    log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
    scope='Full logical platform and executing fx68k through actual shared SDRAM/chip model, native work/score RAM and both maintenance clients. Both MAME table geometries, standard config3/dump4 restore, CPU-consumed restored score word, external maintenance prefill, changed-score OSD autosave/upload, soft-reset restore and ROM-generation/DIP isolation. HPS commands modeled as file signals, game ROM replaced by a 64-byte diagnostic; no disk persistence or physical timing claim.')
(root/'docs/reference/platform_hiscore_checks.json').write_text(json.dumps(result,indent=2)+'\n')
