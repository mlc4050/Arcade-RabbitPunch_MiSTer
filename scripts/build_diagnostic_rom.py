# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Generate original ROM-free bring-up software and a private development MRA."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import xml.etree.ElementTree as ET
from build_mras import layout
from coretools import core_root, mame_exe, mame_version, NO_WINDOW
import mra


def program(fill_words=32768):
    if not 1 <= fill_words <= 32768:
        raise ValueError('Bitmap word count must be 1..32768')
    words = [0x000F, 0xFFFC, 0x0000, 0x0008]
    labels, branches = {}, []
    def emit(*values):
        words.extend(values)
    def immediate_write(value, address):
        emit(0x33FC, value, address >> 16, address & 65535)
    def branch(opcode, target):
        location = len(words) * 2
        emit(opcode, 0)
        branches.append((location, target))
    # Native packed bitmap pen values 1,2,3,4 show R/G/B/white one-pixel stripes.
    for pen, color in ((1, 0x7C00), (2, 0x03E0), (3, 0x001F), (4, 0x7FFF)):
        immediate_write(color, 0x0A0400 + pen * 2)
    immediate_write(0, 0x0C000C)   # bitmap palette bank 0
    immediate_write(0, 0x0C0010)   # no sprites
    emit(0x41F9, 0x0004, 0x0000) # LEA bitmap RAM,A0
    emit(0x303C, fill_words - 1)  # MOVE.W loop count,D0
    labels['fill'] = len(words) * 2
    emit(0x30FC, 0x1234)          # MOVE.W #$1234,(A0)+
    branch(0x51C8, 'fill')       # DBRA D0,fill
    emit(0x3239, 0x0002, 0x0000) # MOVE.W ROM check location,D1
    emit(0x0C41, 0xA55A)         # CMPI.W #$A55A,D1
    branch(0x6600, 'failure')    # BNE.W failure
    immediate_write(0xCAFE, 0x0FC000)
    labels['inputs'] = len(words) * 2
    for source, destination in ((0x0C0018, 0x0FC002), (0x0C001A, 0x0FC004), (0x0C001C, 0x0FC006)):
        emit(0x33F9, source >> 16, source & 65535, destination >> 16, destination & 65535)
    immediate_write(0xBEEF, 0x0FC008)
    branch(0x6000, 'inputs')
    labels['failure'] = len(words) * 2
    immediate_write(0x7C00, 0x0A0408) # white stripe becomes red on readback failure
    immediate_write(0xDEAD, 0x0FC000)
    branch(0x6000, 'failure')
    for location, target in branches:
        displacement = labels[target] - (location + 2)
        assert -32768 <= displacement <= 32767
        words[location // 2 + 1] = displacement & 65535
    return words, labels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test-short', action='store_true', help='64-word bitmap fill for bounded CPU validation')
    parser.add_argument('--output-dir', type=Path, help='Private output directory for an isolated simulation fixture')
    args = parser.parse_args()
    root = core_root()
    out = args.output_dir if args.output_dir is not None else root / 'debug/diagnostic' / ('short' if args.test_short else 'full')
    if not out.is_absolute():
        out = root / out
    out.mkdir(parents=True, exist_ok=True)
    sizes = layout()
    words, labels = program(64 if args.test_short else 32768)
    cpu_bytes = struct.pack('>' + 'H' * len(words), *words)
    physical_bytes = cpu_bytes  # ascending stream bytes are 68000 big-endian bytes
    main_rom = bytearray(sizes['ROM_MAINCPU_SIZE'])
    main_rom[:len(physical_bytes)] = physical_bytes
    main_rom[0x20000:0x20002] = bytes.fromhex('A55A')
    image = bytearray(sizes['ROM_IMAGE_SIZE'])
    image[:len(main_rom)] = main_rom
    audio_offset = sizes['ROM_AUDIOCPU_BASE']
    image[audio_offset:audio_offset + 4] = bytes.fromhex('F3C30100') # DI; JP $0001
    (out / 'maincpu.bin').write_bytes(cpu_bytes)
    (out / 'maincpu.hex').write_text(''.join(f'{value[0]:04X}\n' for value in struct.iter_unpack('<H', main_rom)))
    (out / 'image.bin').write_bytes(image)
    version = mame_version()
    if version is None:
        raise SystemExit('Configured MAME version is required for diagnostic MRA metadata')
    desc = ET.Element('misterromdescription')
    for tag, value in (('name', 'Rabbit Punch hardware diagnostic'), ('setname', 'rpdiag'),
                       ('rbf', 'RabbitPunch'), ('mameversion', version),
                       ('year', '2026'), ('manufacturer', 'RabbitPunch contributors'),
                       ('rotation', 'horizontal'), ('players', '2'),
                       ('about', 'Original ROM-free development diagnostic; hardware output unverified. No game ROMs required.')):
        ET.SubElement(desc, tag).text = value
    rom = ET.SubElement(desc, 'rom', index='0', md5='None')
    ET.SubElement(rom, 'part').text = physical_bytes.hex(' ').upper()
    ET.SubElement(rom, 'part', repeat=hex(0x20000 - len(physical_bytes))).text = '00'
    ET.SubElement(rom, 'part').text = 'A5 5A'
    ET.SubElement(rom, 'part', repeat=hex(audio_offset - 0x20002)).text = '00'
    ET.SubElement(rom, 'part').text = 'F3 C3 01 00'
    ET.SubElement(rom, 'part', repeat=hex(len(image) - audio_offset - 4)).text = '00'
    ET.indent(desc, space='    ')
    path = out / 'RabbitPunch_Diagnostic.mra'
    ET.ElementTree(desc).write(path, encoding='utf-8', xml_declaration=True)
    assembled = mra.build_image(path, [], size=sizes['ROM_IMAGE_SIZE'])
    assert assembled == image
    assert ET.parse(path).getroot().findtext('mameversion') == version
    # The disassembler consumes CPU big-endian bytes, independently of loader order.
    tool = mame_exe().with_name('unidasm.exe')
    listing = subprocess.check_output([str(tool), str(out / 'maincpu.bin'), '-arch', 'm68000'], text=True, **NO_WINDOW)
    (out / 'maincpu.disasm').write_text(listing)
    assert 'dbra' in listing.lower() and 'cmpi.w' in listing.lower()
    report = dict(mameversion=version, bitmap_fill_words=64 if args.test_short else 32768, program_bytes=len(cpu_bytes),
        image_bytes=len(image), image_sha256=hashlib.sha256(image).hexdigest(), labels=labels,
        mra_round_trip=True, mra_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='Original generated 68000/Z80 diagnostic and inline MRA byte assembly; independent 68000 disassembly; no execution or hardware claim')
    (out / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS diagnostic assembly: {len(cpu_bytes)} program bytes, {len(image)} image bytes, inline MRA round trip')
    print(path)


if __name__ == '__main__':
    main()
