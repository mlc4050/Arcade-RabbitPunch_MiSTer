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
parser.add_argument('--pulse-frames', type=int, default=6)
parser.add_argument('--frames', type=int, default=600)
parser.add_argument('--coin-frame', type=int, default=300)
parser.add_argument('--start-frame', type=int, default=310)
a = parser.parse_args()
assert 2 <= a.coin_frame < a.start_frame < a.frames and 2 <= a.pulse_frames <= 60
require_no_jtag('Scripted MAME gameplay reference')
assert mame_version() == '0289'
root = core_root()
out = root/'debug/gameplay_mame'/f'{a.game}_{a.frames}_pulse{a.pulse_frames}'
assert not out.exists(), 'Retain references immutably; choose a fresh frame count'
out.mkdir(parents=True)
source = root/'scripts/mame/capture.lua'
text = source.read_text()
start = text.index('    local coin = field(')
end = text.index('\nend\ncore_subs',start)
text = text[:start] + '\n    local coin = field("Coin 1")\n    local start = field("1 Player Start")\n    local shoot = field("P1 Button 2")\n    local missile = field("P1 Button 1")\n    local up = field("P1 Up")\n    local down = field("P1 Down")\n    local start_frame = tonumber(os.getenv("GAME_START_FRAME"))\n    emu.register_frame_done(guard("inputs", function()\n        local frame = m.screens[":screen"]:frame_number()\n        coin:set_value((frame >= coin_frame and frame < coin_frame+pulse_frames) and 1 or 0)\n        start:set_value((frame >= start_frame and frame < start_frame+pulse_frames) and 1 or 0)\n        shoot:set_value(frame >= start_frame+pulse_frames and 1 or 0)\n        missile:set_value((frame >= start_frame+30 and frame < start_frame+30+pulse_frames) and 1 or 0)\n        local moving = frame >= start_frame+pulse_frames and not (frame >= start_frame+30 and frame < start_frame+30+pulse_frames)\n        up:set_value((moving and math.floor(frame/60)%2 == 0) and 1 or 0)\n        down:set_value((moving and math.floor(frame/60)%2 == 1) and 1 or 0)\n    end))\n' + text[end:]
script = out/'capture_script.lua'
script.write_text(text)
r = regions()
folder,exe = mame_paths()
env = dict(os.environ, **lua_env(r), CORE_SCRIPT=script.as_posix(),CORE_OUT=out.as_posix(),CORE_FRAME=str(a.frames),
    CORE_READ=spec(r['read']),CORE_WTAP=spec(r['wtap']),CORE_COIN=str(a.coin_frame),GAME_START_FRAME=str(a.start_frame),GAME_PULSE_FRAMES=str(a.pulse_frames))
cmd = mame_cmd(exe,a.game,'capture.lua',folder,['-seconds_to_run',str(a.frames//60+10),'-cfg_directory',str(out/'cfg'),'-nvram_directory',str(out/'nvram')])
run = subprocess.run(cmd,cwd=folder,env=env,capture_output=True,text=True,timeout=120,**NO_WINDOW)
(out/'run.log').write_text(run.stdout+run.stderr)
check_lua_error(out)
assert run.returncode == 0 and 'CORE_CAPTURE_OK' in run.stdout, (run.stdout+run.stderr)[-3000:]
manifest=dict(set=a.game,frames=a.frames,coin_frame=a.coin_frame,start_frame=a.start_frame,pulse_frames=a.pulse_frames,mameversion='0289',
    generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    capture_source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()},
    scope='Raw MAME capture with matching input intent. Frame notifier phase differs from the RTL fixture; this alone does not establish temporal CPU or raster alignment.')
(out/'reference.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Captured MAME gameplay reference:',out)
