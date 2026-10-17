# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Capture live MAME port values for pad/key input-map vectors in both games."""
import hashlib
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET
from coretools import core_root, mame_exe, mame_src, mame_version, NO_WINDOW
from mame_capture import mame_cmd,lua_runner_env,check_lua_error
root=core_root()
assert mame_version()=='0289'
manifest=json.loads((root/'docs/reference/rom_manifest.json').read_text())
assert hashlib.sha256(mame_src().read_bytes()).hexdigest()==manifest['sources']['rpunch.cpp']
reports=[]
for game in ('rabiolep','rpunch'):
    out=root/'debug/input_vectors'/game
    out.mkdir(parents=True,exist_ok=True)
    (out/'lua_error.txt').unlink(missing_ok=True)
    env=dict(os.environ,**lua_runner_env('input_vectors.lua'),CORE_OUT=out.as_posix())
    command=mame_cmd(mame_exe(),game,'input_vectors.lua',mame_exe().parent,
        ['-seconds_to_run','5','-cfg_directory',str(out/'cfg'),'-nvram_directory',str(out/'nvram')])
    with (out/'mame.log').open('w') as log:
        result=subprocess.run(command,cwd=out,env=env,stdout=log,stderr=log,timeout=90,**NO_WINDOW)
    check_lua_error(out)
    log=(out/'mame.log').read_text()
    match=re.search(r'INPUT_VECTORS_OK cases=(\d+) dips=(\d+)',log)
    assert result.returncode==0 and match,log[-1500:]
    cases=[]
    for line in (out/'input_vectors.txt').read_text().splitlines():
        name,joy0,joy1,key,pause,p1,p2,service=line.split()
        cases.append(dict(name=name,joy0=int(joy0,16),joy1=int(joy1,16),key=int(key,16),pause=int(pause),player1=int(p1,16),player2=int(p2,16),service=int(service,16)))
    mra=next(ET.parse(path) for path in (root/'releases/_dev').glob('*.mra') if ET.parse(path).findtext('setname')==game)
    defaults=mra.find('switches').get('default').split(',')
    expected_default=int(defaults[0],16)|(int(defaults[1],16)<<8)
    assert len(cases)==int(match[1]) and int(match[2])==expected_default
    reports.append(dict(set=game,mame_version='0289',driver_sha256=manifest['sources']['rpunch.cpp'],dips_default=int(match[2]),cases=cases,
        source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ('scripts/mame/input_vectors.lua','scripts/capture_input_vectors.py')},
        trace_sha256=hashlib.sha256((out/'input_vectors.txt').read_bytes()).hexdigest(),log_sha256=hashlib.sha256((out/'mame.log').read_bytes()).hexdigest(),
        scope='Live MAME ioport values after scripted field overrides for both active-high player ports and SERVICE, low eight bits; MRA pad slots and default key codes identify each stimulus; no FPGA or physical controls proof'))
    print(f'PASS {game}: {len(cases)} live input-port vectors',flush=True)
(root/'docs/reference/input_vectors.json').write_text(json.dumps(reports,indent=2)+'\n')
