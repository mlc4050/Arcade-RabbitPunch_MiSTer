# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Capture MAME score-block readiness and byte geometry for future persistence."""
import argparse
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
from coretools import core_root, mame_exe, mame_src, mame_version, NO_WINDOW
from mame_capture import mame_cmd, lua_runner_env, check_lua_error
root = core_root()
assert mame_version() == '0289'
manifest = json.loads((root / 'docs/reference/rom_manifest.json').read_text())
assert hashlib.sha256(mame_src().read_bytes()).hexdigest() == manifest['sources']['rpunch.cpp']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mame-checkout', type=Path, default=Path(os.environ.get('MAME_CHECKOUT', root.parent / 'mame')))
args = parser.parse_args()
data = subprocess.run(['git', '-C', str(args.mame_checkout), 'show', 'mame0289:plugins/hiscore/hiscore.dat'],
                      capture_output=True, check=True, **NO_WINDOW).stdout
reference = root / '.local/reference/mame0289/plugins/hiscore/hiscore.dat'
reference.parent.mkdir(parents=True, exist_ok=True)
reference.write_bytes(data)
assert hashlib.sha256(data).hexdigest() == '0b7e8e53ee9366f10c75df7b8b7c57de1ba573a1089cafd0937423843f4a2fc9', 'Pinned release hiscore.dat changed'
reports = []
for game in ('rabiolep', 'rpunch'):
    entry = re.search(rb'(?m)^' + game.encode() + rb':\r?\n(@:maincpu,program,[^\r\n]+)', data)[1].decode()
    _, _, address, length, first, last = entry.split(',')
    address, length, first, last = [int(value, 16) for value in (address, length, first, last)]
    assert address == 0xffe01 and length in (0x77, 0x73) and 0xfc000 <= address < address + length <= 0x100000
    out = root / 'debug/hiscore_reference' / game
    out.mkdir(parents=True, exist_ok=True)
    (out / 'lua_error.txt').unlink(missing_ok=True)
    env = dict(os.environ, **lua_runner_env('hiscore_reference.lua'), CORE_OUT=out.as_posix(),
               HISCORE_ADDRESS=str(address), HISCORE_LENGTH=str(length), HISCORE_FIRST=str(first), HISCORE_LAST=str(last))
    command = mame_cmd(mame_exe(), game, 'hiscore_reference.lua', mame_exe().parent,
        ['-seconds_to_run', '12', '-cfg_directory', str(out / 'cfg'), '-nvram_directory', str(out / 'nvram')])
    with (out / 'mame.log').open('w') as log:
        result = subprocess.run(command, cwd=out, env=env, stdout=log, stderr=log, timeout=120, **NO_WINDOW)
    check_lua_error(out)
    log = (out / 'mame.log').read_text()
    match = re.search(r'HISCORE_REFERENCE_OK frame=(\d+) bytes=(\d+)', log)
    assert result.returncode == 0 and match, log[-1500:]
    initial = (out / 'initial.bin').read_bytes()
    assert len(initial) == length and initial[0] == first and initial[-1] == last
    reports.append(dict(set=game, mame_version='0289', entry=entry, address=address, length=length,
        first=first, last=last, initialized_frame=int(match[1]),
        work_ram_first_word=(address - 0xfc000) >> 1, first_byte_lane='lower',
        last_address=address + length - 1, words_spanned=((address & 1) + length + 1) // 2,
        initial_sha256=hashlib.sha256(initial).hexdigest(),
        data_sha256=hashlib.sha256(data).hexdigest(), driver_sha256=manifest['sources']['rpunch.cpp'],
        source_sha256={name:hashlib.sha256((root / name).read_bytes()).hexdigest() for name in
                       ('scripts/capture_hiscore_reference.py', 'scripts/mame/hiscore_reference.lua')},
        log_sha256=hashlib.sha256((out / 'mame.log').read_bytes()).hexdigest(),
        scope='Read-only live MAME readiness using release-pinned hiscore.dat and score-block byte geometry; private initial bytes, no core persistence implementation or RAM writes'))
    print(f'PASS {game}: {length} score bytes initialized at frame {match[1]}', flush=True)
(root / 'docs/reference/hiscore_reference.json').write_text(json.dumps(reports, indent=2) + '\n')
