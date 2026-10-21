# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Lower pristine sound RTL into JSON and inventory reachable sequential state.

This is a frontend/memory-lowering audit, not a functional or timing proof.
All output and tool scratch stay in the selected D-drive checkout. No vendor
source is modified. Gate lowering is optional to assess a VHDL netlist backend.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import subprocess
from coretools import core_root, NO_WINDOW


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yosys', type=Path, required=True)
    parser.add_argument('--chip', choices=('jt51', 'jt7759'), required=True)
    parser.add_argument('--gates', action='store_true')
    args = parser.parse_args()
    root = core_root()
    assert root.drive.upper() == 'D:', 'Generated state work must stay on D:'
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    rows = [row for row in manifest['files']
            if row['target'].startswith('rtl/sound/'+args.chip+'/hdl/')
            and row['target'].endswith('.v')]
    assert rows, 'Missing pinned sound sources'
    hashes = {}
    for row in rows:
        path = root/row['target']
        hashes[row['target']] = hashlib.sha256(path.read_bytes()).hexdigest()
        assert hashes[row['target']] == row['sha256'], row['target']
    out = root/'debug/state_netlist'/(args.chip+('_gates' if args.gates else '_word'))
    out.mkdir(parents=True, exist_ok=True)
    script = out/'inventory.ys'
    commands = ['read_verilog -sv '+' '.join('"'+(root/name).as_posix()+'"' for name in hashes),
                'hierarchy -check -top '+args.chip, 'proc', 'flatten',
                'memory_map', 'opt_clean']
    if args.gates:
        commands += ['techmap', 'opt_clean']
    commands += ['write_json "'+(out/'netlist.json').as_posix()+'"', 'stat']
    script.write_text('\n'.join(commands)+'\n', encoding='utf-8')
    env = os.environ.copy()
    env['PATH'] = os.pathsep.join((str(args.yosys.parent),
                                  str(args.yosys.parent.parent/'lib'), env.get('PATH', '')))
    version = subprocess.check_output([str(args.yosys), '-V'], env=env,
                                      text=True, **NO_WINDOW).strip()
    result = subprocess.run([str(args.yosys), '-ql', str(out/'yosys.log'), '-s', str(script)],
                            env=env, cwd=out, capture_output=True, text=True,
                            timeout=120, **NO_WINDOW)
    (out/'launcher.log').write_text(result.stdout+result.stderr, encoding='utf-8')
    assert result.returncode == 0, (out/'yosys.log').read_text()[-4000:]
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in hashes}
    design = json.loads((out/'netlist.json').read_text())['modules'][args.chip]
    types = Counter(cell['type'] for cell in design['cells'].values())
    sequential = []
    for name, cell in sorted(design['cells'].items()):
        if any(part in cell['type'].lower() for part in ('dff', 'latch', 'mem')):
            sequential.append(dict(name=name, type=cell['type'],
                                   bits=len(cell['connections'].get('Q', [])),
                                   parameters=cell['parameters'],
                                   source=cell.get('attributes', {}).get('src')))
    report = dict(chip=args.chip, gates=args.gates, yosys=version,
                  source_sha256=hashes, cell_types=dict(sorted(types.items())),
                  sequential_bits=sum(cell['bits'] for cell in sequential),
                  sequential_cells=sequential,
                  netlist_sha256=hashlib.sha256((out/'netlist.json').read_bytes()).hexdigest(),
                  log_sha256=hashlib.sha256((out/'yosys.log').read_bytes()).hexdigest(),
                  scope='Pristine production synthesis configuration, no SIMULATION '
                  'initialization or diagnostic blocks. Process/flatten/memory lowering '
                  'only; optional generic gate mapping, no ABC or FPGA build. Reachable '
                  'state inventory only, not normal-mode equivalence, complete freeze, '
                  'state restore, synthesis timing or chip qualification.')
    (out/'inventory.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(dict(chip=args.chip, sequential_bits=report['sequential_bits'],
                          cell_types=report['cell_types'], output=out.as_posix())), flush=True)


if __name__ == '__main__':
    main()
