# SPDX-License-Identifier: GPL-3.0-or-later
"""The six requested work-RAM read overrides, in MiSTer's 16-byte format."""
import xml.etree.ElementTree as ET

MAX_CODES = 8
CHEATS = (
    ('P1 Infinite Missiles', 0xFC269, 0x90),
    ('P1 Infinite Lives', 0xFC3D9, 0x03),
    ('P1 Infinite Energy/Shield', 0xFC3D8, 0x00),
    ('P2 Infinite Missiles', 0xFC2A9, 0x90),
    ('P2 Infinite Lives', 0xFC3F9, 0x03),
    ('P2 Infinite Energy/Shield', 0xFC3F8, 0x00),
)


def emit_cheats(parent, game):
    assert game in ('rabiolep', 'rpunch')
    assert parent.find('cheats') is None
    block = ET.SubElement(parent, 'cheats', size='16', max=str(MAX_CODES))
    for name, address, value in CHEATS:
        code = (0x10).to_bytes(4, 'big') + address.to_bytes(4, 'big') + bytes(4) + value.to_bytes(4, 'big')
        ET.SubElement(block, 'cheat', name=name).text = code.hex(' ').upper()
    return block
