# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Bind a persisted external DDR slot to a completed continuation diagnostic."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

from check_state_game_continuation import inspect_slot
from coretools import core_root


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def read(path):
    return json.loads(path.read_text())


def normalized_sha(path):
    return hashlib.sha256(path.read_text().encode()).hexdigest()


def admit_source_policy(source, origin, bundle, manifest):
    old_names, new_names = set(origin['source_sha256']), set(manifest['source_sha256'])
    assert old_names <= new_names, 'Guest source removal is not admitted'
    additions = new_names - old_names
    root = core_root()
    presentation_admission = None
    if additions:
        allowed = {'sys/video_freak.sv', 'sys/math.sv', 'rtl/video/rotation/screen_rotate_two.sv',
            'rtl/rabbitpunch_hdmi_rotation.vhd', 'rtl/rabbitpunch_video_aspect.vhd',
            'rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
            'rtl/state/rabbitpunch_state_ddr_arbiter.vhd',
            'rtl/state/rabbitpunch_state_rotation_transport.vhd',
            'rtl/state/rabbitpunch_state_hdmi_presentation.vhd'}
        assert additions <= allowed, 'Only the qualified optional presentation sources may be added'
        proof_label = 'v5' if 'sys/math.sv' in additions else 'v3'
        presentation_path = root/('docs/reference/state_hdmi_presentation_netlists_'+proof_label+'_checks.json')
        presentation = read(presentation_path)
        assert presentation['accepted']
        for name in additions:
            assert sha(root/name) == presentation['source_sha256'][name], name
            assert normalized_sha(bundle/'inputs'/name) == normalized_sha(root/name), name
        presentation_admission = dict(added_sources=sorted(additions), proof_sha256=sha(presentation_path))
    differences = {name for name in old_names
                   if manifest['source_sha256'][name] != origin['source_sha256'][name]}
    if not differences:
        return dict(presentation=presentation_admission) if presentation_admission else None
    reader = 'rtl/state/rabbitpunch_state_slot_reader.vhd'
    assert differences == {reader}, 'Only the native-proved outer ARM sentinel fix may differ'
    contract_path = root/'docs/reference/state_arm_slot_sentinel_contract_checks.json'
    contract = read(contract_path)
    assert contract['accepted'] and contract['loaded_counter'] == 'ffffffff'
    assert normalized_sha(source/'inputs'/reader) == contract['original_reader_normalized_sha256']
    assert normalized_sha(bundle/'inputs'/reader) == contract['corrected_reader_normalized_sha256']
    proof_path = root/'docs/reference/state_slot_reader_arm_sentinel_fixed_v2_checks.json'
    proof = read(proof_path)
    assert normalized_sha(proof_path) == contract['fixed_native_receipt_normalized_sha256']
    assert proof['accepted'] and proof['cases'] == 11
    native = root/'debug/ghdl/state_slot_reader_arm_sentinel_fixed_v2'
    assert sha(native/'inputs'/reader) == proof['source_sha256'][reader]
    assert sha(native/'result.log') == proof['log_sha256']
    return dict(file=reader, contract_sha256=sha(contract_path),
        presentation=presentation_admission,
        original_normalized_sha256=contract['original_reader_normalized_sha256'],
        corrected_normalized_sha256=contract['corrected_reader_normalized_sha256'])


