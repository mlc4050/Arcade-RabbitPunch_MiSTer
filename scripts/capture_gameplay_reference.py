# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Capture raw MAME state with the live VHDL fixture's scripted controls."""
import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from coretools import core_root, mame_version, NO_WINDOW
from mame_capture import mame_paths, regions, spec, lua_env, mame_cmd, check_lua_error
from hwlock import require_no_jtag
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game', choices=['rabiolep','rpunch'], required=True)
parser.add_argument('--label', default='')
parser.add_argument('--input-error-control', action='store_true')
parser.add_argument('--action-frame', type=int, default=1290)
parser.add_argument('--pulse-frames', type=int, default=6)
parser.add_argument('--frames', type=int, default=600)
parser.add_argument('--coin-frame', type=int, default=900)
parser.add_argument('--start-frame', type=int, default=990)
a = parser.parse_args()
assert 2 <= a.coin_frame < a.start_frame < a.frames and 2 <= a.pulse_frames <= 60
require_no_jtag('Scripted MAME gameplay reference')
assert mame_version() == '0289'
root = core_root()
out = root/'debug/gameplay_mame'/(f'{a.game}_{a.frames}_pulse{a.pulse_frames}_checked_actions{a.action_frame}' + ('_errorcontrol' if a.input_error_control else '') + ('_'+a.label if a.label else ''))
assert not out.exists(), 'Retain references immutably; choose a fresh frame count'
out.mkdir(parents=True)
source = root/'scripts/mame/gameplay_capture.lua'
script = out/'capture_script.lua'
script.write_bytes(source.read_bytes())
r = regions()
folder,exe = mame_paths()
env = dict(os.environ, **lua_env(r), CORE_SCRIPT=script.as_posix(),CORE_OUT=out.as_posix(),CORE_FRAME=str(a.frames),
    CORE_READ=spec(r['read']),CORE_WTAP=spec(r['wtap']),CORE_COIN=str(a.coin_frame),GAME_START_FRAME=str(a.start_frame),GAME_PULSE_FRAMES=str(a.pulse_frames),GAME_ACTION_FRAME=str(a.action_frame),GAME_FORCE_INPUT_ERROR='1' if a.input_error_control else '0')
cmd = mame_cmd(exe,a.game,'capture.lua',folder,['-seconds_to_run',str(a.frames//60+10),'-cfg_directory',str(out/'cfg'),'-nvram_directory',str(out/'nvram')])
run = subprocess.run(cmd,cwd=folder,env=env,capture_output=True,text=True,timeout=120,**NO_WINDOW)
(out/'run.log').write_text(run.stdout+run.stderr)
check_lua_error(out)
if (out/'ERROR.txt').exists():
    raise SystemExit('MAME callback failed: '+(out/'ERROR.txt').read_text()[:1000])
assert 'CORE_CAPTURE_ERROR' not in run.stdout + run.stderr, 'MAME callback error marker'
applied = [list(map(int,line.split())) for line in (out/'inputs.txt').read_text().splitlines()]
assert len(applied) > a.frames-10
assert [row[0] for row in applied if row[1]]==list(range(a.coin_frame,a.coin_frame+a.pulse_frames)), 'Coin pulse frames differ from request'
assert [row[0] for row in applied if row[2]]==list(range(a.start_frame,a.start_frame+a.pulse_frames)), 'Start pulse frames differ from request'
assert sum(row[4] for row in applied)==a.pulse_frames, 'Missile pulse was not applied'
assert sum(bool(row[7] & 0x10) for row in applied)==a.pulse_frames, 'Coin 1 port did not observe pulse'
assert sum(bool(row[7] & 0x20) for row in applied)==a.pulse_frames, 'Start 1 port did not observe pulse'
assert sum(bool(row[8] & 0x10) for row in applied)==a.pulse_frames, 'Missile port did not observe pulse'
assert any(row[8] & 0x20 for row in applied), 'Shoot port remained inactive'
assert run.returncode == 0 and 'CORE_CAPTURE_OK' in run.stdout, (run.stdout+run.stderr)[-3000:]
manifest=dict(set=a.game,frames=a.frames,coin_frame=a.coin_frame,start_frame=a.start_frame,pulse_frames=a.pulse_frames,action_frame=a.action_frame,mameversion='0289',
    actual_requested_coin_frames=[row[0] for row in applied if row[1]],actual_requested_start_frames=[row[0] for row in applied if row[2]],
    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    capture_source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()},
    scope='Raw MAME capture with matching input intent. Frame notifier phase differs from the RTL fixture; this alone does not establish temporal CPU or raster alignment.')
(out/'reference.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Captured MAME gameplay reference:',out)
