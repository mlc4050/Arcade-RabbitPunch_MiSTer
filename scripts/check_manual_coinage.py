# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Observe six physical coin pulses under manual-only US DIP encodings in MAME."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from coretools import core_root, mame_version, NO_WINDOW
from mame_capture import mame_paths, regions, spec, lua_env, mame_cmd, seed_dips, check_lua_error
from hwlock import require_no_jtag

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game',choices=('rpunch','rabiolep'),default='rpunch')
parser.add_argument('--known-control',action='store_true')
parser.add_argument('--cross-slot',action='store_true')
args=parser.parse_args()
root=core_root();require_no_jtag('US manual coinage ROM audit')
assert mame_version()=='0289'
folder,exe=mame_paths();r=regions();reports=[]
for slot in ('A','B'):
    for nibble in ((12,) if args.known_control else (0,1,14)):
        out=root/('debug/manual_coinage' if args.game=='rpunch' else 'debug/manual_coinage_rabiolep')/(f'coin{slot}_{nibble:X}' + ('_cross' if args.cross_slot else ''))
        assert not out.exists(), 'Preserve existing coinage captures'
        out.mkdir(parents=True)
        cfg=seed_dips(exe,folder,args.game,[f'Coin {slot}=1 Coin/1 Credit'],out)
        mask=15 if slot=='A' else 240
        value=nibble if slot=='A' else nibble<<4
        config=cfg/(args.game+'.cfg');doc=ET.parse(config)
        ports=[p for p in doc.findall('.//port') if p.get('type')=='DIPSWITCH' and int(p.get('mask'))==mask]
        assert len(ports)==1
        ports[0].set('value',str(value));doc.write(config,encoding='utf-8',xml_declaration=True)
        (out/'poweron.cfg').write_bytes(config.read_bytes())
        lua=root/'scripts/mame/manual_coinage.lua'
        env=dict(os.environ,**lua_env(r),CORE_SCRIPT=lua.as_posix(),CORE_OUT=out.as_posix(),CORE_FRAME='1260',
            CORE_READ=spec(r['read']),CORE_WTAP=spec(r['wtap']),CORE_COIN='900',
            COIN_FIELD='Coin 1' if (slot=='A') != args.cross_slot else 'Coin 2',COIN_RAW=str(value),COIN_MASK=str(mask))
        cmd=mame_cmd(exe,args.game,'manual_coinage.lua',folder,['-seconds_to_run','30','-cfg_directory',cfg.as_posix(),'-nvram_directory',str(out/'nvram')])
        run=subprocess.run(cmd,cwd=folder,env=env,capture_output=True,text=True,timeout=120,**NO_WINDOW)
        log=run.stdout+run.stderr;(out/'run.log').write_text(log)
        check_lua_error(out)
        assert not (out/'ERROR.txt').exists(), (out/'ERROR.txt').read_text()[:1000] if (out/'ERROR.txt').exists() else ''
        assert run.returncode==0 and 'CORE_CAPTURE_OK' in log and 'CORE_CAPTURE_ERROR' not in log,log[-1000:]
        rows=[list(map(int,line.split())) for line in (out/'inputs.txt').read_text().splitlines()]
        coinmask=16 if (slot=='A') != args.cross_slot else 8
        assert sum(bool(row[2]&coinmask) for row in rows)==36
        assert all((row[3]&mask)==value for row in rows)
        states=[(out/f'coin_{index}.bin').read_bytes() for index in range(1,7)]
        expected={0:[1,2,3,4,5,6],1:[1,3,4,6,7,9],14:[0,0,0,1,1,1],12:[0,1,1,2,2,3]}[nibble]
        candidates=[hex(0xfc000+offset) for offset in range(16384) if [state[offset] for state in states]==expected]
        reports.append(dict(slot=slot,nibble=nibble,cross_slot=args.cross_slot,expected_credit_history=expected,
            matching_ram_byte_candidates=candidates,actual_port_coin_frames=36,poweron_raw_dip_verified=True,
            files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}))
        print('MAME coin',slot,hex(nibble),'candidate credit bytes:',candidates,flush=True)
result=dict(mameversion='0289',game=args.game,cases=reports,
    source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ('scripts/check_manual_coinage.py','scripts/mame/manual_coinage.lua')},
    scope='Six real input-port coin pulses per slot/encoding; raw DIP checked from power-on configuration and every recorded frame. Candidate RAM bytes matching manual credit schedules are observations, pending cross-case and screen validation. No live FPGA coin accounting or physical hardware claim.')
report_name='manual_coinage_cross_control.json' if args.cross_slot and args.known_control else ('manual_coinage_cross_observations.json' if args.cross_slot else ('manual_coinage_known_control.json' if args.known_control else 'manual_coinage_observations.json'))
if args.game=='rabiolep': report_name='rabiolep_'+report_name
(root/'docs/reference'/report_name).write_text(json.dumps(result,indent=2)+'\n')
