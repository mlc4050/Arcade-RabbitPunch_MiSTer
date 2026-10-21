# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare full-game diagnostic windows without granting native qualification."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import re
import struct
import zlib


TRACE_CYCLES = 2 * 432 * 256 * 7


def inspect_trace(path):
    counts = dict(clocks=0, main_writes=0, sound_writes=0, pixels=0,
                  active_pixels=0, nonblack_pixels=0, nonzero_pcm_clocks=0,
                  sample_markers=0, nonzero_pcm_samples=0,
                  stopped_clocks=0, halted_clocks=0)
    digest = hashlib.sha256()
    irqs = set()
    sampled_pcm = set()
    with path.open('rb') as source:
        for number, line in enumerate(source, 1):
            digest.update(line)
            fields = line.split()
            assert fields, f'{path.name}:{number}: empty record'
            kind = fields[0]
            if kind == b'C':
                assert len(fields) == 15, f'{path.name}:{number}: malformed clock'
                assert int(fields[1]) == counts['clocks'], 'Missing or repeated clock'
                counts['clocks'] += 1
                pcm = tuple(int(value, 16) for value in fields[2:6])
                counts['nonzero_pcm_clocks'] += any(pcm)
                counts['sample_markers'] += int(fields[6])
                if int(fields[6]):
                    sampled_pcm.add(pcm)
                    counts['nonzero_pcm_samples'] += any(pcm)
                counts['stopped_clocks'] += int(fields[12])
                counts['halted_clocks'] += int(fields[13])
                irqs.add(int(fields[14], 16))
            elif kind == b'M':
                assert len(fields) == 5 and 0 < int(fields[4], 16) < 4
                counts['main_writes'] += 1
            elif kind == b'S':
                assert len(fields) == 4
                counts['sound_writes'] += 1
            elif kind == b'P':
                active = int(fields[2])
                assert active in (0, 1) and len(fields) == 7 + active
                counts['pixels'] += 1
                counts['active_pixels'] += active
                counts['nonblack_pixels'] += bool(active and int(fields[7], 16))
            else:
                raise AssertionError(f'{path.name}:{number}: unknown record {kind!r}')
            assert 0 <= int(fields[1]) < TRACE_CYCLES
    counts['irq_levels'] = sorted(irqs)
    counts['distinct_sampled_pcm_values'] = len(sampled_pcm)
    counts['sha256'] = digest.hexdigest()
    return counts


def first_difference(paths):
    with paths[0].open('rb') as first, paths[1].open('rb') as second, paths[2].open('rb') as third:
        for number, records in enumerate(itertools.zip_longest(first, second, third), 1):
            if not records[0] == records[1] == records[2]:
                return dict(line=number, records=[
                    None if record is None else record.decode('ascii').rstrip()
                    for record in records])
    return None


