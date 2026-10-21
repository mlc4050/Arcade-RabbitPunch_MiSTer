# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Bind native/export DQ conformance and a restricted graph audit to one export."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from coretools import core_root, NO_WINDOW


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root = core_root()
    bundle, out = args.bundle.resolve(), args.out.resolve()
    assert bundle.drive.upper() == out.drive.upper() == 'D:'
    target = out/'dq_native_readback_admission.json'
    assert out.is_dir() and not target.exists(), 'Preserve earlier admissions'
    plan = read(out/'plan.json')
    manifest = read(bundle/'manifest.json')
    assert plan['manifest_sha256'] == sha(bundle/'manifest.json')
    proof_path = root/'docs/reference/state_sdram_alias_deep_v3_checks.json'
    proof = read(proof_path)
    assert proof['accepted'] and proof['writes'] == 256 and proof['burst_reads'] == 192
    assert proof['trace_clocks'] == 6186
    for name, expected in proof['source_sha256'].items():
        assert sha(root/name) == expected, name
    assert sha(root/'scripts/run_state_sdram_alias_tests.py') == proof['runner_sha256']
    assert sha(root/proof['native']['log']) == proof['native_log_sha256']
    native_case = root/'debug/baselines'/proof['native']['case']
    exported_case = root/'debug'/proof['native']['case']
    native = (native_case/'alias_trace.txt').read_bytes()
    exported = (exported_case/'alias_trace.txt').read_bytes()
    assert hashlib.sha256(native).hexdigest() == proof['native_trace_sha256']
    assert hashlib.sha256(exported).hexdigest() == proof['exported_trace_sha256']
    assert native.replace(b'\r\n', b'\n') == exported.replace(b'\r\n', b'\n')
    assert hashlib.sha256(native.replace(b'\r\n', b'\n')).hexdigest() == proof['newline_normalized_trace_sha256']
    assert sha(exported_case/'raw.v') == proof['raw_sha256']
    assert sha(exported_case/'normalized.v') == proof['normalized_sha256']
    for stage in ('export', 'verilate', 'build', 'run'):
        assert read(exported_case/(stage+'.json'))['returncode'] == 0

    image_path = root/'docs/reference/state_sdram_image_rabiolep_full_checks.json'
    image = read(image_path)
    assert image['accepted'] and image['checked_bytes'] == 0x210000
    assert image['image_sha256'] == manifest['roms']['rabiolep']['sha256']
    assert sha(root/image['log']) == image['log_sha256']
    common = ('rtl/rabbitpunch_sdram_types.vhd', 'rtl/rabbitpunch_sdram.vhd',
              'rtl/memory/sdram/sdram.sv', 'sim/vendor/sdram/sdram_chip_model_wide.sv')
    for name in common:
        expected = proof['source_sha256'][name]
        assert image['source_sha256'][name] == expected, name
        assert sha(bundle/'inputs'/name) == expected, name
        assert sha(bundle/'export_inputs'/name) == expected, name
    for game, metadata in manifest['roms'].items():
        rom = bundle/'roms'/(game+'.bin')
        assert rom.stat().st_size == image['checked_bytes']
        assert sha(rom) == metadata['sha256']

    audit = read(out/'dq_alias_audit.json')
    assert audit['diagnostic_only'] and not audit['accepted']
    assert audit['source_export_sha256'] == sha(out/'fixture.v')
    assert audit['normalized_export_sha256'] == sha(out/'fixture_dq.v')
    expected_sources = {
        'rtl/rabbitpunch_sdram.vhd', 'rtl/rabbitpunch_roms.vhd',
        'rtl/rabbitpunch_system.vhd', 'rtl/rabbitpunch_platform.vhd',
        'rtl/rabbitpunch_machine.vhd', 'rtl/state/rabbitpunch_state_machine_backend.vhd',
        'rtl/state/rabbitpunch_state_machine.vhd', 'state_machine_restore_eval.vhd',
    }
    assert len(audit['records']) == 8
    assert {row['native_source'] for row in audit['records']} == expected_sources
    for row in audit['records']:
        name = row['native_source']
        source = bundle/name if name.endswith('_eval.vhd') else bundle/'export_inputs'/name
        assert sha(source) == row['native_source_sha256'], name
    leaf_audit = read(exported_case/'alias_audit.json')
    assert len(leaf_audit['records']) == 8
    native_controller = next(row['module'] for row in leaf_audit['records']
                             if row['module'].startswith('rabbitpunch_sdram_'))
    game_controller = next(row['module'] for row in audit['records']
                           if row['native_source'] == 'rtl/rabbitpunch_sdram.vhd')
    assert native_controller == game_controller, 'Controller capture/refresh/init parameters differ'

    # Reapply the narrow association audit, refusing all extra functional DQ
    # readers and any delta beyond its seven native associations/shared net.
    replay = out/'dq_admission_reaudit'
    assert not replay.exists(), 'Preserve the previous structural audit replay'
    replay.mkdir()
    shutil.copyfile(out/'fixture.v', replay/'fixture.v')
    result = subprocess.run([sys.executable, '-B', str(root/'scripts/normalize_state_game_dq.py'),
        '--bundle', str(bundle), '--out', str(replay)], cwd=root,
        capture_output=True, text=True, timeout=30, **NO_WINDOW)
    (replay/'run.log').write_text(result.stdout+'\n'+result.stderr, newline='\n')
    assert result.returncode == 0, result.stderr
    assert sha(replay/'fixture_dq.v') == sha(out/'fixture_dq.v')
    assert read(replay/'dq_alias_audit.json')['records'] == audit['records']
    # Preserve the exact receipt/recorder bytes as well as their hashes. Git's
    # text newline policy must not make historical evidence unrecoverable.
    evidence = replay/'evidence'
    evidence.mkdir()
    for source in (proof_path, image_path, Path(__file__)):
        shutil.copyfile(source, evidence/source.name)
    report = dict(accepted=True, bundle_manifest_sha256=sha(bundle/'manifest.json'),
        normalized_export_sha256=sha(out/'fixture_dq.v'),
        native_export_receipt_sha256=sha(proof_path),
        native_full_image_receipt_sha256=sha(image_path),
        normalized_leaf_trace_sha256=proof['newline_normalized_trace_sha256'],
        native_full_image_bytes=image['checked_bytes'],
        common_source_sha256={name: proof['source_sha256'][name] for name in common},
        dq_alias_audit_sha256=sha(out/'dq_alias_audit.json'),
        audit_replay_sha256=sha(replay/'dq_alias_audit.json'),
        association_auditor_sha256=sha(root/'scripts/normalize_state_game_dq.py'),
        recorder_sha256=sha(Path(__file__)),
        evidence_snapshot_directory=str(evidence.relative_to(out)).replace('\\', '/'),
        scope='SDRAM DQ abstraction admission by bounded native/export conformance '
              'and exact transparent association replay. The same unchanged '
              'controller/adapter/chip and parameters pass6186 initialized '
              'command clocks,256 normal writes and192 three-port readbacks '
              'through seven inout stages; only CRLF/LF and protocol-unused '
              'address/bank operands differ in the observer. Native all-address '
              'readback covers the full Japanese image; the US image shares '
              'that address geometry, without a separate native full-image run. '
              'The game export changes only the seven direct native associations '
              'and shared top wire, with no functional VHDL DQ readers. This '
              'does not admit game event monitors, CPU/state logic, whole-game '
              'continuation, fitted timing, full MiSTer or hardware behavior.')
    target.write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print('ADMITTED frozen SDRAM DQ abstraction; game/integration gates remain separate')


if __name__ == '__main__':
    main()
