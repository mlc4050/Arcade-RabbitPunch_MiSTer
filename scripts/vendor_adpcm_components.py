"""Pin an unchanged local JT7759 candidate and its original donor smoke test."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from coretools import core_root, NO_WINDOW


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--donor', type=Path, required=True)
    args = parser.parse_args()
    root, donor = core_root(), args.donor
    selected = 'rtl/jt7759'
    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(donor), *arguments], text=True, **NO_WINDOW).strip()
    assert not git('status', '--porcelain', '--', selected), 'Selected donor files are modified'
    commit = git('rev-parse', 'HEAD')
    jobs = [(f'{selected}/hdl/{name}', f'rtl/sound/jt7759/hdl/{name}') for name in
            ('jt7759.v', 'jt7759_adpcm.v', 'jt7759_ctrl.v', 'jt7759_data.v', 'jt7759_div.v', 'jt7759.qip')]
    jobs += [(f'{selected}/{name}', f'rtl/sound/jt7759/{name}') for name in ('LICENSE', 'README.md')]
    jobs += [(f'{selected}/ver/top/{name}', f'sim/vendor/jt7759/{name}') for name in ('test.v', 'go.sh')]
    path = root/'docs/reference/vendor_manifest.json'
    manifest = json.loads(path.read_text())
    targets = {target for _, target in jobs}
    manifest['files'] = [row for row in manifest['files'] if row['target'] not in targets]
    manifest['donors']['upd7759'] = dict(directory=donor.name, commit=commit, selected_files_clean=True)
    for source, target in jobs:
        original, copied = donor/source, root/target
        digest = hashlib.sha256(original.read_bytes()).hexdigest()
        assert not copied.exists() or hashlib.sha256(copied.read_bytes()).hexdigest() == digest, copied
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, copied)
        manifest['files'].append(dict(donor='upd7759', source=source, target=target, sha256=digest))
    path.write_text(json.dumps(manifest, indent=2)+'\n')
    (root/'rtl/sound/jt7759/PROVENANCE.md').write_text(f'''# JT7759 evaluation copy

Copied unchanged from SNK68 at {commit}; selected rtl/jt7759 files are clean.
Upstream: https://github.com/jotego/jt7759, Jose Tejada Gomez, GPL-3.0-or-later.
The donor does not record its exact upstream revision. LICENSE/README/QIP are
preserved, as are the original top-level test.v/go.sh under sim/vendor/jt7759.
File hashes are in docs/reference/vendor_manifest.json. No chip edits are made.

The README table is not an interface declaration: the native ROM address is
17 bits and PCM is signed 9 bits. Existing vendor header spelling is preserved.
This is an evaluation candidate, not integrated sample audio. Original test.v
launches four sample commands and exits at the fourth launch; it has no waveform
scoreboard and its clock comments do not establish 640 kHz operation. A VHDL
baseline must verify the selected clock-enable and interface contracts separately.

The SystemC2 candidate was not selected: its controller's DONE state holds
forever until reset. This SNK68 version returns to IDLE at sample end; that
static distinction motivates selection but requires a retrigger test.
''')
    print(f'Pinned {len(jobs)} unchanged JT7759 donor/test files at {commit}', flush=True)


if __name__ == '__main__':
    main()
