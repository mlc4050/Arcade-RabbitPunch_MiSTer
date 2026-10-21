# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the native VHDL cheat loader and big-endian read-override regression."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from coretools import core_root
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    root = core_root()
    name = 'cheats_' + args.label
    out = root/'debug/baselines'/name
    assert not out.exists(), 'Keep earlier attempts'
    sources = ['rtl/rabbitpunch_cheats.vhd', 'sim/cheats/cheats_tb.vhd']
    hashes = {}
    for source in sources:
        path = root/source
        hashes[source] = hashlib.sha256(path.read_bytes()).hexdigest()
        target = out/'inputs'/source
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    result = run_case(name, sources, 'cheats_tb', '100 us', 'CHEATS_PASS')
    assert hashes == {source: hashlib.sha256((root/source).read_bytes()).hexdigest() for source in sources}
    report = dict(accepted=True, result=result, source_sha256=hashes,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        transcript_sha256=hashlib.sha256((out/'result.log').read_bytes()).hexdigest(),
        scope='Native VHDL loader/protocol, six game codes, big-endian byte/word/long compare and replace/OR/AND, overlap priority, eight-slot bound, malformed/truncated/empty reload, write bypass and clear. No game, whole-machine or synthesis claim.')
    target = root/f'docs/reference/cheats_engine_{args.label}_checks.json'
    assert not target.exists()
    target.write_bytes((json.dumps(report, indent=2)+'\n').encode())
    print(target)


if __name__ == '__main__':
    main()
