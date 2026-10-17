"""Capture bounded audio-Z80 startup writes; this is not a game-audio oracle."""
import argparse
import hashlib
import json
import os
import subprocess
from collections import Counter
from coretools import core_root, mame_exe, mame_src, mame_version, NO_WINDOW
from mame_capture import mame_cmd, lua_runner_env, check_lua_error


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--writes', type=int, default=4096)
    args = parser.parse_args()
    if args.writes < 1:
        parser.error('--writes must be positive')
    root = core_root()
    assert mame_version() == '0289', 'Pinned MAME 0289 required'
    manifest = json.loads((root/'docs/reference/rom_manifest.json').read_text())
    assert sha(mame_src()) == manifest['sources']['rpunch.cpp'], 'Reference driver changed'
    reports = []
    for game in ('rabiolep', 'rpunch'):
        out = root/'debug/sound_boot'/game
        out.mkdir(parents=True, exist_ok=True)
        (out/'lua_error.txt').unlink(missing_ok=True)
        env = dict(os.environ, **lua_runner_env('sound_boot.lua'),
                   CORE_OUT=out.as_posix(), SOUND_WRITES=str(args.writes))
        command = mame_cmd(mame_exe(), game, 'sound_boot.lua', mame_exe().parent,
            ['-seconds_to_run', '10', '-cfg_directory', str(out/'cfg'),
             '-nvram_directory', str(out/'nvram')])
        with (out/'mame.log').open('w') as log:
            result = subprocess.run(command, cwd=out, env=env, stdout=log, stderr=log,
                                    timeout=90, **NO_WINDOW)
        check_lua_error(out)
        assert result.returncode == 0 and f'SOUND_BOOT_OK writes={args.writes}' in (out/'mame.log').read_text(), out
        writes = [tuple(int(word, 16) for word in line.split())
                  for line in (out/'sound_writes.txt').read_text().splitlines()]
        assert len(writes) == args.writes and all(mask == 255 for _, mask, _ in writes)
        assert all(address in (0xf000, 0xf001, 0xf400, 0xf600) or address >= 0xf800 for address, _, _ in writes)
        counts = Counter('ram' if address >= 0xf800 else f'{address:04x}' for address, _, _ in writes)
        events = (out/'sound_events.txt').read_text().splitlines()
        rom = root/'debug/rom_regions'/game/'audiocpu.bin'
        report = dict(set=game, writes=len(writes), writes_by_target=dict(counts),
            command_events=[line for line in events if line[0] in 'CL'],
            mame_version='0289', driver_sha256=sha(mame_src()), audiocpu_sha256=sha(rom),
            trace=str((out/'sound_writes.txt').relative_to(root)), trace_sha256=sha(out/'sound_writes.txt'),
            events_sha256=sha(out/'sound_events.txt'), reset_state_sha256=sha(out/'reset_state.txt'), log_sha256=sha(out/'mame.log'),
            source_sha256={name: sha(root/name) for name in ('scripts/mame/sound_boot.lua', 'scripts/capture_sound_boot.py')},
            scope='MAME audio-CPU ordered reset writes with real main CPU and sound devices; commands/ack reads indexed by preceding sound-write count; no waveform or FPGA comparison')
        reports.append(report)
        print(f'PASS {game}: {len(writes)} sound startup writes, targets={dict(counts)}, command events={len(report["command_events"])}', flush=True)
    (root/'docs/reference/sound_boot_reference.json').write_text(json.dumps(reports, indent=2)+'\n')


if __name__ == '__main__':
    main()
