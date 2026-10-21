# SPDX-License-Identifier: GPL-3.0-or-later
"""Record completed October 20 release-audio source and reference checks.

Requires the retained local debug captures. It never runs simulators, rebuilds
the core, modifies a reference, or publishes an artifact.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
parser.add_argument('--check-only',action='store_true',help='Verify evidence without writing a receipt')
args = parser.parse_args()
root = args.root.resolve()
captures = root/'debug/music_commands'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
source_path = root/'docs/reference/release_audio_source_20261020_checks.json'
source = json.loads(source_path.read_text())
assert source['accepted']
def git(*args):
    return subprocess.check_output(['git','-C',str(root),*args])
assert git('rev-parse',source['release_commit']+'^{tree}').decode().strip() == source['release_tree']
assert git('rev-parse',source['published_commit']+'^{tree}').decode().strip() == source['published_tree']
assert source['release_tree'] == source['published_tree']
bundle = captures/'sound_state_bundle_release_20261020_v2'
assert sha(bundle/'manifest.json') == source['manifest_sha256']
manifest = json.loads((bundle/'manifest.json').read_text())
for logical,audit in source['sources'].items():
    snapshot = (bundle/manifest['sources'][logical]['snapshot']).read_bytes()
    original = git('show',source['release_commit']+':'+logical)
    assert hashlib.sha256(snapshot).hexdigest() == audit['snapshot_sha256']
    assert hashlib.sha256(original).hexdigest() == audit['git_blob_sha256']
    assert snapshot.replace(b'\r\n',b'\n') == original.replace(b'\r\n',b'\n'),logical
release_receipt_bytes = git('show',source['release_commit']+':docs/reference/savestate_release_20261020_checks.json')
release_receipt = json.loads(release_receipt_bytes)
assert release_receipt['accepted']
assert not git('diff','--name-only',release_receipt['source_build_commit'],source['release_commit'],'--','rtl')
bitstream = git('show',source['release_commit']+':'+release_receipt['rbf'])
assert hashlib.sha256(bitstream).hexdigest() == release_receipt['rbf_sha256']
rows = []
cases = [
    ('rabiolep',3,0xe4,'release_20261020_v2','silence_correction'),
    ('rpunch',3,0xe4,'release_20261020_v3','silence_correction'),
    ('rabiolep',9,0x99,'release_20261020_parallel_v4','silence_correction'),
    ('rpunch',9,0x99,'release_20261020_v5','corpus'),
]
for game,seconds,command,label,gold_label in cases:
    name = f'{game}_{seconds}s_rtl_cmd{command:02x}_{label}'
    actual = captures/name
    gold = captures/f'{game}_{seconds}s_rtl_cmd{command:02x}_{gold_label}'
    result = json.loads((actual/'result.json').read_text())
    reference = json.loads((gold/'result.json').read_text())
    assert result['candidate_regression']['release_source']['commit'] == source['release_commit']
    assert result['candidate_regression']['release_source']['state_controls_inactive']
    assert result['candidate_regression']['latest_capture_native_admission_transferred'] is False
    for artifact,digest in result['files'].items():
        assert sha(actual/artifact) == digest,(name,artifact)
    audited_sources = []
    for name_in_result,digest in result['source_sha256'].items():
        logical = name_in_result.replace('\\','/')
        if '/sources/rtl/state/rabbitpunch_t80_capture.vhd' in logical:
            logical = 'rtl/state/rabbitpunch_t80_capture.vhd'
        if logical.startswith('rtl/'):
            assert source['sources'][logical]['snapshot_sha256'] == digest,(name,logical)
            audited_sources.append(logical)
    assert 'rtl/state/rabbitpunch_t80_capture.vhd' in audited_sources
    assert 'rtl/state/generated/jt51_state_netlist.vhd' in audited_sources
    assert 'rtl/state/generated/jt7759_state_netlist.vhd' in audited_sources
    assert result['candidate_regression']['exact_original_pcm_and_timed_trace']
    assert result['candidate_regression']['original_result_sha256'] == sha(gold/'result.json')
    for field in ('comparison','adpcm_commands','adpcm_controls'):
        comparison = result[field]
        assert comparison['mame_count'] == comparison['rtl_count'],(name,field)
        assert comparison['shorter_is_exact_prefix'] and comparison['first_difference'] is None,(name,field)
    artifacts = {}
    for artifact in ('pcm.raw','mono.wav','rtl_sound_writes.txt'):
        digest = sha(actual/artifact)
        assert digest == result['files'][artifact] == reference['files'][artifact] == sha(gold/artifact)
        artifacts[artifact] = digest
    timing_keys = ('first_sample_cycle','last_sample_cycle','sample_intervals','wav_initial_padding_samples')
    assert {key:result[key] for key in timing_keys} == {key:reference[key] for key in timing_keys}
    cleanup = result['candidate_regression']['export_cleanup']
    assert cleanup['four_state_semantics_preserved'] and cleanup['one_bit_widths_verified'] and cleanup['entire_export_delta_verified']
    assert cleanup['replacements'] == 486
    row = dict(case=name,samples=result['sample_count'],result_sha256=sha(actual/'result.json'),
        golden_case=gold.name,golden_result_sha256=sha(gold/'result.json'),
        directly_audited_release_sources=audited_sources,
        exact_golden_pcm_wav_timed_writes_and_sample_marker_timing=True,
        mame_non_timer_registers=result['comparison'],artifacts=artifacts,
        mame_sample_starts=result['adpcm_commands'],mame_sample_controls=result['adpcm_controls'],
        export_one_bit_identities=cleanup['replacements'])
    if command == 0x99:
        corpus = captures/f'{game}_9s_rtl_cmd99_corpus'
        analysis_path = root/f'docs/reference/music_corpus_{game}_9s_cmd99_checks.json'
        analysis = json.loads(analysis_path.read_text())
        analysis_blob = git('show','HEAD:'+analysis_path.relative_to(root).as_posix())
        assert analysis_path.read_bytes().replace(b'\r\n',b'\n') == analysis_blob.replace(b'\r\n',b'\n')
        mame = captures/f'{game}_9s_mame_cmd99'
        assert sha(corpus/'result.json') == analysis['input_reports']['rtl_sha256']
        assert sha(mame/'reference.json') == analysis['input_reports']['mame_sha256']
        metadata = json.loads((mame/'reference.json').read_text())
        for artifact,digest in metadata['files'].items():
            assert sha(mame/artifact) == digest,artifact
        for artifact in artifacts:
            assert sha(corpus/artifact) == artifacts[artifact],artifact
        assert result['adpcm_commands']['mame_count'] == result['adpcm_commands']['rtl_count'] == 0
        assert analysis['note_timing']['sequence']['first_difference'] is None
        assert analysis['note_timing']['sequence']['mame_count'] == analysis['note_timing']['sequence']['rtl_count']
        row['mame_music'] = dict(analysis_sha256=sha(analysis_path),
            analysis_git_blob_sha256=hashlib.sha256(analysis_blob).hexdigest(),
            analysis_hash_scope='Local retained analysis bytes; separate Git blob hash records repository LF form. Equality checked after line-ending normalization.',
            metric_transfer='Current WAV and complete timed writes are byte-identical to both verified corpus metric inputs; preserved MAME metadata/files match original report hashes.',
            note_timing=analysis['note_timing'],waveform=analysis['waveform'],
            raw_timer_difference_retained=analysis['raw_ym'],
            scope='Ordered note/timing checks and descriptive waveform metrics; not bit-exact MAME PCM or all-track/analog-board accuracy.')
    rows.append(row)
system_bytes = subprocess.check_output(['git','-C',str(root),'show',source['release_commit']+':rtl/rabbitpunch_system.vhd'])
mute = "ou16_mono_pcm <= (others => '0') when (i_pause = '1') else su16_mono_pcm;"
assert mute in system_bytes.decode()
report = dict(accepted=True,release_commit=source['release_commit'],published_commit=source['published_commit'],
    checker_sha256=sha(Path(__file__)),
    published_bitstream=dict(path=release_receipt['rbf'],sha256=release_receipt['rbf_sha256'],
        build_commit=release_receipt['source_build_commit'],release_receipt_sha256=hashlib.sha256(release_receipt_bytes).hexdigest(),
        tested_release_rtl_identical_to_fitted_source=True),
    source_identity_report_sha256=sha(source_path),cases=rows,
    retained_pause_mute=dict(source='rtl/rabbitpunch_system.vhd',source_sha256=hashlib.sha256(system_bytes).hexdigest(),
        assignment=mute,scope='Retained source gate; no new mute change or new hardware pause test.'),
    production_rtl_changed=False,new_rbf_required=False,
    native_capture_admission_transferred=False,
    scope='Four bounded ordinary sound-playback tests of the published state-capable release: both ROM sets, corrected ADPCM example and nine-second music99. Exact golden PCM/WAV/timed writes/sample timing, complete MAME non-timer sequences; note/waveform metrics transferred only through verified input equality. No new active-restore/native whole-machine/hardware qualification.')
target = root/'docs/reference/release_audio_20261020_checks.json'
if not args.check_only:
    assert not target.exists(),'Refusing to overwrite an existing receipt'
    target.write_bytes((json.dumps(report,indent=2)+'\n').encode())
print(json.dumps(dict(accepted=True,cases=len(rows),samples=sum(row['samples'] for row in rows),
    report=None if args.check_only else str(target)),indent=2))
