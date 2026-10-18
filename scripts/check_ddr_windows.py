# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Check configured framework/rotation/ROM DDR reservations from their sources."""
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from coretools import core_root
root = core_root()
sources = ['sys/sys_top.v', 'sys/ascal.vhd', 'rtl/video/rotation/screen_rotate_two.sv',
           'rtl/memory/ddram/ddram_phy.sv', 'rtl/rabbitpunch_layout.vhd', 'RabbitPunch.qsf', 'RabbitPunch_stp.qsf']
text = {name: (root / name).read_text(encoding='utf-8') for name in sources}
for name in ('RabbitPunch.qsf', 'RabbitPunch_stp.qsf'):
    assert not re.search(r'^\s*set_global_assignment\s+-name VERILOG_MACRO\s+"MISTER_SMALL_VBUF=', text[name], re.M)
framework_base = int(re.search(r'\.RAMBASE\(32\x27h([0-9a-fA-F]+)\)', text['sys/sys_top.v'])[1], 16)
framework_slot = int(re.search(r'`else\s*\.RAMSIZE\(32\x27h([0-9a-fA-F]+)\)', text['sys/sys_top.v'])[1], 16)
assert 'base+(size(30 DOWNTO 0) & \'0\')' in text['sys/ascal.vhd']
rotation_bits = re.search(r'parameter MEM_BASE\s*=\s*7\x27b([01]{7})', text['rtl/video/rotation/screen_rotate_two.sv'])[1]
assert "{MEM_BASE,o_fb,23'd0}" in text['rtl/video/rotation/screen_rotate_two.sv']
rotation_base = int(rotation_bits, 2) << 25
loader_bits = re.search(r'DDRAM_ADDR\s*=\s*\{4\x27b([01]{4}),', text['rtl/memory/ddram/ddram_phy.sv'])[1]
loader_base = int(loader_bits, 2) << 28
image_bytes = int(re.search(r'CINT_ROM_IMAGE_SIZE\s*:\s*natural\s*:=\s*16#([0-9a-fA-F]+)#', text['rtl/rabbitpunch_layout.vhd'])[1], 16)
windows = [dict(name='framework scaler', base=framework_base, size=3 * framework_slot),
           dict(name='optional rotation', base=rotation_base, size=3 * (1 << 23)),
           dict(name='ROM image', base=loader_base, size=image_bytes)]
for number, first in enumerate(windows):
    for second in windows[number + 1:]:
        assert first['base'] + first['size'] <= second['base'] or second['base'] + second['size'] <= first['base'], (first, second)
    first['last_byte'] = first['base'] + first['size'] - 1
    for key in ('base', 'size', 'last_byte'):
        first[key + '_hex'] = hex(first[key])
stride = ((216 + 3) // 4) * 16
assert stride * 288 <= 1 << 23
mras = []
for path in sorted((root / 'releases').rglob('*.mra')):
    rom = ET.parse(path).getroot().find("rom[@index='0']")
    if rom is not None:
        address = rom.get('address')
        assert address is None or int(address, 0) == loader_base
        name = path.relative_to(root).as_posix()
        sources.append(name)
        mras.append(dict(path=name, ddr_address=address))
report = dict(accepted=True, windows=windows, rotated_width=216, rotated_height=288,
              rotated_stride_bytes=stride, rotated_frame_bytes=stride * 288,
              source_sha256={name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}, mras=mras,
              scope='Configured core/framework source reservations, normal 8 MiB scaler slots with MISTER_SMALL_VBUF disabled, unchanged donor three 8 MiB slots, production ROM image extent and optional MRA staging address. Pairwise disjoint; one rotated 32-bit image fits its slot. Not a physical DDR test or an audit of arbitrary host-supplied external framebuffer addresses.')
(root / 'docs/reference/ddr_window_checks.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('DDR windows disjoint:', [(w['name'], w['base_hex'], w['last_byte_hex']) for w in windows])
