# SPDX-License-Identifier: GPL-3.0-or-later
"""Replay all live MAME cheat-read words through the production VHDL engine."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET
from coretools import core_root
from run_baselines import run_case
from rabbitpunch_cheats import CHEATS


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game',choices=('rabiolep','rpunch'),required=True)
    parser.add_argument('--reference-label',required=True)
    parser.add_argument('--label',required=True)
    args = parser.parse_args()
    assert all(value.replace('_','').isalnum() for value in (args.reference_label,args.label))
    root = core_root()
    reference = root/f'debug/cheats/{args.game}_{args.reference_label}'
    metadata = json.loads((reference/'result.json').read_text())
    assert metadata['accepted'] and metadata['mameversion'] == '0289'
    for name,digest in metadata['files'].items():
        assert sha(reference/name) == digest,name
    for row,(_,address,value) in zip(metadata['semantic_counters'],CHEATS,strict=True):
        assert int(row[0],16) == address and int(row[1],16) == value
        assert int(row[2]) > 0 and int(row[3]) > 0
    title = 'Rabio Lepus (Japan)' if args.game == 'rabiolep' else 'Rabbit Punch (US)'
    descriptor = root/'releases/_dev/cheats'/(title+'.mra')
    block = ET.parse(descriptor).getroot().find('cheats')
    assert block.get('size') == '16' and block.get('max') == '8' and len(block) == 6
    codes = [bytes.fromhex(node.text) for node in block]
    for code,(_,address,value) in zip(codes,CHEATS,strict=True):
        assert code == (0x10).to_bytes(4,'big')+address.to_bytes(4,'big')+bytes(4)+value.to_bytes(4,'big')
    name = f'cheats_trace_{args.game}_{args.label}'
    out = root/'debug/baselines'/name
    assert not out.exists()
    out.mkdir(parents=True)
    vectors = []
    for line in (reference/'cheat_reads.txt').read_text().splitlines():
        frame,address,raw,mask,result,active = line.split()
        vectors.append((int(active),int(address,16),int(raw,16),int(result,16)))
    assert {row[0] for row in vectors} == {0,1} and len(vectors) > 1000
    (out/'vectors.txt').write_bytes((''.join(' '.join(map(str,row))+'\n' for row in vectors)).encode())
    (out/'codes.txt').write_bytes((''.join(' '.join(map(str,code))+'\n' for code in codes)).encode())
    sources = ['rtl/rabbitpunch_cheats.vhd','sim/cheats/cheats_trace_replay_tb.vhd']
    hashes = {name:sha(root/name) for name in sources}
    for source in sources:
        target = out/'inputs'/source
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/source,target)
    result = run_case(name,sources,'cheats_trace_replay_tb','5 ms','CHEATS_TRACE_REPLAY_PASS')
    assert hashes == {name:sha(root/name) for name in sources}
    match = re.search(r'CHEATS_TRACE_REPLAY_PASS reads=(\d+)',(out/'result.log').read_text())
    assert match and int(match[1]) == len(vectors)
    report = dict(accepted=True,game=args.game,reads=len(vectors),result=result,source_sha256=hashes,
        mame_reference_sha256=sha(reference/'result.json'),mra_sha256=sha(descriptor),
        semantic_counters=metadata['semantic_counters'],
        files={name:sha(out/name) for name in ('vectors.txt','codes.txt','result.log')},
        scope='Native production VHDL cheat engine matches every complete MAME read-response word during disabled/enabled/disabled phases, using the six actual development MRA codes. Raw input unchanged. MAME controlled life/damage perturbations are retained in the reference; no whole-machine cycle or hardware claim.')
    target = root/f'docs/reference/cheats_trace_{args.game}_{args.label}_checks.json'
    assert not target.exists()
    target.write_bytes((json.dumps(report,indent=2)+'\n').encode())
    print(target)


if __name__ == '__main__':
    main()
