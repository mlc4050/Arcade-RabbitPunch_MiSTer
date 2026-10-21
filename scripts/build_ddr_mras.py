# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Generate optional DDR-staged development MRAs from verified direct-load MRAs."""
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from coretools import core_root, mame_version, setting, NO_WINDOW
from build_mras import layout
import mra

root = core_root()
reference = json.loads((root / 'docs/reference/mra_checks.json').read_text())
version = mame_version()
phy = root / 'rtl/memory/ddram/ddram_phy.sv'
bits = re.search(r'DDRAM_ADDR\s*=\s*\{4\x27b([01]{4}),', phy.read_text())[1]
base = int(bits, 2) << 28
assert base == 0x30000000
size = layout()['ROM_IMAGE_SIZE']
assert size == 0x210000 and size % 8 == 0
archives = [Path(path) / 'rabiolep.zip' for path in setting('MAME_ROMPATH', '').split(';') if path]
archives = [path for path in archives if path.exists()]
if not archives:
    raise SystemExit('Verified local merged rabiolep.zip is required')
out = root / 'releases/_alternatives/_ddr'
out.mkdir(parents=True, exist_ok=True)
results = []
for row in reference:
    original = root / row['mra']
    doc = ET.parse(original).getroot()
    assert doc.findtext('mameversion') == version == row['mameversion']
    assert doc.findtext('setname') == row['set']
    direct_rom = doc.find("rom[@index='0']")
    assert direct_rom is not None and direct_rom.get('address') is None
    expected = mra.build_image(original, archives, size=size)
    assert hashlib.sha256(expected).hexdigest() == row['sha256']
    candidate = copy.deepcopy(doc)
    candidate.find("rom[@index='0']").set('address', hex(base))
    candidate.find('name').text += ' [DDR load]'
    candidate.find('about').text = 'DDR-staged ROM loading; game ROMs execute from external SDRAM. Savestate controller mapping included.'
    # Only the presentation label, explanatory text and staging address differ.
    comparison = copy.deepcopy(candidate)
    comparison.find("rom[@index='0']").attrib.pop('address')
    for tag in ('name', 'about'):
        comparison.find(tag).text = doc.findtext(tag)
    assert ET.tostring(comparison) == ET.tostring(doc)
    path = out / (original.stem + ' - DDR load.mra')
    ET.indent(candidate, space='    ')
    ET.ElementTree(candidate).write(path, encoding='utf-8', xml_declaration=True)
    actual = mra.build_image(path, archives, size=size)
    assert actual == expected
    assert [(node.tag, node.get('index')) for node in candidate if node.tag in ('rom', 'nvram')] == [
        ('rom', '0'), ('rom', '3'), ('nvram', '4')]
    validation = subprocess.run([sys.executable, str(root / 'scripts/validate_mra.py'), str(path)],
                                capture_output=True, text=True, **NO_WINDOW)
    if validation.returncode:
        raise SystemExit(validation.stdout + validation.stderr)
    print(validation.stdout, end='')
    results.append(dict(set=row['set'], mameversion=version, bytes=len(actual), image_sha256=row['sha256'],
                        source_mra=row['mra'], source_mra_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                        mra=path.relative_to(root).as_posix(), mra_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                        ddr_address=hex(base), ddr_last_byte=hex(base + size - 1),
                        direct_and_ddr_images_identical=True, other_metadata_unchanged=True,
                        load_order=['rom0', 'config3', 'nvram4']))
(root / 'docs/reference/ddr_mra_checks.json').write_text(json.dumps(dict(cases=results,
    loader_source_sha256=hashlib.sha256(phy.read_bytes()).hexdigest(),
    scope='Optional unpublished DDR-load MRAs from the verified direct-load definitions. Actual local merged-ROM assembly is byte-identical, MAME version/validation pass, score/DIP/button metadata and section order retained, staging address derived from loader RTL. No physical HPS/DDR transfer, full-image copier throughput or speed measurement claim.'), indent=2) + '\n')
print('PASS optional DDR-load MRAs: both exact 0x210000-byte images and unchanged metadata')

