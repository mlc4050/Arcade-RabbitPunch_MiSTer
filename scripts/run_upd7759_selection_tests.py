# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Require corrected native/state selection equivalence through silence and PCM."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from coretools import core_root, NO_WINDOW
from run_baselines import run_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    root = core_root()
    original = subprocess.check_output(['git', 'show', 'ea4c83e:rtl/rabbitpunch_upd7759.vhd'], cwd=root, **NO_WINDOW).decode()
    expected = original.replace('rabbitpunch_upd7759 is', 'rabbitpunch_upd7759_playback is')
    expected = expected.replace('of rabbitpunch_upd7759 is', 'of rabbitpunch_upd7759_playback is')
    expected = expected.replace('-- Rabbit Punch standalone player.',
        '-- Qualified native playback composition from ea4c83e; entity name only.\n-- Rabbit Punch standalone player.')
    assert (root/'rtl/rabbitpunch_upd7759_playback.vhd').read_text() == expected.replace('\r\n', '\n')
    metadata = json.loads((root/'rtl/state/generated/jt7759_state_netlist.json').read_text())
    assert metadata['state_bits'] == 189 and metadata['state_words'] == 6
    case = 'upd7759_selection_'+args.label
    assert not (root/'debug/baselines'/case).exists(), 'Preserve previous attempts'
    sources = ['rtl/sound/jt7759/hdl/'+name+'.v' for name in ('jt7759_div', 'jt7759_data', 'jt7759_adpcm')]
    sources += ['rtl/rabbitpunch_upd7759_control.vhd', 'rtl/rabbitpunch_upd7759_playback.vhd',
        'rtl/state/generated/jt7759_state_netlist.vhd', 'rtl/rabbitpunch_upd7759.vhd',
        'sim/state/upd7759_selection_tb.vhd']
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    assert hashes['rtl/state/generated/jt7759_state_netlist.vhd'] == metadata['generated_sha256']
    vendor = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    for name in sources[:3]:
        assert hashes[name] == next(row['sha256'] for row in vendor['files'] if row['target'] == name)
    result = run_case(case, sources, 'upd7759_selection_tb', '1 ms',
        'UPD7759_SELECTION_PASS', wall_timeout=120, verilog_defines=(),
        vlog_options=('+initreg=r+0', '+initmem=r+0'))
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources}
    result.update(source_sha256=hashes, integration_branch='codex/savestates',
        production_source_branch='develop', production_source_commit='ea4c83e',
        state_model_commit='f1a552d', state_model_sha256=metadata['generated_sha256'],
        native_playback_transform='Entity rename and provenance comment only; LF/CRLF normalized for source comparison.',
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Production ADPCM wrapper generic=false and true compared every '
              'clock with the explicit FPGA-zero native power-up contract. '
              'Busy/ROM request/address/PCM match through a2048-enable corrected '
              'silence packet and subsequent nonzero synthetic sample with '
              'throttled ROM; inactive state read is zero. No active restore, '
              'real sound corpus, whole-machine or FPGA/hardware qualification.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
