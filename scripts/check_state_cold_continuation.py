# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare fresh-load RESTORE continuation against its original SAVE clocks."""
import argparse
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    args = parser.parse_args()
    out, bundle = args.out.resolve(), args.bundle.resolve()
    assert out.drive.upper() == bundle.drive.upper() == 'D:'
    admission_path = out/'cold_seed_admission.json'
    admission = read(admission_path)
    assert admission['accepted'] and admission['admission_kind'] == 'persisted_external_DDR_seed'
    assert admission['bundle_manifest_sha256'] == sha(bundle/'manifest.json')
    assert sha(out/'seed_slot0.bin') == admission['seed_sha256']
    assert admission['loaded_counter'] == 0xffffffff and admission['expected_counters'] == [0xffffffff, 0]
    evidence = out/'cold_seed_evidence'
    assert sha(evidence/'origin_manifest.json') == admission['origin_manifest_sha256']
    assert sha(evidence/'origin_coverage.json') == admission['origin_coverage_sha256']
    original = read(evidence/'origin_coverage.json')
    persisted = (evidence/'persisted_slot_file.bin').read_bytes()
    seed = (out/'seed_slot0.bin').read_bytes()
    assert len(persisted) == 107288 and len(seed) == 0x40000
    assert hashlib.sha256(persisted).hexdigest() == admission['persisted_file_sha256']
    assert seed[:4] == b'\xff'*4 and seed[4:107288] == persisted[4:] and not any(seed[107288:])
    assert admission['expected_trace_sha256'] == [row['sha256'] for row in original['coverage'][:3]]
    assert admission['expected_release_observations'] == original['release_observations'][:3]
    case = out/admission['game']
    result = read(case/'coverage_comparison.json')
    assert result['diagnostic_checks_passed'] and result['exact_continuations_equal']
    assert [row['counter'] for row in result['published_images']] == admission['expected_counters']
    assert read(case/'run.json')['returncode'] == 0
    assert sha(case/'slot0_save1.bin') == admission['seed_sha256']
    assert 'EXTERNAL_SLOT counter=ffffffff bytes=262144' in (case/'endpoints.txt').read_text()
    failures = []
    for index in range(3):
        actual = sha(case/f'continuation_{index+1}.txt')
        assert actual == result['coverage'][index]['sha256']
        if actual != admission['expected_trace_sha256'][index]:
            failures.append(f'Cold window {index+1} differs from the original SAVE continuation')
        if result['release_observations'][index][1:] != admission['expected_release_observations'][index][1:]:
            failures.append(f'Cold window {index+1}: STOP/HALT/IRQ/beam differs from original SAVE')
    report = dict(accepted=False, cold_continuation_checks_passed=not failures,
        failures=failures, seed_sha256=admission['seed_sha256'],
        seed_admission_sha256=sha(admission_path),
        bundle_manifest_sha256=admission['bundle_manifest_sha256'],
        original_coverage_sha256=admission['origin_coverage_sha256'],
        cold_coverage_sha256=sha(case/'coverage_comparison.json'),
        expected_trace_sha256=admission['expected_trace_sha256'],
        actual_trace_sha256=[row['sha256'] for row in result['coverage'][:3]],
        checker_sha256=sha(Path(__file__)),
        scope='Fresh machine/ROM load, ARM file-sized zero-filled external slot '
              'with rewritten FFFFFFFF counter, ordinary restore, and three exact '
              'two-frame continuations compared with the original SAVE. Includes a new '
              'SAVE and two further RESTOREs checked by the ordinary continuation checker. '
              'No internal model deposits; this does not qualify hardware or the complete '
              'MiSTer presentation/DDR path.')
    (case/'cold_continuation_comparison.json').write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
