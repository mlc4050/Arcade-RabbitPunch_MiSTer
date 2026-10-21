# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Admit a reviewed passive post-clock recorder, not a native game timing miter."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

from coretools import core_root, NO_WINDOW


REVIEWED = ('60f35a441b3fd3bcf94655bad8f43adab3b3be6d',
            '7bc7e571f30d06c34d8295b143aacbc0c8a1c25a',
            'dcdbeb6ef0f73a7eb63ae92bc033148a90382044',
            'ab625c90636bf5a4eef56f6e268aeadcf94b2aa6',
            'dd27e637322d97846c471e061394aeea418ab739',
            '16d2d22385f945e4cbf5123046c5ad1bad6f6eb9',
            '44299fc91cbb04f068a731468820cfa20430a57d',
            'ac5d4d411b34c5136cdf9ddd438eb4a5e9b8feda',
            '1222088082418f23ec0aeee2d8b32db4bd7038e6')
INPUTS = {'i_clk', 'i_chip_clk', 'i_initialize', 'iu128_status', 'iu2_host_buttons',
    'iu32_joystick0', 'iu32_joystick1', 'iu11_key_event', 'i_osd_open', 'i_debug_pause',
    'i_host_upload', 'iu16_host_index', 'i_host_write', 'iu27_host_byte_address',
    'iu8_host_data', 'i_maintenance_access', 'i_maintenance_valid', 'i_maintenance_write',
    'iu14_maintenance_byte_address', 'iu8_maintenance_data', 'i_ddr_busy',
    'iu64_ddr_read_data', 'i_ddr_read_valid', 'i_view_enable', 'iu5_view_target',
    'iu15_view_word_address', 'i_audio_view_enable', 'iu11_audio_view_address',
    'iu4_gga_view_address', 'i_state_ddr_busy', 'i_state_ddr_read_valid', 'iu64_state_ddr_read_data'}