def checkpoint_pad(scenario):
    """The VHDL stimulus freezes its frame counter when warmup ends."""
    if not scenario['gameplay']:
        return 0
    frame = scenario['checkpoint_frames']
    pad = 0
    if scenario['coin_frame'] <= frame < scenario['coin_frame'] + 6:
        pad |= 1 << 11
    if scenario['start_frame'] <= frame < scenario['start_frame'] + 6:
        pad |= 1 << 10
    if frame >= scenario['action_frame']:
        pad |= 1 << 4
        if scenario['action_frame'] + 30 <= frame < scenario['action_frame'] + 36:
            pad |= 1 << 5
        elif (frame // 60) % 2 == 0:
            pad |= 1 << 3
        else:
            pad |= 1 << 2
    return pad


def profile_identity(profile):
    if profile is None:
        return None
    return {name: profile[name] for name in ('game', 'config_hex', 'config_sha256',
        'mra', 'mra_sha256', 'polling_waits_unchanged', 'require_ready')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--reference-out', type=Path, required=True)
    parser.add_argument('--reference-bundle', type=Path, required=True)
    parser.add_argument('--game', choices=('rabiolep', 'rpunch'), required=True)
    args = parser.parse_args()
    bundle, out = args.bundle.resolve(), args.out.resolve()
    reference, source = args.reference_out.resolve(), args.reference_bundle.resolve()
    assert all(path.drive.upper() == 'D:' for path in (bundle, out, reference, source))
    target, seed = out/'cold_seed_admission.json', out/'seed_slot0.bin'
    assert out.is_dir() and not target.exists() and not seed.exists(), 'Preserve earlier seed evidence'
    manifest, origin = read(bundle/'manifest.json'), read(source/'manifest.json')
    scenario, original_scenario = manifest['scenario'], origin['scenario']
    assert scenario['boot_restore'] and not scenario['gameplay']
    post_gameplay = scenario.get('post_restore_gameplay', False)
    if post_gameplay:
        assert 2 <= scenario['coin_frame'] < scenario['start_frame'] < scenario['action_frame'] < scenario['checkpoint_frames']
    assert not original_scenario.get('boot_restore', False), 'Use an original SAVE, not a chained cold run'
    assert scenario['boot_pad'] == checkpoint_pad(original_scenario)
    assert scenario['dips'] == original_scenario['dips']
    assert scenario.get('image_identity', dict(abi='52500101', config=0, production=False)) == original_scenario.get(
        'image_identity', dict(abi='52500101', config=0, production=False)), 'Image identities must match'
    assert profile_identity(scenario.get('hiscore_profile')) == profile_identity(original_scenario.get('hiscore_profile'))
    assert manifest['roms'] == origin['roms'] and manifest['transport'] == origin['transport']
    source_policy = admit_source_policy(source, origin, bundle, manifest)
    for frozen, metadata in ((source, origin), (bundle, manifest)):
        for name, expected in metadata['source_sha256'].items():
            path = frozen/name if name.startswith('reference/') else frozen/'inputs'/name
            assert sha(path) == expected, name
        assert sha(frozen/'roms'/(args.game+'.bin')) == metadata['roms'][args.game]['sha256']
    plan = read(reference/'plan.json')
    assert plan['manifest_sha256'] == sha(source/'manifest.json')
    case = reference/args.game
    result_path = case/'coverage_comparison.json'
    result = read(result_path)
    assert result['diagnostic_checks_passed'] and result['exact_continuations_equal']
    assert not result['failures'] and result['rom_identity'] == origin['roms'][args.game]['crc32']
    assert read(case/'run.json')['returncode'] == 0
    for name in ('native_state_ram_admission.json', 'dq_native_readback_admission.json',
                 'event_monitor_admission.json'):
        receipt = read(reference/name)
        # RAM's original recorder uses manifest_sha256; newer admissions use
        # bundle_manifest_sha256. Both bind the same immutable bundle.
        assert receipt['accepted']
        assert receipt.get('bundle_manifest_sha256', receipt.get('manifest_sha256')) == plan['manifest_sha256']
    image = case/'slot0_save1.bin'
    identity = original_scenario.get('image_identity')
    extra = dict(image_identity=identity) if identity and identity['production'] else {}
    checked = inspect_slot(image, result['rom_identity'], 1, original_scenario.get('hiscore_profile'), **extra)
    assert checked == result['published_images'][0]
    for index in range(3):
        assert sha(case/f'continuation_{index+1}.txt') == result['coverage'][index]['sha256']
    assert result['coverage'][0] == result['coverage'][1] == result['coverage'][2]
    evidence = out/'cold_seed_evidence'
    evidence.mkdir()
    for name, path in (('origin_manifest.json', source/'manifest.json'),
                       ('origin_plan.json', reference/'plan.json'),
                       ('origin_coverage.json', result_path),
                       ('origin_endpoints.txt', case/'endpoints.txt'),
                       ('admit_state_game_cold_seed.py', Path(__file__))):
        shutil.copyfile(path, evidence/name)
    # process_ss persists only control+payload, clears the target mapping,
    # reads that file, then marks its counter FFFFFFFF. Model that external
    # host operation exactly; retain the original saved body/header bytes.
    persisted = image.read_bytes()[:107288]
    loaded = bytearray(0x40000)
    loaded[:len(persisted)] = persisted
    struct.pack_into('<I', loaded, 0, 0xffffffff)
    seed.write_bytes(loaded)
    (evidence/'persisted_slot_file.bin').write_bytes(persisted)
    report = dict(accepted=True, admission_kind='persisted_external_DDR_seed',
        bundle_manifest_sha256=sha(bundle/'manifest.json'), game=args.game,
        loaded_counter=0xffffffff, expected_counters=[0xffffffff, 0],
        original_published_slot_sha256=sha(image), persisted_file_sha256=hashlib.sha256(persisted).hexdigest(),
        source_policy_admission=source_policy,
        seed_sha256=sha(seed), origin_manifest_sha256=plan['manifest_sha256'],
        origin_coverage_sha256=sha(result_path), origin_case=str(case),
        expected_trace_sha256=[item['sha256'] for item in result['coverage'][:3]],
        expected_release_observations=result['release_observations'][:3],
        frozen_pad=scenario['boot_pad'], recorder_sha256=sha(Path(__file__)),
        post_restore_gameplay=scenario.get('post_restore_gameplay', False),
        post_restore_inputs=dict(coin_frame=scenario['coin_frame'], start_frame=scenario['start_frame'],
            action_frame=scenario['action_frame'], capture_frame=scenario['checkpoint_frames']) if post_gameplay else None,
        scope='Only the external DDR slot is initialized from an independently CRC-checked '
              'published SAVE, using ARM file length, zero fill and FFFFFFFF change-counter '
              'rewrite. No internal model state is written. Original continuation '
              'passed with matching guest RTL, ROMs, DIPs and score descriptor; only '
              'the separately native-proved outer reader sentinel correction may differ. '
              'Optional presentation source additions must match their qualified native '
              'composition; actual shared-bus continuation is still a separate test. '
              'An optional post-restore script changes only ordinary controller inputs '
              'after the three baseline windows, before the new SAVE. Cold continuation '
              'must still pass separately; this admission is not that test.')
    target.write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print('ADMITTED persisted external DDR seed; cold continuation remains untested')


if __name__ == '__main__':
    main()
