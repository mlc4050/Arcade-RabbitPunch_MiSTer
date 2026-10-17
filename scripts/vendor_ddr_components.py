# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Pin unchanged GPLv3 DDR transport and word-copy logic from the local Psikyo core."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from coretools import core_root, NO_WINDOW


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--donor',type=Path,required=True)
    args=parser.parse_args()
    root=core_root();donor=args.donor
    jobs=[('rtl/memory/ddram_phy.sv','rtl/memory/ddram/ddram_phy.sv'),
          ('rtl/memory/rom_loader.sv','rtl/memory/ddram/rom_loader.sv'),
          ('LICENSE','rtl/memory/ddram/LICENSE'),('README.md','rtl/memory/ddram/UPSTREAM_README.md'),
          ('sim/ddram_phy_tb/tb_ddram_phy.sv','sim/vendor/ddram/tb_ddram_phy.sv'),
          ('sim/ddram_phy_tb/ddram_model.sv','sim/vendor/ddram/ddram_model.sv')]
    def git(*arguments):
        return subprocess.check_output(['git','-C',str(donor),*arguments],text=True,**NO_WINDOW).strip()
    assert not git('status','--porcelain','--',*[source for source,_ in jobs]), 'Selected donor files modified'
    commit=git('rev-parse','HEAD')
    path=root/'docs/reference/vendor_manifest.json';manifest=json.loads(path.read_text())
    targets={target for _,target in jobs}
    manifest['files']=[row for row in manifest['files'] if row['target'] not in targets]
    manifest['donors']['ddrload']=dict(directory=donor.name,commit=commit,selected_files_clean=True)
    for source,target in jobs:
        original=donor/source;copied=root/target
        digest=hashlib.sha256(original.read_bytes()).hexdigest()
        assert not copied.exists() or hashlib.sha256(copied.read_bytes()).hexdigest()==digest
        copied.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(original,copied)
        manifest['files'].append(dict(donor='ddrload',source=source,target=target,sha256=digest))
    path.write_text(json.dumps(manifest,indent=2)+'\n')
    (root/'rtl/memory/ddram/PROVENANCE.md').write_text(f'''# DDR load-time transport

Copied byte-for-byte from Arcade-Psikyo_MiSTer at {commit}; all selected files
are clean. Source paths/hashes are in docs/reference/vendor_manifest.json.
The donor README states GPL v3 and its LICENSE contains GPLv3. Both are retained.
The native files do not add an or-later statement; no broader licence is inferred.
The donor header traces the loading mechanism to srg320/Arcade-PsikyoSH2_MiSTer.
No vendor changes are made. This is a development integration, not a hardware claim.

rom_loader reads eight-byte DDR granules and emits four little-endian 16-bit
words. Its optional Psikyo ADPCM-A swap must be disabled for Rabbit Punch's
already-laid-out image. Native write addresses are 25 bits, sufficient for the
0x210000-byte in-scope image; do not silently widen or truncate a larger image.
DDR request acceptance also requires DDRAM_BUSY low, even when native busy is
low. The descriptive boundary must account for both sources of backpressure.
Native dl_req is held until dl_busy acknowledges acceptance and remains blocked
until dl_busy drops; it is not a ready/valid word stream without an adapter.

The original DDR PHY test/model are retained unchanged under sim/vendor/ddram.
Run them before adaptation. No matching native word-loader test was identified;
a new VHDL behavioral DDR/word-backend baseline must pass before system use.
No physical DDR/HPS, rotator sharing or real-image transfer is proven by copying.
''')
    print(f'Pinned {len(jobs)} unchanged DDR loader files at {commit}')


if __name__=='__main__':
    main()
