# SPDX-License-Identifier: GPL-3.0-or-later
"""Capture live MAME on/off read-override behavior for both production ROM sets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from coretools import core_root, mame_exe, mame_version, NO_WINDOW
from mame_capture import mame_cmd, lua_runner_env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', choices=('rabiolep', 'rpunch'), required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_','').isalnum()
    root = core_root()
    out = root/f'debug/cheats/{args.game}_{args.label}'
    assert not out.exists()
    out.mkdir(parents=True)
    exe = mame_exe()
    folders = {}
    for key in ('cfg','nvram','state','snapshot','diff'):
        folders[key] = out/key
        folders[key].mkdir()
    command = mame_cmd(exe, args.game, 'cheat_reference.lua', exe.parent,
        ['-seconds_to_run','120'] + [item for key,path in folders.items() for item in ('-'+key+'_directory',str(path))])
    env = dict(os.environ, **lua_runner_env('cheat_reference.lua'), CORE_OUT=out.as_posix())
    with (out/'run.log').open('w') as log:
        result = subprocess.run(command, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT,
            timeout=150, **NO_WINDOW)
    text = (out/'run.log').read_text()
    assert result.returncode == 0 and 'CHEAT_REFERENCE_PASS' in text and not (out/'lua_error.txt').exists(),text[-3000:]
    assert mame_version() == '0289'
    semantics = [line.split() for line in (out/'cheat_semantics.txt').read_text().splitlines()]
    assert len(semantics) == 6 and all(int(row[2]) > 0 and int(row[3]) > 0 for row in semantics)
    metadata = dict(accepted=True, game=args.game, frames=6600, mameversion='0289',
        semantic_counters=semantics, controlled_test_ram_perturbation_frame=3000,
        files={path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in out.iterdir() if path.is_file()},
        script_sha256=hashlib.sha256((root/'scripts/mame/cheat_reference.lua').read_bytes()).hexdigest(),
        scope='Two-player MAME game run through combat, read-tap enabled frames800..4999, disabled before/after. Four explicit test-only RAM perturbations at frame3000 exercise both life and damage counters. All six fields have natural CPU reads that change with overrides; probe reads preserve underlying RAM. Not RTL, original-board or hardware qualification.')
    (out/'result.json').write_bytes((json.dumps(metadata,indent=2)+'\n').encode())
    print(args.game, 'CHEAT_REFERENCE_PASS')


if __name__ == '__main__':
    main()
