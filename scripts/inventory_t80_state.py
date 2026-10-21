# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Inventory a complete T80 implementation without modifying the imported CPU.

The architectural DIR port omits hidden execution, HALT, pending interrupt and
bus wrapper state. This evaluates complete primitive-state access as a possible
alternative to an intrusive NMI monitor. It does not qualify a CPU replacement.
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
    parser.add_argument('--ghdl', type=Path, required=True)
    args = parser.parse_args()
    root = core_root()
    assert root.drive.upper() == 'D:'
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    pinned = {row['target']: row['sha256'] for row in manifest['files']}
    sources = ['rtl/cpu/t80/'+name+'.vhd' for name in
               ('T80_Pack', 'T80_ALU', 'T80_MCode', 'T80_Reg', 'T80', 'T80se')]
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    for name, digest in hashes.items():
        assert pinned[name] == digest, name
    sources += ['rtl/rabbitpunch_t80.vhd']
    hashes[sources[-1]] = hashlib.sha256((root/sources[-1]).read_bytes()).hexdigest()
    out = root/'debug/state_netlist/t80_gates'
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['PATH'] = os.pathsep.join((str(args.yosys.parent),
                                  str(args.yosys.parent.parent/'lib'), env.get('PATH', '')))
    result = subprocess.run([str(args.ghdl), '--synth', '--std=08', '-fsynopsys',
                             '--no-formal', '--out=verilog',
                             *[str(root/name) for name in sources], '-e', 'rabbitpunch_t80'],
                            cwd=out, env=env, capture_output=True, text=True,
                            timeout=120, **NO_WINDOW)
    (out/'ghdl.log').write_text(result.stderr, encoding='utf-8', newline='\n')
    if result.returncode != 0:
        report = dict(accepted=False, stage='GHDL synthesis frontend', source_sha256=hashes,
                      runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      log_sha256=hashlib.sha256((out/'ghdl.log').read_bytes()).hexdigest(),
                      diagnostics=result.stderr,
                      scope='Pristine production T80se inventory rejected before JSON lowering. '
                      'The original operand-width expression and inferred latches are retained. '
                      'No source patch, CPU inventory count, state implementation, equivalence '
                      'or replacement qualification is claimed. Existing fast fixtures use an '
                      'explicitly trapped tool-only unsupported block-I/O path; that restricted '
                      'substitution is not used for this complete-state inventory.')
        (root/'docs/reference/t80_state_inventory_rejected.json').write_text(
            json.dumps(report, indent=2)+'\n', encoding='utf-8')
        raise SystemExit(result.stderr)
    # This Verilog is compiler output, never authored or substituted for imports.
    (out/'generated.v').write_text(result.stdout, encoding='utf-8')
    script = out/'inventory.ys'
    script.write_text('read_verilog generated.v\nhierarchy -check -top rabbitpunch_t80\n'
                      'proc\nflatten\nmemory_map\nopt_clean\ntechmap\nopt_clean\n'
                      'write_json netlist.json\nstat\n', encoding='utf-8')
    result = subprocess.run([str(args.yosys), '-ql', str(out/'yosys.log'), '-s', str(script)],
                            cwd=out, env=env, capture_output=True, text=True,
                            timeout=120, **NO_WINDOW)
    (out/'launcher.log').write_text(result.stdout+result.stderr, encoding='utf-8')
    assert result.returncode == 0, (out/'yosys.log').read_text()[-4000:]
    design = json.loads((out/'netlist.json').read_text())['modules']['rabbitpunch_t80']
    types = Counter(cell['type'] for cell in design['cells'].values())
    sequential = [dict(name=name, type=cell['type'], bits=len(cell['connections'].get('Q', [])))
                  for name, cell in sorted(design['cells'].items())
                  if any(part in cell['type'].lower() for part in ('dff', 'latch', 'mem'))]
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    report = dict(source_sha256=hashes, cell_types=dict(sorted(types.items())),
                  sequential_bits=sum(cell['bits'] for cell in sequential),
                  sequential_cells=sequential,
                  netlist_sha256=hashlib.sha256((out/'netlist.json').read_bytes()).hexdigest(),
                  ghdl=subprocess.check_output([str(args.ghdl), '--version'], text=True,
                                               **NO_WINDOW).splitlines()[0],
                  yosys=subprocess.check_output([str(args.yosys), '-V'], text=True,
                                                env=env, **NO_WINDOW).strip(),
                  scope='Inventory of pristine production T80se and descriptive wrapper '
                  'lowered through GHDL/Yosys; no CPU modification, generated state access, '
                  'equivalence, continuation, FPGA fit or production replacement claimed.')
    (out/'inventory.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(dict(sequential_bits=report['sequential_bits'],
                          cell_types=report['cell_types'])), flush=True)


if __name__ == '__main__':
    main()
