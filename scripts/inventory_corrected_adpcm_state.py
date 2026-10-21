# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Inventory the corrected controller with the unchanged imported JT7759 shell.

The VHDL controller is lowered by GHDL. Yosys translates only its port/module
names to the imported controller ABI; no authored Verilog or vendor edits.
Previous state inventories and canonical generated models are never replaced.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


PORT_NAMES = dict(i_reset='rst', i_clk='clk', i_control_enable='cen_ctl',
    i_decode_enable='cen_dec', ou6_divider='divby', i_start_n='stn',
    i_chip_select='cs', i_standalone_mode='mdn', i_data_request_n='drqn',
    o_busy_n='busyn', i_write_n='wrn', iu8_command='din',
    o_decoder_reset='dec_rst', ou4_decoder_nibble='dec_din',
    o_rom_request='rom_cs', ou17_rom_address='rom_addr',
    iu8_rom_data='rom_data', i_rom_valid='rom_ok', o_fifo_flush='flush')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def simplify_unknown_scalar_muxes(text):
    """Z ? scalar : X is X, preserving exact four-state conditional merging."""
    scalars = set(re.findall(r'^\s*(?:wire|reg|input|output)(?:\s+(?:wire|reg))?\s+(\w+)\s*[,;)]', text, re.MULTILINE))
    pattern = re.compile(r"^  assign (\w+) = 1'bZ \? (\w+|1'b[01XZ]) : (\w+|1'b[01XZ]);$", re.MULTILINE)
    matches = list(pattern.finditer(text))
    assert len(matches) == sum("1'bZ ?" in line for line in text.splitlines()), 'Unclassified unknown conditional'
    audit = []
    for match in matches:
        target, first, second = match.groups()
        assert target in scalars, 'Unknown merge target is not proven scalar: ' + target
        assert "1'bX" in (first, second), 'Unknown merge without an X arm'
        assert all(arm.startswith("1'b") or arm in scalars for arm in (first, second)), 'Unknown merge arm is not scalar'
        audit.append(dict(original=match.group(0), replacement="  assign " + target + " = 1'bX;"))
    return pattern.sub(lambda match: "  assign " + match.group(1) + " = 1'bX;", text), audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ghdl', type=Path, required=True)
    parser.add_argument('--yosys', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    assert re.fullmatch(r'[a-z0-9_]+', args.tag)
    require_no_jtag('RabbitPunch corrected ADPCM state frontend')
    root = core_root()
    assert root.drive.upper() == 'D:'
    out = root / 'debug/state_netlist' / args.tag
    assert not out.exists(), 'Use a fresh inventory tag; preserve prior artifacts'
    out.mkdir(parents=True)
    controller = 'rtl/rabbitpunch_upd7759_control.vhd'
    assert sha((root / controller).read_bytes()) == 'b3fabe48db6731c86fda4a54e7d8b7ce212a71fccb83a0b258facf8af1ede454'
    manifest = json.loads((root / 'docs/reference/vendor_manifest.json').read_text())
    imports = ['rtl/sound/jt7759/hdl/' + name + '.v' for name in
               ('jt7759_div', 'jt7759_data', 'jt7759_adpcm', 'jt7759')]
    hashes = {name: sha((root / name).read_bytes()) for name in [controller, *imports]}
    for name in imports:
        assert hashes[name] == next(row['sha256'] for row in manifest['files'] if row['target'] == name)
    env = os.environ.copy()
    env['PATH'] = os.pathsep.join((str(args.yosys.parent), str(args.yosys.parent.parent / 'lib'),
                                  str(args.ghdl.parent), env.get('PATH', '')))

    def command(name, arguments, timeout=120):
        result = subprocess.run(list(map(str, arguments)), cwd=out, env=env, text=True,
                                capture_output=True, timeout=timeout, **NO_WINDOW)
        (out / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        assert result.returncode == 0, (name, result.stderr[-3000:], result.stdout[-3000:])
        return result.stdout

    ghdl_version = command('ghdl_version', [args.ghdl, '--version']).splitlines()[0]
    yosys_version = command('yosys_version', [args.yosys, '-V']).strip()
    raw = command('controller_export', [args.ghdl, '--synth', '--std=08', '--no-formal',
        '--out=verilog', '-gGBOOL_MAME_SILENCE=true', root / controller,
        '-e', 'rabbitpunch_upd7759_control'], timeout=60)
    (out / 'controller_raw.v').write_text(raw, encoding='utf-8', newline='\n')
    lowered, cleanup = simplify_unknown_scalar_muxes(raw)
    (out / 'controller.v').write_text(lowered, encoding='utf-8', newline='\n')
    script = ['read_verilog controller.v', 'cd rabbitpunch_upd7759_control']
    script += ['rename ' + source + ' ' + target for source, target in PORT_NAMES.items()]
    script += ['cd ..', 'rename rabbitpunch_upd7759_control jt7759_ctrl']
    script += ['read_verilog -sv ' + ' '.join('"' + (root / name).as_posix() + '"' for name in imports),
               'hierarchy -check -top jt7759', 'proc', 'flatten', 'memory_map',
               'opt_clean', 'techmap', 'opt_clean', 'write_json netlist.json', 'stat']
    (out / 'inventory.ys').write_text('\n'.join(script) + '\n', encoding='utf-8', newline='\n')
    command('inventory', [args.yosys, '-ql', out / 'yosys.log', '-s', out / 'inventory.ys'])
    assert hashes == {name: sha((root / name).read_bytes()) for name in hashes}
    design = json.loads((out / 'netlist.json').read_text())['modules']['jt7759']
    types = Counter(cell['type'] for cell in design['cells'].values())
    sequential = []
    for name, cell in sorted(design['cells'].items()):
        if any(part in cell['type'].lower() for part in ('dff', 'latch', 'mem')):
            sequential.append(dict(name=name, type=cell['type'], bits=len(cell['connections'].get('Q', [])),
                parameters=cell['parameters'], source=cell.get('attributes', {}).get('src')))
    assert sequential, 'No functional state survived'
    assert not any('latch' in row['type'].lower() for row in sequential), 'Unqualified latch state'
    report = dict(chip='jt7759', gates=True, yosys=yosys_version, ghdl=ghdl_version,
        source_sha256=hashes, cell_types=dict(sorted(types.items())),
        sequential_bits=sum(row['bits'] for row in sequential), sequential_cells=sequential,
        netlist_sha256=sha((out / 'netlist.json').read_bytes()),
        log_sha256=sha((out / 'yosys.log').read_bytes()),
        frontend=dict(raw_sha256=sha((out / 'controller_raw.v').read_bytes()),
            lowered_sha256=sha((out / 'controller.v').read_bytes()),
            scalar_unknown_mux_identities=cleanup, port_renames=PORT_NAMES,
            source_commit='ea4c83e', source_line_endings='LF only'),
        runner_sha256=sha(Path(__file__).read_bytes()),
        scope='Corrected MAME-silence VHDL controller composed with unchanged imported '
              'JT7759 top/divider/FIFO/decoder, with name-only frontend ABI translation '
              'and audited exact four-state scalar unknown-mux identities. Complete '
              'reachable mapped state inventory; no generated-model equivalence, '
              'freeze/restore, FPGA or full-game qualification yet.')
    (out / 'inventory.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(output=out.as_posix(), sequential_bits=report['sequential_bits'],
                          cell_types=report['cell_types'])), flush=True)


if __name__ == '__main__':
    main()
