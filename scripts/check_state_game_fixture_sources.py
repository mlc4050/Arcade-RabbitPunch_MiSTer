# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Analyze a frozen game fixture's VHDL interfaces; do not claim elaboration."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from coretools import core_root, modelsim_bin, NO_WINDOW
from hwlock import require_no_jtag


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    require_no_jtag('Frozen game fixture VHDL source analysis')
    root, bundle = core_root(), args.bundle.resolve()
    assert bundle.drive.upper() == 'D:'
    manifest = json.loads((bundle/'manifest.json').read_text())
    assert sha(bundle/'state_machine_restore_eval.vhd') == manifest['fixture_sha256']
    order = json.loads((bundle/'source_order.json').read_text())
    groups = [('state_t80', [bundle/'export_inputs'/name for name in order['state_t80']]),
              ('work', [bundle/'export_inputs'/name for name in order['work'] if name.endswith('.vhd')]
                       + [bundle/'state_machine_restore_eval.vhd'])]
    hashes = {str(path.relative_to(bundle)).replace('\\', '/'): sha(path)
              for _, paths in groups for path in paths}
    case = 'state_game_fixture_sources_'+args.label
    out = root/'debug/baselines'/case
    assert not out.exists(), 'Preserve earlier source-analysis attempts'
    out.mkdir(parents=True)
    ini = out/'modelsim.ini'
    shutil.copyfile(Path(os.environ['MODELSIM']), ini)
    env = dict(os.environ, MODELSIM=str(ini))
    tools = modelsim_bin()
    commands = []
    for library, paths in groups:
        commands += [[str(tools/'vlib.exe'), library],
                     [str(tools/'vmap.exe'), library, str(out/library)]]
        commands += [[str(tools/'vcom.exe'), '-2008', '-work', library, str(path)] for path in paths]
    logs = []
    for command in commands:
        result = subprocess.run(command, cwd=out, env=env, capture_output=True,
                                text=True, timeout=180, **NO_WINDOW)
        logs.append(dict(command=command, returncode=result.returncode,
                         stdout=result.stdout, stderr=result.stderr))
        (out/'commands.json').write_text(json.dumps(logs, indent=2)+'\n', newline='\n')
        assert result.returncode == 0, (result.stdout+result.stderr)[-6000:]
    assert hashes == {name: sha(bundle/name) for name in hashes}
    report = dict(analyzed=True, functional_qualification=False,
        bundle_manifest_sha256=sha(bundle/'manifest.json'), source_sha256=hashes,
        compiler_sha256=sha(tools/'vcom.exe'), commands_sha256=sha(out/'commands.json'),
        recorder_sha256=sha(Path(__file__)),
        scope='VHDL interface/source analysis only, including the frozen passive '
              'observation variant and optional shared presentation composition. '
              'No Verilog elaboration, runtime simulation, native/export admission, '
              'physical timing or hardware qualification.')
    (root/'docs/reference'/(case+'_checks.json')).write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print('ANALYZED frozen game VHDL fixture; no elaboration or runtime claim')


if __name__ == '__main__':
    main()