OUTPUTS = {
    'ou16_left_pcm': 16, 'ou16_right_pcm': 16, 'ou16_mono_pcm': 16, 'ou9_adpcm_pcm': 9,
    **{name: 1 for name in ('o_audio_sample_marker', 'o_pixel_enable', 'o_hsync',
        'o_vsync', 'o_hblank', 'o_vblank', 'o_state_cpu_stopped', 'o_eval_sound_halted',
        'o_cpu_request', 'o_cpu_request_write', 'o_audio_debug_request', 'o_audio_debug_write', 'o_active',
        'o_hiscore_enabled', 'o_hiscore_config_error', 'o_hiscore_initialized', 'o_hiscore_saved_valid',
        'o_state_run_release', 'o_state_finished', 'o_state_success', 'o_state_restoring',
        'o_state_incomplete', 'o_eval_complete')},
    'ou4_eval_irq': 4, 'ou24_cpu_request_address': 24, 'ou16_cpu_request_data': 16,
    'ou2_cpu_request_bytes': 2, 'ou16_audio_debug_address': 16, 'ou8_audio_debug_data': 8,
    'ou9_horizontal_position': 9, 'ou9_vertical_position': 9, 'ou9_output_x': 9,
    'ou8_output_y': 8, 'ou8_red': 8, 'ou8_green': 8, 'ou8_blue': 8, 'ou3_eval_window': 3,
    'ou8_state_error': 8,
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def blob(root, commit, name):
    return subprocess.check_output(['git', 'show', commit+':'+name], cwd=root, **NO_WINDOW).decode().replace('\r\n', '\n')


def fixture_with_scenario(template, scenario):
    frames = scenario['checkpoint_frames']
    assert 1 <= frames <= 1800 and 0 <= scenario['dips'] <= 0xffff
    replacements = {
        'GINT_CHECKPOINT_CYCLES : positive := 120 * 432 * 256 * 7':
            f'GINT_CHECKPOINT_CYCLES : positive := {frames} * 432 * 256 * 7',
        'GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000"':
            f'GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"{scenario["dips"]:04X}"',
    }
    if frames > 300:
        replacements['GINT_PHASE_TIMEOUT : positive := 240000000'] = 'GINT_PHASE_TIMEOUT : positive := 2000000000'
    post_gameplay = scenario.get('post_restore_gameplay', False)
    assert not post_gameplay or (scenario.get('boot_restore', False) and not scenario['gameplay'])
    if scenario['gameplay']:
        replacements['GBOOL_GAMEPLAY_INPUTS : boolean := false'] = 'GBOOL_GAMEPLAY_INPUTS : boolean := true'
    if post_gameplay:
        replacements['GBOOL_POST_RESTORE_GAMEPLAY : boolean := false'] = 'GBOOL_POST_RESTORE_GAMEPLAY : boolean := true'
    if scenario['gameplay'] or post_gameplay:
        assert scenario['coin_frame'] < scenario['start_frame'] < scenario['action_frame'] < frames
        for name, default in (('coin', 900), ('start', 990), ('action', 1290)):
            replacements[f'GINT_{name.upper()}_FRAME : positive := {default}'] = f'GINT_{name.upper()}_FRAME : positive := {scenario[name+"_frame"]}'
    if scenario.get('boot_restore', False):
        assert not scenario['gameplay'] and 0 <= scenario['boot_pad'] <= 0xffffffff
        replacements['GBOOL_BOOT_RESTORE : boolean := false'] = 'GBOOL_BOOT_RESTORE : boolean := true'
        replacements["GU32_BOOT_PAD : unsigned(31 downto 0) := (others => '0')"] = (
            f'GU32_BOOT_PAD : unsigned(31 downto 0) := x"{scenario["boot_pad"]:08X}"')
    else:
        assert scenario.get('boot_pad', 0) == 0
    identity = scenario.get('image_identity')
    if identity and identity['production']:
        assert re.fullmatch('[0-9a-f]{8}', identity['abi'])
        replacements['GU32_ABI_SIGNATURE : unsigned(31 downto 0) := x"52500101"'] = (
            'GU32_ABI_SIGNATURE : unsigned(31 downto 0) := x"'+identity['abi'].upper()+'"')
        replacements['GBOOL_CONFIG_IDENTITY : boolean := false'] = 'GBOOL_CONFIG_IDENTITY : boolean := true'
    if scenario.get('shared_presentation', False):
        assert scenario['rotation'] in (1, 2)
        replacements['GBOOL_SHARED_PRESENTATION : boolean := false'] = 'GBOOL_SHARED_PRESENTATION : boolean := true'
        replacements['GU2_ROTATION : unsigned(1 downto 0) := "01"'] = (
            f'GU2_ROTATION : unsigned(1 downto 0) := "{scenario["rotation"]:02b}"')
    profile = scenario.get('hiscore_profile')
    if profile:
        data = bytes.fromhex(profile['config_hex'])
        assert len(data) == 24 and hashlib.sha256(data).hexdigest() == profile['config_sha256']
        replacements.update({
            'GBOOL_HISCORE_PROFILE : boolean := false': 'GBOOL_HISCORE_PROFILE : boolean := true',
            "GU192_HISCORE_PROFILE : unsigned(191 downto 0) := (others => '0')":
                'GU192_HISCORE_PROFILE : unsigned(191 downto 0) := x"'+data.hex().upper()+'"',
        })
        if profile['require_ready']:
            replacements['GBOOL_REQUIRE_HISCORE_READY : boolean := false'] = 'GBOOL_REQUIRE_HISCORE_READY : boolean := true'
    for original, replacement in replacements.items():
        assert template.count(original) == 1, original
        template = template.replace(original, replacement)
    return template


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root = core_root()
    bundle, out = args.bundle.resolve(), args.out.resolve()
    assert bundle.drive.upper() == out.drive.upper() == 'D:'
    target = out/'event_monitor_admission.json'
    assert not target.exists(), 'Preserve earlier admissions'
    plan, manifest = read(out/'plan.json'), read(bundle/'manifest.json')
    assert plan['manifest_sha256'] == sha(bundle/'manifest.json')
    for name, expected in plan['tool_input_sha256'].items():
        assert sha(bundle/name) == expected, name
    for name, expected in plan['export_input_sha256'].items():
        assert sha(bundle/'export_inputs'/name) == expected, name
    cpp = (bundle/'restore_transport.cpp').read_text()
    reviewed = None
    for commit in REVIEWED:
        if cpp != blob(root, commit, 'sim/fast/state_machine_restore_transport.cpp'):
            continue
        try:
            fixture = fixture_with_scenario(blob(root, commit, 'sim/state/state_machine_restore_eval.vhd'), manifest['scenario'])
        except AssertionError:
            continue
        if (bundle/'state_machine_restore_eval.vhd').read_text() == fixture:
            reviewed = commit
            break
    assert reviewed, 'Recorder/fixture pair changed: explicit source/API review required'
    seed_receipt = None
    if manifest['scenario'].get('boot_restore', False):
        assert reviewed in ('dd27e637322d97846c471e061394aeea418ab739',
                            '16d2d22385f945e4cbf5123046c5ad1bad6f6eb9',
                            '44299fc91cbb04f068a731468820cfa20430a57d',
                            'ac5d4d411b34c5136cdf9ddd438eb4a5e9b8feda',
                            '1222088082418f23ec0aeee2d8b32db4bd7038e6'), 'Cold test must mirror the ARM file-load contract'
        seed_receipt = read(out/'cold_seed_admission.json')
        assert seed_receipt['accepted'] and seed_receipt['admission_kind'] == 'persisted_external_DDR_seed'
        assert seed_receipt['bundle_manifest_sha256'] == plan['manifest_sha256']
        assert seed_receipt['seed_sha256'] == sha(out/'seed_slot0.bin')
        assert seed_receipt['frozen_pad'] == manifest['scenario']['boot_pad']
        assert seed_receipt['loaded_counter'] == 0xffffffff
        assert seed_receipt['expected_counters'] == [0xffffffff, 0]
    else:
        assert not (out/'seed_slot0.bin').exists(), 'Normal SAVE must begin with empty external DDR'
    profile = manifest['scenario'].get('hiscore_profile')
    identity = manifest['scenario'].get('image_identity')
    if identity and identity['production']:
        definition_path = bundle/'reference/state_abi_definition.json'
        assert sha(definition_path) == identity['abi_definition_sha256']
        assert read(definition_path)['signature_hex'].lower() == identity['abi']
        assert identity['config'] == (int(profile is not None) << 16) | manifest['scenario']['dips']
    if profile:
        mra = subprocess.check_output(['git', 'show', profile['mra_commit']+':'+profile['mra']],
                                      cwd=root, **NO_WINDOW)
        assert hashlib.sha256(mra).hexdigest() == profile['mra_sha256']
        descriptor = bytes.fromhex(ET.fromstring(mra).find("rom[@index='3']/part").text)
        assert descriptor.hex() == profile['config_hex'] and profile['polling_waits_unchanged']
    assigned = set(re.findall(r'\bm\.(\w+)(?:\[\d+\])?\s*=(?!=)', cpp))
    assert assigned == INPUTS, 'Recorder drives something other than reviewed external inputs'
    assert not re.search(r'\b(?:rootp|vlSymsp|VerilatedVpi|VL_FORCE|VL_DEPOSIT)\b|(?<!&)&(?!&)\s*m\b', cpp)
    assert cpp.count('m.i_clk = 1; m.eval();') == 1
    assert cpp.index('m.i_clk = 1; m.eval();') < cpp.index('unsigned window = m.ou3_eval_window;')
    assert cpp.index('unsigned window = m.ou3_eval_window;') < cpp.index('std::fprintf(out, "C ')
    header = (out/'obj/Vstate_machine_restore_eval.h').read_text()
    outputs = dict(OUTPUTS)
    if 'unsigned(m.ou8_player1)' in cpp:
        outputs.update(ou8_player1=8, ou8_service=8)
    if 'ou8_eval_presentation_flags' in cpp:
        outputs['ou8_eval_presentation_flags'] = 8
    if 'm.o_eval_shared_ddr' in cpp:
        outputs.update({name: 1 for name in ('o_eval_shared_ddr', 'o_eval_framebuffer_blank',
                                            'o_eval_rotation_overflow')})
    for name, width in outputs.items():
        match = re.search(r'VL_OUT(?:8|16|64)?\(&'+name+r',(\d+),(\d+)\);', header)
        assert match and int(match[1])-int(match[2])+1 == width, name

    # The native/export data-path miter samples these same four clock phases.
    sampler_path = root/'docs/reference/state_sdram_alias_deep_v3_checks.json'
    sampler = read(sampler_path)
    assert sampler['accepted'] and sampler['trace_clocks'] == 6186
    sampler_source = root/'sim/fast/state_sdram_alias_transport.cpp'
    assert sha(sampler_source) == sampler['source_sha256']['sim/fast/state_sdram_alias_transport.cpp']
    def phases(text):
        return [line.strip() for line in text.splitlines() if 'Verilated::timeInc(' in line]
    assert phases(cpp) == phases(sampler_source.read_text())
    source_admission = read(out/'frozen_source_admission.json')
    assert source_admission['source_identity_verified']
    assert source_admission['manifest_sha256'] == plan['manifest_sha256']
    assert set(source_admission['observation_only_changes']) == {
        'rtl/state/rabbitpunch_state_machine.vhd', 'rtl/state/rabbitpunch_state_machine_backend.vhd'}
    backend = (bundle/'export_inputs/rtl/state/rabbitpunch_state_machine_backend.vhd').read_text()
    assert backend.count('o_eval_sound_halted <= su256_t80(229);') == 1
    assert backend.count('ou4_eval_irq <= su4_irq;') == 1
    command = read(out/'verilate.json')
    assert command['returncode'] == read(out/'build.json')['returncode'] == 0
    assert command['command'][command['command'].index('--timescale')+1] == '1ps/1ps'
    assert '--no-timing' in command['command']
    assert str(bundle/'restore_transport.cpp').replace('\\', '/') in command['command']
    evidence = out/'event_monitor_evidence'
    evidence.mkdir()
    for source in (sampler_path, sampler_source, Path(__file__)):
        shutil.copyfile(source, evidence/source.name)
    report = dict(accepted=True, admission_kind='reviewed_passive_post_clock_API_recorder',
        native_game_event_miter=False, bundle_manifest_sha256=plan['manifest_sha256'],
        reviewed_transport_commit=reviewed, transport_sha256=sha(bundle/'restore_transport.cpp'),
        fixture_sha256=sha(bundle/'state_machine_restore_eval.vhd'),
        generated_header_sha256=sha(out/'obj/Vstate_machine_restore_eval.h'),
        executable_sha256=sha(out/'obj/sim.exe'), outputs=outputs,
        cold_seed_admission_sha256=sha(out/'cold_seed_admission.json') if seed_receipt else None,
        source_identity_receipt_sha256=sha(out/'frozen_source_admission.json'),
        native_sampler_receipt_sha256=sha(sampler_path), recorder_sha256=sha(Path(__file__)),
        scope='Passive monitor source/API admission. Exact reviewed C++ can drive '
              'only external clocks, cold reset, fixed host inputs and protocol '
              'DDR storage; no internal access or state deposits. VHDL owns '
              'all game commands. Scenario changes are restricted to reviewed '
              'generics. Generated output widths and passive HALT/IRQ taps '
              'match, and sampling follows the four 5357 ps phases used by the '
              'native/export DQ miter. C records post-clock PCM/cadence/flags; '
              'M/S record write requests, excluding inactive byte lanes; '
              'P records enabled pixels, excluding inactive RGB. This is not '
              'an independent native whole-game event/timing comparison, CPU '
              'or chip-model admission, active-game coverage, full-shell or '
              'hardware qualification.')
    target.write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print('ADMITTED passive recorder source/API contract; no native whole-game timing miter claimed')


if __name__ == '__main__':
    main()
