# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Audit and restore only native transparent DQ associations in a debug export."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def sha(data):
    return hashlib.sha256(data).hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
bundle, out = args.bundle, args.out
raw_path = out/'fixture.v'
target = out/'fixture_dq.v'
assert not target.exists(), 'Keep prior normalized exports'
raw = raw_path.read_text()
chain = {
    'rabbitpunch_sdram_Brtl_': ('rtl/rabbitpunch_sdram.vhd', 'memory_controller', 'SDRAM_DQ'),
    'rabbitpunch_roms_Brtl_': ('rtl/rabbitpunch_roms.vhd', 'memory_transport', 'iou16_sdram_data'),
    'rabbitpunch_system_Brtl_': ('rtl/rabbitpunch_system.vhd', 'roms', 'iou16_sdram_data'),
    'rabbitpunch_platform_Brtl_': ('rtl/rabbitpunch_platform.vhd', 'system', 'iou16_sdram_data'),
    'rabbitpunch_machine_Brtl_': ('rtl/rabbitpunch_machine.vhd', 'platform', 'iou16_sdram_data'),
    'rabbitpunch_state_machine_backend_Brtl_': ('rtl/state/rabbitpunch_state_machine_backend.vhd', 'machine', 'iou16_sdram_data'),
    'rabbitpunch_state_machine_Brtl_': ('rtl/state/rabbitpunch_state_machine.vhd', 'machine', 'iou16_sdram_data'),
}
records = []
seen = set()


def transform(match):
    text = match[0]
    name = re.search(r'^module\s+(\w+)', text)[1]
    original = text
    matches = [prefix for prefix in chain if name.startswith(prefix)]
    if matches:
        assert len(matches) == 1
        prefix = matches[0]
        assert prefix not in seen
        seen.add(prefix)
        source, child, pin = chain[prefix]
        native = (bundle/'export_inputs'/source).read_text()
        assert re.search(r'iou16_sdram_data\s*:\s*inout unsigned\(15 downto 0\)', native)
        assert native.count(pin+' => iou16_sdram_data') == 1
        assert re.search(r'inout\s+\[15:0\]\s+iou16_sdram_data\b', text)
        alias = '\\'+child+'.'+pin
        declaration = '  wire [15:0] '+alias+' ;\n'
        assert text.count(declaration) == 1
        port_lines = re.findall(r'^  assign ([^\n]+) = ([^\n]+); // \(inout - port\)\n', text, re.M)
        read_lines = re.findall(r'^  assign ([^\n]+) = ([^\n]+); // \(inout - read\)\n', text, re.M)
        assert len(port_lines) == len(read_lines) == 1
        port_alias, child_alias = [token.strip() for token in port_lines[0]]
        read_alias, read_source = [token.strip() for token in read_lines[0]]
        assert child_alias == alias and read_source == 'iou16_sdram_data'
        # These generated aliases have no functional readers in the VHDL
        # pass-through wrappers: declaration/assignment, and declaration/two
        # assignments respectively. Refuse a behavioral DQ consumer.
        assert len(re.findall(re.escape(read_alias)+r'(?=\s)', text)) == 2
        assert len(re.findall(re.escape(port_alias)+r'(?=\s)', text)) == 3
        output_pattern = r'^  assign iou16_sdram_data = '+re.escape(port_alias)+r' ; //\(module output\)\n'
        text, count = re.subn(output_pattern, '', text, flags=re.M)
        assert count == 1
        text, count = re.subn(r'^  assign [^\n]+// \(inout - (?:port|read)\)\n', '', text, flags=re.M)
        assert count == 2
        text = text.replace(declaration, '')
        assert text.count(alias+' ') == 1
        text = text.replace(alias+' ', 'iou16_sdram_data')
        assert '.'+pin+'(iou16_sdram_data)' in text
        records.append(dict(module=name, native_source=source, native_source_sha256=sha((bundle/'export_inputs'/source).read_bytes()),
            direct_native_association=pin+' => iou16_sdram_data',
            original_sha256=sha(original.encode()), normalized_sha256=sha(text.encode())))
        return text
    if name == 'state_machine_restore_eval':
        source = (bundle/'state_machine_restore_eval.vhd').read_text()
        assert source.count('SDRAM_DQ => su16_sdram_data') == 1
        assert source.count('iou16_sdram_data => su16_sdram_data') == 1
        assert source.count('signal su16_sdram_data : unsigned(15 downto 0);') == 1
        first = '  wire [15:0] \\chip.SDRAM_DQ ;\n'
        second = '  wire [15:0] \\machine.iou16_sdram_data ;\n'
        assert text.count(first) == text.count(second) == 1
        assert text.count('.SDRAM_DQ()') == text.count('.iou16_sdram_data()') == 1
        assert len(re.findall(r'\\(?:chip\.SDRAM_DQ|machine\.iou16_sdram_data)(?=\s)', text)) == 2
        text = text.replace(first, '  wire [15:0] state_eval_sdram_data;\n').replace(second, '')
        text = text.replace('.SDRAM_DQ()', '.SDRAM_DQ(state_eval_sdram_data)')
        text = text.replace('.iou16_sdram_data()', '.iou16_sdram_data(state_eval_sdram_data)')
        records.append(dict(module=name, native_source='state_machine_restore_eval.vhd',
            native_source_sha256=sha((bundle/'state_machine_restore_eval.vhd').read_bytes()),
            direct_native_associations=['SDRAM_DQ => su16_sdram_data', 'iou16_sdram_data => su16_sdram_data'],
            original_sha256=sha(original.encode()), normalized_sha256=sha(text.encode())))
        return text
    assert '(inout -' not in text, 'Unexpected inout module: '+name
    return text


fixed = re.sub(r'^module\s+\w+\b.*?^endmodule\b', transform, raw, flags=re.M|re.S)
assert seen == set(chain) and len(records) == 8
assert '(inout -' not in fixed
assert fixed.count('.SDRAM_DQ(iou16_sdram_data)') == 1
assert fixed.count('.SDRAM_DQ(state_eval_sdram_data)') == 1
assert fixed.count('.iou16_sdram_data(state_eval_sdram_data)') == 1
target.write_text(fixed, newline='\n')
(out/'dq_alias_audit.json').write_text(json.dumps(dict(diagnostic_only=True, accepted=False,
    source_export_sha256=sha(raw_path.read_bytes()), normalized_export_sha256=sha(target.read_bytes()),
    records=records, scope='Restore exactly seven native transparent16-bit inout associations and the two top-level shared-bus associations dropped by GHDL. No logic, reset, data, timing or vendor source changes. Native full-machine/event admission remains open; diagnostic build only.'), indent=2)+'\n')
print('AUDITED7 transparent DQ wrappers and shared top wire; diagnostic only')
