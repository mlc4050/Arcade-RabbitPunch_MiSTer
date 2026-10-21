# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Preserve a frozen source bundle and refresh only its diagnostic test tools."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from coretools import core_root, NO_WINDOW
from run_state_machine_backend_tests import state_machine_sources

PRESENTATION_SOURCES = (
    'sys/video_freak.sv', 'sys/math.sv', 'rtl/video/rotation/screen_rotate_two.sv',
    'rtl/rabbitpunch_hdmi_rotation.vhd', 'rtl/rabbitpunch_video_aspect.vhd',
    'rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
    'rtl/state/rabbitpunch_state_ddr_arbiter.vhd',
    'rtl/state/rabbitpunch_state_rotation_transport.vhd',
    'rtl/state/rabbitpunch_state_hdmi_presentation.vhd',
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-bundle', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--refresh-core', action='store_true',
                        help='Snapshot committed HEAD core files while preserving the base references/ROMs')
    parser.add_argument('--checkpoint-frames', type=int, default=120)
    parser.add_argument('--gameplay', action='store_true')
    parser.add_argument('--coin-frame', type=int, default=900)
    parser.add_argument('--start-frame', type=int, default=990)
    parser.add_argument('--action-frame', type=int, default=1290)
    parser.add_argument('--dips', type=lambda value: int(value, 0), default=0)
    parser.add_argument('--hiscore-profile', choices=('rabiolep', 'rpunch'))
    parser.add_argument('--require-hiscore-ready', action='store_true')
    parser.add_argument('--boot-restore', action='store_true',
                        help='Begin with a persisted external slot restore; requires separate seed admission')
    parser.add_argument('--post-restore-gameplay', action='store_true',
                        help='Keep three baseline restores, then run scripted inputs before the next SAVE')
    parser.add_argument('--boot-pad', type=lambda value: int(value, 0), default=0)
    parser.add_argument('--production-identity', action='store_true',
                        help='Use the generated ABI and live DIP/profile configuration identity')
    parser.add_argument('--shared-presentation', action='store_true',
                        help='Use the actual presentation three-client DDR arbiter and rotator')
    parser.add_argument('--rotation', type=int, choices=(1, 2), default=1)
    args = parser.parse_args()
    assert 1 <= args.checkpoint_frames <= 1800 and 0 <= args.dips <= 0xffff
    assert not args.require_hiscore_ready or args.hiscore_profile
    assert not args.shared_presentation or args.refresh_core
    assert not args.production_identity or args.refresh_core, 'Generated ABI requires the matching committed core snapshot'
    assert 0 <= args.boot_pad <= 0xffffffff and (args.boot_restore or args.boot_pad == 0)
    assert not args.post_restore_gameplay or (args.boot_restore and not args.gameplay)
    if args.gameplay or args.post_restore_gameplay:
        assert 2 <= args.coin_frame < args.start_frame < args.action_frame < args.checkpoint_frames
    base, out = args.base_bundle.resolve(), args.out.resolve()
    assert base.drive.upper() == out.drive.upper() == 'D:'
    assert base.is_dir() and not out.exists() and base not in out.parents
    manifest = json.loads((base/'manifest.json').read_text())
    if not args.refresh_core:
        order = json.loads((base/'source_order.json').read_text())
        assert set(PRESENTATION_SOURCES) <= set(order['work']), 'Current fixture declarations require --refresh-core for an older bundle'
    for name, expected in manifest['source_sha256'].items():
        original = base/name if name.startswith('reference/') else base/'inputs'/name
        assert sha(original) == expected, name
    assert sha(base/'state_machine_restore_eval.vhd') == manifest['fixture_sha256']
    for game, metadata in manifest['roms'].items():
        assert sha(base/'roms'/(game+'.bin')) == metadata['sha256']
    shutil.copytree(base, out)
    root = core_root()
    profile = None
    if args.hiscore_profile:
        title = 'Rabio Lepus (Japan)' if args.hiscore_profile == 'rabiolep' else 'Rabbit Punch (US)'
        name = 'releases/'+title+'.mra'
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root,
                                           text=True, **NO_WINDOW).strip()
        data = subprocess.check_output(['git', 'show', revision+':'+name], cwd=root, **NO_WINDOW)
        mra = ET.fromstring(data)
        config = bytes.fromhex(mra.find("rom[@index='3']/part").text)
        assert len(config) == 24
        assert int.from_bytes(config[20:22], 'big') == int(mra.find("nvram[@index='4']").get('size'))
        profile = dict(game=args.hiscore_profile, config_hex=config.hex(),
            config_sha256=hashlib.sha256(config).hexdigest(), mra=name,
            mra_commit=revision, mra_sha256=hashlib.sha256(data).hexdigest(),
            polling_waits_unchanged=True, require_ready=args.require_hiscore_ready)
    if args.refresh_core:
        order = json.loads((out/'source_order.json').read_text())
        current_work = [name for name in state_machine_sources()
                        if name.startswith(('rtl/', 'sim/vendor/'))]
        # VHDL analyzes direct entity references even in an inactive generate.
        for name in PRESENTATION_SOURCES:
            if name not in current_work:
                current_work.append(name)
        added = set(current_work)-set(order['work'])
        assert set(order['work']) <= set(current_work), 'Review removed core sources explicitly'
        assert [name for name in current_work if name not in added] == order['work'], 'Existing source order changed'
        assert all(name.startswith('rtl/') or name in ('sys/video_freak.sv', 'sys/math.sv') for name in added)
        order['work'] = current_work
        (out/'source_order.json').write_text(json.dumps(order, indent=2)+'\n')
        for name in added:
            manifest['source_sha256'][name] = ''
        commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root,
                                         text=True, **NO_WINDOW).strip()
        for name in manifest['source_sha256']:
            if name.startswith('reference/'):
                continue
            data = subprocess.check_output(['git', 'show', commit+':'+name], cwd=root, **NO_WINDOW)
            # Retain the base checkout's CRLF representation for authored
            # sources; imported vendor files remain byte exact Git blobs.
            previous = (base/'inputs'/name).read_bytes() if (base/'inputs'/name).exists() else b''
            if b'\r\n' in previous and '/vendor/' not in name and '/cpu/' not in name:
                data = data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            (out/'inputs'/name).parent.mkdir(parents=True, exist_ok=True)
            (out/'inputs'/name).write_bytes(data)
            manifest['source_sha256'][name] = hashlib.sha256(data).hexdigest()
            exported = out/'export_inputs'/name
            if exported.exists() or name in added:
                exported.parent.mkdir(parents=True, exist_ok=True)
                text = data.decode()
                if name in ('rtl/state/rabbitpunch_state_machine.vhd', 'rtl/state/rabbitpunch_state_machine_backend.vhd'):
                    text = text.replace('\r\n', '\n')
                    marker = '        i_clk : in std_logic;'
                    assert text.count(marker) == 1
                    text = text.replace(marker, '        o_eval_sound_halted : out std_logic;\n        ou4_eval_irq : out unsigned(3 downto 0);\n'+marker)
                    if name.endswith('_backend.vhd'):
                        marker = 'begin\n    o_ready <= s_machine_ready;'
                        assert text.count(marker) == 1
                        text = text.replace(marker, 'begin\n    o_eval_sound_halted <= su256_t80(229);\n    ou4_eval_irq <= su4_irq;\n    o_ready <= s_machine_ready;')
                    else:
                        marker = '        port map (\n            i_clk => i_clk,'
                        assert text.count(marker) == 2
                        text = text.replace(marker, '        port map (\n            o_eval_sound_halted => o_eval_sound_halted,\n            ou4_eval_irq => ou4_eval_irq,\n            i_clk => i_clk,', 1)
                    exported.write_text(text, newline='\n')
                else:
                    exported.write_bytes(data)
        manifest['peer_commit'] = commit
    replacements = {
        'state_machine_restore_eval.vhd': 'sim/state/state_machine_restore_eval.vhd',
        'restore_transport.cpp': 'sim/fast/state_machine_restore_transport.cpp',
    }
    for target, source in replacements.items():
        shutil.copyfile(root/source, out/target)
    fixture_path = out/'state_machine_restore_eval.vhd'
    fixture = fixture_path.read_text()
    substitutions = {
        'GINT_CHECKPOINT_CYCLES : positive := 120 * 432 * 256 * 7':
            f'GINT_CHECKPOINT_CYCLES : positive := {args.checkpoint_frames} * 432 * 256 * 7',
        'GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000"':
            f'GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"{args.dips:04X}"',
    }
    if args.checkpoint_frames > 300:
        substitutions['GINT_PHASE_TIMEOUT : positive := 240000000'] = 'GINT_PHASE_TIMEOUT : positive := 2000000000'
    if args.gameplay:
        substitutions['GBOOL_GAMEPLAY_INPUTS : boolean := false'] = 'GBOOL_GAMEPLAY_INPUTS : boolean := true'
    if args.post_restore_gameplay:
        substitutions['GBOOL_POST_RESTORE_GAMEPLAY : boolean := false'] = 'GBOOL_POST_RESTORE_GAMEPLAY : boolean := true'
    if args.gameplay or args.post_restore_gameplay:
        substitutions.update({
            'GINT_COIN_FRAME : positive := 900': f'GINT_COIN_FRAME : positive := {args.coin_frame}',
            'GINT_START_FRAME : positive := 990': f'GINT_START_FRAME : positive := {args.start_frame}',
            'GINT_ACTION_FRAME : positive := 1290': f'GINT_ACTION_FRAME : positive := {args.action_frame}',
        })
    if profile:
        substitutions.update({
            'GBOOL_HISCORE_PROFILE : boolean := false': 'GBOOL_HISCORE_PROFILE : boolean := true',
            "GU192_HISCORE_PROFILE : unsigned(191 downto 0) := (others => '0')":
                'GU192_HISCORE_PROFILE : unsigned(191 downto 0) := x"'+profile['config_hex'].upper()+'"',
        })
        if args.require_hiscore_ready:
            substitutions['GBOOL_REQUIRE_HISCORE_READY : boolean := false'] = 'GBOOL_REQUIRE_HISCORE_READY : boolean := true'
    if args.boot_restore:
        assert not args.gameplay, 'Cold comparison keeps the source checkpoint external controls fixed'
        substitutions['GBOOL_BOOT_RESTORE : boolean := false'] = 'GBOOL_BOOT_RESTORE : boolean := true'
        substitutions["GU32_BOOT_PAD : unsigned(31 downto 0) := (others => '0')"] = f'GU32_BOOT_PAD : unsigned(31 downto 0) := x"{args.boot_pad:08X}"'
    if args.shared_presentation:
        substitutions['GBOOL_SHARED_PRESENTATION : boolean := false'] = 'GBOOL_SHARED_PRESENTATION : boolean := true'
        substitutions['GU2_ROTATION : unsigned(1 downto 0) := "01"'] = (
            f'GU2_ROTATION : unsigned(1 downto 0) := "{args.rotation:02b}"')
    image_identity = dict(abi='52500101', config=0, production=False)
    if args.production_identity:
        subprocess.run([sys.executable, '-B', str(root/'scripts/generate_state_abi.py')],
                       cwd=root, check=True, **NO_WINDOW)
        abi = json.loads((root/'docs/reference/state_abi.json').read_text())
        signature = abi['signature_hex'].upper()
        assert len(signature) == 8
        substitutions['GU32_ABI_SIGNATURE : unsigned(31 downto 0) := x"52500101"'] = (
            'GU32_ABI_SIGNATURE : unsigned(31 downto 0) := x"'+signature+'"')
        substitutions['GBOOL_CONFIG_IDENTITY : boolean := false'] = 'GBOOL_CONFIG_IDENTITY : boolean := true'
        image_identity = dict(abi=signature.lower(), config=(int(profile is not None) << 16) | args.dips,
            production=True, abi_definition_sha256=sha(root/'docs/reference/state_abi.json'))
        definition = out/'reference/state_abi_definition.json'
        if definition.exists():
            assert sha(definition) == image_identity['abi_definition_sha256'], 'Preserve an earlier ABI definition'
        else:
            shutil.copyfile(root/'docs/reference/state_abi.json', definition)
    for original, replacement in substitutions.items():
        assert fixture.count(original) == 1, original
        fixture = fixture.replace(original, replacement)
    fixture_path.write_text(fixture, newline='\n')
    manifest.update(preparation_revision='Tracked fixture/transport; '+('committed HEAD core snapshot' if args.refresh_core else 'unchanged frozen core sources'),
        base_manifest_sha256=sha(base/'manifest.json'),
        fixture_sha256=sha(out/'state_machine_restore_eval.vhd'),
        test_tool_sha256={name: sha(out/name) for name in replacements},
        scenario=dict(checkpoint_frames=args.checkpoint_frames, dips=args.dips, save_count=2,
            hiscore_profile=profile,
            boot_restore=args.boot_restore,
            post_restore_gameplay=args.post_restore_gameplay,
            boot_pad=args.boot_pad,
            image_identity=image_identity,
            shared_presentation=args.shared_presentation, rotation=args.rotation,
            gameplay=args.gameplay, coin_frame=args.coin_frame, start_frame=args.start_frame,
            action_frame=args.action_frame, phase_cycle_limit=2000000000 if args.checkpoint_frames > 300 else 240000000),
        compilation_run=False, simulation_run=False, accepted=False)
    (out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('PREPARED diagnostic tools; core remains frozen at '+manifest['peer_commit'])


if __name__ == '__main__':
    main()
