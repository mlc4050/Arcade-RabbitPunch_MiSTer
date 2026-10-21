# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Promote byte-identical VHDL only after matching native and formal receipts.

This qualifies neither FPGA timing nor a production game-state service. Old
models/reports are archived without deleting any worktree or ignored artifacts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from coretools import core_root


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chip', choices=('jt51', 'jt7759'), required=True)
    parser.add_argument('--model-dir', type=Path, required=True)
    parser.add_argument('--native-report', type=Path, required=True)
    parser.add_argument('--proof-report', type=Path, required=True)
    args = parser.parse_args()
    root = core_root()
    candidate = (root/args.model_dir/(args.chip+'_state_netlist.vhd')).resolve()
    assert candidate.drive.upper() == 'D:'
    relative = candidate.relative_to(root).as_posix()
    metadata = json.loads(candidate.with_suffix('.json').read_text())
    expected = metadata['generated_sha256']
    assert digest(candidate) == expected
    assert digest(root/'scripts/generate_sound_state_vhdl.py') == metadata['generator_sha256']
    native = json.loads((root/args.native_report).read_text())
    proof = json.loads((root/args.proof_report).read_text())
    assert native['source_sha256'][relative] == expected
    assert proof['accepted'] and proof['generated_sha256'] == expected
    assert proof['state_bits'] == metadata['state_bits']
    assert proof['source_sha256'] == metadata['source_sha256']
    assert proof['generator_sha256'] == metadata['generator_sha256']
    for name, value in native['source_sha256'].items():
        assert digest(root/name) == value, name
    log = root/native['log']
    assert digest(log) == native['log_sha256']
    marker = 'FM_NETLIST_STATE_PASS' if args.chip == 'jt51' else 'ADPCM_NETLIST_STATE_PASS'
    assert native['pass_marker'] == marker and '** Note: '+marker in log.read_text()
    for name, value in metadata['source_sha256'].items():
        assert digest(root/name) == value, name
    destination = root/'rtl/state/generated'/candidate.name
    native_name = 'fm_netlist_state_checks.json' if args.chip == 'jt51' else 'adpcm_netlist_state_checks.json'
    proof_name = args.chip+'_state_normal_proof.json'
    previous = [destination, destination.with_suffix('.json'),
                root/'docs/reference'/native_name, root/'docs/reference'/proof_name]
    old_hash = digest(destination) if destination.exists() else 'no_previous_model'
    archive = root/'debug/fit_archive/sound_before_word_group_promotion'/args.chip/old_hash[:12]
    archive.mkdir(parents=True, exist_ok=True)
    for path in previous:
        if path.exists():
            target = archive/path.name
            if target.exists():
                assert digest(path) == digest(target), 'Archive collision: '+str(target)
            else:
                shutil.copyfile(path, target)
    shutil.copyfile(candidate, destination)
    shutil.copyfile(candidate.with_suffix('.json'), destination.with_suffix('.json'))
    assert digest(destination) == expected
    for report, name, original in [(native, native_name, args.native_report),
                                   (proof, proof_name, args.proof_report)]:
        report.update(canonical_model_path=destination.relative_to(root).as_posix(),
                      canonical_model_sha256=expected, executed_model_path=relative,
                      qualification_report=original.as_posix(),
                      promotion_scope='Canonical VHDL is byte-identical to the tested model. '
                      'Native/formal receipts retain executed paths and exact input hashes. '
                      'This promotion is not FPGA fit or production game-state qualification.')
        (root/'docs/reference'/name).write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('PROMOTED', args.chip, expected, 'native and normal-mode formal receipts matched')


if __name__ == '__main__':
    main()
