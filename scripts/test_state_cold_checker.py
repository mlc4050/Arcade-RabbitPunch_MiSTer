# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Regress cross-boot comparison using completed real-game trace fixtures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import struct

from coretools import core_root, NO_WINDOW


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def write(path, data):
    path.write_text(json.dumps(data, indent=2)+'\n', newline='\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-out', type=Path, required=True)
    parser.add_argument('--reference-bundle', type=Path, required=True)
    parser.add_argument('--game', choices=('rabiolep', 'rpunch'), required=True)
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    root = core_root()
    output = root/'debug'/('state_cold_checker_'+args.label)
    assert not output.exists(), 'Preserve earlier checker regressions'
    output.mkdir()
    source = args.reference_out.resolve()/args.game
    manifest = args.reference_bundle.resolve()/'manifest.json'
    coverage = json.loads((source/'coverage_comparison.json').read_text())
    assert coverage['diagnostic_checks_passed'] and coverage['exact_continuations_equal']
    assert coverage['coverage'][0]['sha256'] != coverage['coverage'][3]['sha256'], 'Distinct checkpoints required'
    seed = source/'slot0_save1.bin'
    checker = root/'scripts/check_state_cold_continuation.py'
    cases = []
    for name, offset, expected in (('same_checkpoint', 0, 0), ('different_checkpoint', 3, 1)):
        case_root = output/name
        case = case_root/args.game
        evidence = case_root/'cold_seed_evidence'
        case.mkdir(parents=True)
        evidence.mkdir()
        # Hard links are read only fixtures here. No source trace is edited.
        for index in range(3):
            os.link(source/f'continuation_{index+offset+1}.txt', case/f'continuation_{index+1}.txt')
        persisted = seed.read_bytes()[:107288]
        loaded = bytearray(0x40000)
        loaded[:len(persisted)] = persisted
        struct.pack_into('<I', loaded, 0, 0xffffffff)
        (case_root/'seed_slot0.bin').write_bytes(loaded)
        (case/'slot0_save1.bin').write_bytes(loaded)
        (evidence/'persisted_slot_file.bin').write_bytes(persisted)
        shutil.copyfile(manifest, evidence/'origin_manifest.json')
        shutil.copyfile(source/'coverage_comparison.json', evidence/'origin_coverage.json')
        (case/'endpoints.txt').write_text('EXTERNAL_SLOT counter=ffffffff bytes=262144\n', newline='\n')
        write(case/'run.json', dict(returncode=0, synthetic_checker_fixture=True))
        simulated = dict(coverage)
        simulated['published_images'] = [dict(coverage['published_images'][0], counter=0xffffffff),
                                         dict(coverage['published_images'][1], counter=0)]
        simulated['coverage'] = coverage['coverage'][offset:offset+3] + coverage['coverage'][3:]
        simulated['release_observations'] = coverage['release_observations'][offset:offset+3] + coverage['release_observations'][3:]
        write(case/'coverage_comparison.json', simulated)
        write(case_root/'cold_seed_admission.json', dict(accepted=True,
            admission_kind='persisted_external_DDR_seed', synthetic_checker_fixture=True,
            bundle_manifest_sha256=sha(manifest), game=args.game,
            seed_sha256=hashlib.sha256(loaded).hexdigest(), loaded_counter=0xffffffff,
            expected_counters=[0xffffffff, 0], persisted_file_sha256=hashlib.sha256(persisted).hexdigest(),
            origin_manifest_sha256=sha(manifest),
            origin_coverage_sha256=sha(source/'coverage_comparison.json'),
            expected_trace_sha256=[row['sha256'] for row in coverage['coverage'][:3]],
            expected_release_observations=coverage['release_observations'][:3]))
        command = [sys.executable, '-B', str(checker), '--out', str(case_root),
                   '--bundle', str(args.reference_bundle.resolve())]
        result = subprocess.run(command, cwd=root, capture_output=True, text=True,
                                timeout=30, **NO_WINDOW)
        (case_root/'checker.log').write_text(result.stdout+result.stderr, newline='\n')
        assert result.returncode == expected, result.stdout+result.stderr
        report = json.loads((case/'cold_continuation_comparison.json').read_text())
        assert report['cold_continuation_checks_passed'] == (expected == 0)
        if expected:
            assert len([item for item in report['failures'] if 'differs from the original SAVE' in item]) == 3
        cases.append(dict(name=name, returncode=result.returncode,
            expected_returncode=expected, log_sha256=sha(case_root/'checker.log')))
    report = dict(accepted=True, checker_sha256=sha(checker), recorder_sha256=sha(Path(__file__)),
        fixture_coverage_sha256=sha(source/'coverage_comparison.json'), cases=cases,
        scope='Checker regression only, with explicitly synthetic cold-run metadata and '
              'read-only real-game traces. Same checkpoint passes; three mutually equal '
              'continuations from the wrong checkpoint are rejected against the original '
              'SAVE. No cold machine or new game simulation was executed.')
    write(root/'docs/reference'/('state_cold_checker_'+args.label+'_checks.json'), report)
    print('PASS cross-boot checker positive and wrong-checkpoint rejection; no cold machine run claimed')


if __name__ == '__main__':
    main()