def inspect_slot(path, rom_id, counter, profile=None, image_identity=None):
    expected_identity = image_identity or dict(abi="52500101", config=0, production=False)
    expected_abi = int(expected_identity["abi"], 16)
    expected_config = expected_identity["config"]
    assert 0 <= expected_abi <= 0xffffffff and 0 <= expected_config <= 0xffffffff
    slot = path.read_bytes()
    assert len(slot) == 0x40000
    assert struct.unpack_from('<II', slot) == (counter, 107280 // 4)
    header = slot[8:72]
    magic, version, abi, identity, length, body_crc, config, total = struct.unpack_from('<8I', header)
    assert (magic, version, abi, identity, length, config, total) == (
        0x31535052, 0x00400001, expected_abi, int(rom_id, 16), 107216, expected_config, 107280)
    assert struct.unpack_from('<6I', header, 32) == (106496, 96, 32, 64, 504, 24)
    assert zlib.crc32(header[:56]) == struct.unpack_from('<I', header, 56)[0]
    body = slot[72:72 + length]
    assert zlib.crc32(body) == body_crc and body[-1] & 0xe0 == 0
    result = dict(counter=counter, sha256=hashlib.sha256(slot).hexdigest())
    if profile:
        descriptor = bytes.fromhex(profile['config_hex'])
        assert len(descriptor) == 24
        assert hashlib.sha256(descriptor).hexdigest() == profile['config_sha256']
        address = int.from_bytes(descriptor[16:20], 'big')
        size = int.from_bytes(descriptor[20:22], 'big')
        base = 88064 + address - 0xfc000
        assert size > 1 and 88064 <= base and base + size <= 104448
        table = body[base:base + size]
        score_ready = bool(body[106624 + 44] & 4)
        assert not profile['require_ready'] or score_ready, 'Saved score-readiness flag is absent'
        result['hiscore'] = dict(ready=score_ready, address=address, length=size,
            table_sha256=hashlib.sha256(table).hexdigest(),
            initial_guards_match=(table[0], table[-1]) == (descriptor[22], descriptor[23]))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', type=Path)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--game', choices=('rabiolep', 'rpunch'), required=True)
    parser.add_argument('--require-active-audio', action='store_true')
    parser.add_argument('--require-active-checkpoint', type=int, choices=(1, 2), action='append', default=[])
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    profile = manifest.get('scenario', {}).get('hiscore_profile')
    image_identity = manifest.get('scenario', {}).get('image_identity')
    assert not profile or profile['game'] == args.game, 'High-score descriptor belongs to another set'
    save_count = manifest.get('scenario', {}).get('save_count', 1)
    assert save_count in (1, 2), 'Unsupported number of checkpoints'
    assert not (args.require_active_audio and args.require_active_checkpoint), 'Select all or explicit checkpoints'
    active_checkpoints = set(range(1, save_count + 1)) if args.require_active_audio else set(args.require_active_checkpoint)
    assert active_checkpoints <= set(range(1, save_count + 1))
    paths = [args.case / f'continuation_{index}.txt' for index in range(1, 3 * save_count + 1)]
    coverage = [inspect_trace(path) for path in paths]
    differences = [first_difference(paths[index:index + 3]) for index in range(0, len(paths), 3)]
    difference = next((item for item in differences if item is not None), None)
    failures = []
    if difference is not None:
        failures.append('Exact per-clock continuation differs')
    for index, counts in enumerate(coverage, 1):
        if counts['clocks'] != TRACE_CYCLES:
            failures.append(f'Window {index}: incomplete continuation')
        for field in ('main_writes', 'sound_writes', 'nonblack_pixels', 'sample_markers'):
            if not counts[field]:
                failures.append(f'Window {index}: no {field}')
        if (index - 1) // 3 + 1 in active_checkpoints and (not counts['nonzero_pcm_samples'] or
                                         counts['distinct_sampled_pcm_values'] < 2):
            failures.append(f'Window {index}: varying nonzero sampled audio required but absent')
    rom_id = manifest['roms'][args.game]['crc32']
    endpoints = (args.case / 'endpoints.txt').read_text()
    assert f'ROM_ID {rom_id}' in endpoints, 'ROM identity differs'
    windows = re.findall(r'WINDOW ([1-6]) cycle=\d+ go=1 stop=([01]) halt=([01]) irq=([0-9a-f]+) beam=(\d+),(\d+)', endpoints)
    assert [item[0] for item in windows] == [str(index) for index in range(1, len(paths) + 1)], 'Missing aligned releases'
    for index in range(0, len(windows), 3):
        if not windows[index][1:] == windows[index + 1][1:] == windows[index + 2][1:]:
            failures.append(f'Checkpoint {index // 3 + 1}: STOP/HALT/IRQ/beam differs at release')
    shared_observations = None
    if manifest.get('scenario', {}).get('shared_presentation', False):
        shared = re.search(r'SHARED_DDR rotation_writes=(\d+) unblanked=([01])', endpoints)
        assert shared and int(shared[1]) > 0, 'Shared presentation scenario did not exercise rotation DDR writes'
        shared_observations = dict(rotation_writes=int(shared[1]), unblanked=bool(int(shared[2])))
    images = []
    boot_restore = manifest.get('scenario', {}).get('boot_restore', False)
    counters = [0xffffffff, 0] if boot_restore else list(range(1, save_count + 1))
    assert len(counters) == save_count
    for index, counter in enumerate(counters, 1):
        name = f'slot0_save{index}.bin' if save_count > 1 else 'slot0.bin'
        images.append(inspect_slot(args.case / name, rom_id, counter, profile, image_identity))
    final_image = inspect_slot(args.case / 'slot0.bin', rom_id, counters[-1], profile, image_identity)
    assert final_image == images[-1], 'Restoring modified the published image'
    score_observations = []
    if profile:
        assert 'PROFILE enabled=1 error=0' in endpoints, 'Normal high-score profile was not accepted'
        score_observations = re.findall(r'WINDOW ([1-6]) [^\n]* nvready=([01]) nvsaved=([01])', endpoints)
        assert [item[0] for item in score_observations] == [str(index) for index in range(1, len(paths) + 1)]
        for index, observation in enumerate(score_observations):
            assert bool(int(observation[1])) == images[index // 3]['hiscore']['ready'], 'Readiness differs from the saved image'
    result = dict(accepted=False, diagnostic_checks_passed=not failures,
        exact_continuations_equal=difference is None, failures=failures,
        first_difference=difference, coverage=coverage,
        checkpoint_differences=differences, published_images=images,
        hiscore_profile=profile, hiscore_release_observations=score_observations,
        image_identity=image_identity or dict(abi="52500101", config=0, production=False),
        shared_presentation_observations=shared_observations,
        active_audio_required=args.require_active_audio,
        active_audio_checkpoints_required=sorted(active_checkpoints),
        rom_identity=rom_id, release_observations=windows,
        independently_checked_header_and_body_crc=True,
        slot_sha256=final_image['sha256'],
        checker_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        scope='Diagnostic evidence only. Native/export admission and full MiSTer '
              'integration remain independent gates. STOP/HALT/IRQ counts describe '
              'observed coverage, not proof of every interrupt or stopped-state case.')
    (args.case / 'coverage_comparison.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
