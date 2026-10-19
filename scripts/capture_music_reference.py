# SPDX-License-Identifier: GPL-3.0-or-later
"""Record pinned MAME music and compare ordered sound writes to a qualified live run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import wave
from coretools import core_root, mame_version, NO_WINDOW
from hwlock import require_no_jtag
from mame_capture import mame_paths, mame_cmd, regions, spec, lua_env, check_lua_error
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game',choices=('rabiolep','rpunch'),required=True)
args=parser.parse_args()
root=core_root()
require_no_jtag('Pinned MAME music/reference capture')
assert mame_version()=='0289'
source_dir=root/'debug/fit_archive/gameplay_mame_explicit_900_990/captures'/(args.game+'_1800_pulse6_checked_actions1290_explicit_900_990')
reference=json.loads((source_dir/'reference.json').read_text())
assert (reference['frames'],reference['coin_frame'],reference['start_frame'],reference['action_frame'])==(1800,900,990,1290)
out=root/'debug/music_reference'/args.game
assert not out.exists(),'Preserve prior music reference before rerunning'
out.mkdir(parents=True)
script=out/'capture_script.lua'
base=(source_dir/'capture_script.lua').read_bytes()
assert b'local shoot = field("P1 Button 2")' in base,'This run must match the old raw live-fixture action sequence'
addon=(root/'scripts/mame/music_trace.lua').read_bytes()
script.write_bytes(base+b'\n'+addon)
folder,exe=mame_paths()
reg=regions()
env=dict(os.environ,**lua_env(reg),CORE_SCRIPT=script.as_posix(),CORE_OUT=out.as_posix(),CORE_FRAME='1800',
    CORE_READ=spec(reg['read']),CORE_WTAP=spec(reg['wtap']),CORE_COIN='900',GAME_START_FRAME='990',GAME_PULSE_FRAMES='6',GAME_ACTION_FRAME='1290',GAME_FORCE_INPUT_ERROR='0')
command=mame_cmd(exe,args.game,'capture.lua',folder,['-seconds_to_run','40','-cfg_directory',str(out/'cfg'),'-nvram_directory',str(out/'nvram'),'-snapshot_directory',str(out/'snapshots'),'-state_directory',str(out/'states'),'-diff_directory',str(out/'diff'),'-wavwrite',str(out/'mame.wav'),'-samplerate','48000'])
run=subprocess.run(command,cwd=folder,env=env,capture_output=True,text=True,timeout=180,**NO_WINDOW)
(out/'run.log').write_text(run.stdout+run.stderr)
check_lua_error(out)
assert not (out/'ERROR.txt').exists(),(out/'ERROR.txt').read_text() if (out/'ERROR.txt').exists() else ''
assert run.returncode==0 and 'CORE_CAPTURE_OK' in run.stdout and 'CORE_CAPTURE_ERROR' not in run.stdout
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
trace=[]
for line in (out/'music_writes.txt').read_text().splitlines():
    seconds,frame,address,data=line.split()
    trace.append((float(seconds),int(frame),int(address,16),int(data,16)))
assert len(trace)>215
live_root=Path('D:/git/RabbitPunch-video-options-work')
live=live_root/'debug/gameplay_fast'/(args.game+'_1800_pad')
live_report=json.loads((live_root/('docs/reference/gameplay_fast_'+args.game+'_1800_pad_checks.json')).read_text())
assert live_report['accepted'] and sha(live/'rtl_sound_writes.txt')==live_report['rtl_sound_trace_sha256']
rtl=[]
for line in (live/'rtl_sound_writes.txt').open():
    address,mask,data=(int(x,16) for x in line.split())
    if address in (0xf000,0xf001,0xf400,0xf600):rtl.append((address,data))
expected=[(row[2],row[3]) for row in trace]
common=0
for left,right in zip(expected,rtl):
    if left!=right:break
    common+=1
with wave.open(str(out/'mame.wav'),'rb') as wav:
    geometry=dict(channels=wav.getnchannels(),width=wav.getsampwidth(),rate=wav.getframerate(),frames=wav.getnframes())
    pcm=wav.readframes(wav.getnframes())
assert geometry['frames']>1000000 and any(pcm)
report=dict(set=args.game,mame_version='0289',frames=1800,coin_frame=900,start_frame=990,action_frame=1290,
    raw_action_profile='old qualified fixture: hold P1 bit5/button2; pulse bit4/button1',
    mame_peripheral_writes=len(expected),rtl_peripheral_writes=len(rtl),common_ordered_write_prefix=common,
    shorter_stream_is_exact_prefix=common==min(len(expected),len(rtl)),
    first_difference=None if common==min(len(expected),len(rtl)) else dict(index=common,mame=expected[common],rtl=rtl[common],mame_time=trace[common][:2]),
    wav=geometry,files={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()},
    source_sha256={'qualified_capture':hashlib.sha256(base).hexdigest(),'music_trace.lua':hashlib.sha256(addon).hexdigest(),'runner':sha(Path(__file__))},
    scope='Pinned MAME full bounded-schedule peripheral-write ordering and output WAV captured against the already completed live FPGA simulation. Machine-time tap timestamps have scheduler granularity. Matching prefixes are register/command sequence evidence only; no sample-exact waveform, tempo or physical listening equality claim yet.')
(root/('docs/reference/music_reference_'+args.game+'_checks.json')).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ('set','mame_peripheral_writes','rtl_peripheral_writes','common_ordered_write_prefix','shorter_stream_is_exact_prefix','first_difference','wav')}))
