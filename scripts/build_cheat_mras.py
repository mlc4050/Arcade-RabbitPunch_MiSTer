# SPDX-License-Identifier: GPL-3.0-or-later
"""Create development-only cheat MRAs from the unchanged published descriptors."""
import copy
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from coretools import core_root, setting
from rabbitpunch_cheats import CHEATS, emit_cheats
import mra


def main():
    root = core_root()
    baseline = {row['set']:row for row in json.loads((root/'docs/reference/mra_checks.json').read_text())}
    archives = [Path(folder)/name for folder in setting('MAME_ROMPATH','').split(';')
                for name in ('rabiolep.zip','rpunch.zip') if (Path(folder)/name).exists()]
    assert archives
    out = root/'releases/_dev/cheats'
    assert not out.exists(),'Keep prior generated MRAs'
    reports = []
    for game, title in (('rabiolep','Rabio Lepus (Japan)'),('rpunch','Rabbit Punch (US)')):
        for ddr in (False,True):
            relative = Path('_alternatives/_ddr')/(title+' - DDR load.mra') if ddr else Path(title+'.mra')
            original = root/'releases'/relative
            baseline_xml = ET.parse(original).getroot()
            candidate = copy.deepcopy(baseline_xml)
            assert candidate.findtext('setname') == game
            block = emit_cheats(candidate,game)
            check = copy.deepcopy(candidate)
            check.remove(check.find('cheats'))
            assert ET.tostring(check) == ET.tostring(baseline_xml),'Cheat MRA changed other settings'
            assert len(block) == len(CHEATS) == 6
            path = out/relative
            path.parent.mkdir(parents=True,exist_ok=True)
            ET.indent(candidate,space='    ')
            ET.ElementTree(candidate).write(path,encoding='utf-8',xml_declaration=True)
            data = mra.build_image(path,archives,size=0x210000)
            assert hashlib.sha256(data).hexdigest() == baseline[game]['sha256']
            reports.append(dict(path=path.relative_to(root).as_posix(),source=original.relative_to(root).as_posix(),
                source_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                only_cheat_block_added=True,rom_image_sha256=hashlib.sha256(data).hexdigest(),
                cheat_codes=[bytes.fromhex(node.text).hex() for node in block]))
    target = root/'docs/reference/cheat_mra_checks.json'
    assert not target.exists()
    target.write_bytes((json.dumps(dict(accepted=True,mras=reports,
        scope='Four development-only MRA descriptors retain complete published settings and exact ROM images; six codes fit the eight-slot loader. No cheat gameplay, RBF or hardware claim.'),indent=2)+'\n').encode())
    print('CHEAT_MRAS_PASS four development descriptors; published MRAs unchanged')


if __name__ == '__main__':
    main()
