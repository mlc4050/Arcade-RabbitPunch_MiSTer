# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise actual CPU cheat reads while state-master RAM access remains raw."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
from coretools import core_root
from run_baselines import run_case
from run_state_board_tests import board_sources


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',required=True)
    args = parser.parse_args()
    assert args.label.replace('_','').isalnum()
    root = core_root()
    name = 'cheats_board_'+args.label
    out = root/'debug/baselines'/name
    assert not out.exists()
    out.mkdir(parents=True)
    for filename in ('microrom.mem','nanorom.mem'):
        target = out/'rtl/cpu/fx68k'/filename
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/'rtl/state/vendor/konamigx/fx68k'/filename,target)
    codes = ET.parse(root/'releases/Rabbit Punch (US).mra').getroot().find('cheats')
    assert len(codes) == 6
    (out/'codes.txt').write_bytes((''.join(' '.join(map(str,bytes.fromhex(node.text)))+'\n' for node in codes)).encode())
    sources = board_sources()[:-1]+['sim/cheats/cheats_board_tb.vhd']
    hashes = {name:sha(root/name) for name in sources}
    for source in sources:
        target = out/'inputs'/source
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/source,target)
    result = run_case(name,sources,'cheats_board_tb','10 ms','CHEATS_BOARD_PASS',
        sim_args=('-suppress','8315','-suppress','8360'),wall_timeout=300)
    assert hashes == {name:sha(root/name) for name in sources}
    target = root/f'docs/reference/cheats_board_{args.label}_checks.json'
    assert not target.exists()
    target.write_bytes((json.dumps(dict(accepted=True,result=result,source_sha256=hashes,
        codes_sha256=sha(out/'codes.txt'),log_sha256=sha(out/'result.log'),
        scope='Actual state-capable CPU and production board memory/owner: mirrored 68000 reads apply all six MRA cheats, raw state reads/writes bypass them, warm CPU reset retains codes and empty reload restores ordinary reads. Synthetic ROM program; no full game, sound, HDMI or hardware claim.'),indent=2)+'\n').encode())
    print(target)


if __name__ == '__main__':
    main()
