# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Run frozen game-state diagnostics, retaining explicit native admission gates."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from coretools import core_root

ROOT = core_root()
TOOLS_ROOT = Path('D:/git/Arcade-RabbitPunch_MiSTer')
NO_WINDOW = dict(creationflags=0x08000000) if os.name == 'nt' else {}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')

def lf(path):
    return path.read_bytes().replace(b'\r\n', b'\n')

def run(command, out, label, timeout, env):
    assert not (out / (label + '.log')).exists(), 'Preserve previous attempts'
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=out, env=env, text=True,
                                capture_output=True, timeout=timeout, **NO_WINDOW)
    except subprocess.TimeoutExpired as error:
        def decoded(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
        (out / (label + '.log')).write_text(decoded(error.stdout)+'\n'+decoded(error.stderr))
        write_json(out / (label + '.json'), dict(command=command,
            accepted=False, timed_out=True, seconds=time.monotonic()-start))
        raise SystemExit(label+' exceeded wall limit; partial outputs preserved')
    (out / (label + '.log')).write_text(result.stdout + '\n' + result.stderr)
    receipt = dict(command=command, returncode=result.returncode,
                   seconds=time.monotonic() - start)
    write_json(out / (label + '.json'), receipt)
    assert result.returncode == 0, (label, result.stderr[-4000:])
    return result

def require_window():
    # User authorization and the shared hardware lock are independent. Serialize
    # this heavy diagnostic against other compiler/simulator processes as well.
    query = "Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(quartus.*|vsim.*|vlog|vcom|ghdl|verilator.*|cc1plus|g\\+\\+|make|sim)$' } | Select-Object -ExpandProperty ProcessName"
    result = subprocess.run(['powershell.exe', '-NoProfile', '-Command', query],
                            capture_output=True, text=True, timeout=20, **NO_WINDOW)
    assert result.returncode == 0 and not result.stdout.strip(), result.stdout
    import sys
    sys.path.insert(0, str(ROOT / 'scripts'))
    from hwlock import require_no_jtag
    require_no_jtag('Isolated full-machine restore evaluation')

def prepare(bundle, out):
    manifest = json.loads((bundle / 'manifest.json').read_text())
    assert sha(bundle / 'state_machine_restore_eval.vhd') == manifest['fixture_sha256']
    verified = {}
    observation_changes = []
    for name, expected in manifest['source_sha256'].items():
        original = bundle / name if name.startswith('reference/') else bundle / 'inputs' / name
        assert sha(original) == expected, name
        verified[name] = expected
        exported = bundle / 'export_inputs' / name
        if not exported.exists():
            continue
        text = original.read_text()
        modified = text
        if name in ('rtl/state/rabbitpunch_state_machine.vhd', 'rtl/state/rabbitpunch_state_machine_backend.vhd'):
            marker = '        i_clk : in std_logic;'
            assert modified.count(marker) == 1
            modified = modified.replace(marker, '        o_eval_sound_halted : out std_logic;\n        ou4_eval_irq : out unsigned(3 downto 0);\n'+marker)
            if name.endswith('_backend.vhd'):
                marker = 'begin\n    o_ready <= s_machine_ready;'
                assert modified.count(marker) == 1
                modified = modified.replace(marker, 'begin\n    o_eval_sound_halted <= su256_t80(229);\n    ou4_eval_irq <= su4_irq;\n    o_ready <= s_machine_ready;')
            else:
                marker = '        port map (\n            i_clk => i_clk,'
                assert modified.count(marker) == 2
                modified = modified.replace(marker, '        port map (\n            o_eval_sound_halted => o_eval_sound_halted,\n            ou4_eval_irq => ou4_eval_irq,\n            i_clk => i_clk,', 1)
            observation_changes.append(name)
        assert exported.read_text() == modified, 'Unexpected export source mutation: '+name
    write_json(out / 'frozen_source_admission.json', dict(accepted=False,
        source_identity_verified=True, input_reference_sha256=verified,
        observation_only_changes=observation_changes,
        manifest_sha256=sha(bundle / 'manifest.json'),
        scope='Frozen input/reference hashes and exact two passive observation port changes only. No runtime or exporter qualification.'))
    manifest = json.loads((bundle / 'manifest.json').read_text())
    for name, expected in manifest['source_sha256'].items():
        source = bundle / name if name.startswith('reference/') else bundle / 'inputs' / name
        assert sha(source) == expected, name
    order = json.loads((bundle / 'source_order.json').read_text())
    contract_path = bundle / 'reference/docs/reference/fast_ram_contract_checks.json'
    contract = json.loads(contract_path.read_text())
    assert contract['accepted']
    assert sha(bundle / 'reference/scripts/run_fast_ram_tests.py') == contract['runner_sha256']
    admission = {}
    for width in (16, 8):
        logical = f'rtl/rabbitpunch_ram{width}.vhd'
        model = f'sim/fast/rabbitpunch_ram{width}_model.vhd'
        native = ROOT / logical
        assert sha(native) == contract['native_comparison']['source_sha256'][logical]
        assert lf(native) == lf(bundle / 'inputs' / logical), logical
        assert sha(bundle / 'reference' / model) == contract['source_sha256'][model]
        admission[logical] = dict(native_source_sha256=sha(native),
            frozen_source_sha256=sha(bundle / 'inputs' / logical),
            equal_after_line_ending_normalization=True,
            model_sha256=sha(bundle / 'reference' / model))
    write_json(out / 'ram_source_admission.json', dict(accepted=False,
        source_identity_matches_existing_contract=True, wrappers=admission,
        contract_sha256=sha(contract_path),
        pending='Native full state-bank access comparison still required; old primitive contract excludes read-during-write/collisions.'))
    transformed = {}
    tiles = bundle / 'export_inputs/rtl/rabbitpunch_tiles.vhd'
    text = tiles.read_text()
    for old, new in [
        ('    function bank_number', '    signal su9_selected_scroll_x, su9_selected_scroll_y : unsigned(8 downto 0);\n    function bank_number'),
        ('    end function;\nbegin', '    end function;\nbegin\n    su9_selected_scroll_x <= su9_scroll_x(bank_number(s_foreground));\n    su9_selected_scroll_y <= su9_scroll_y(bank_number(s_foreground));'),
        ('iu9_scroll_x => su9_scroll_x(bank_number(s_foreground))', 'iu9_scroll_x => su9_selected_scroll_x'),
        ('iu9_scroll_y => su9_scroll_y(bank_number(s_foreground))', 'iu9_scroll_y => su9_selected_scroll_y'),
    ]:
        assert text.count(old) == 1, old
        text = text.replace(old, new, 1)
    (out / 'rabbitpunch_tiles.vhd').write_text(text)
    transformed['rtl/rabbitpunch_tiles.vhd'] = dict(input_sha256=sha(tiles), output_sha256=sha(out / 'rabbitpunch_tiles.vhd'))
    for donor, filename in [('rtl/state/vendor/meatsauce_t80/T80.vhd', 'T80_state.vhd'),
                             ('rtl/cpu/t80/T80.vhd', 'T80_original.vhd')]:
        source = bundle / 'export_inputs' / donor
        text = source.read_text()
        mask = '(ioq and x"7")'
        branch = "if (TState = 2 and I_BTR = '1' and IR(0) = '1') or (TState = 1 and I_BTR = '1' and IR(0) = '0') then"
        assert text.count(mask) == text.count(branch) == text.count('\nbegin\n') == 1
        guard = "    assert not (RESET_n = '1' and DIRSet = '0' and ClkEn = '1' and (" + branch[3:-5] + ")) report \"FAST_T80_UNSUPPORTED_BLOCK_IO_FLAGS\" severity failure;"
        text = text.replace(mask, '(ioq and "000000111")')
        text = text.replace('\nbegin\n', '\nbegin\n' + guard + '\n', 1)
        (out / filename).write_text(text)
        transformed[donor] = dict(input_sha256=sha(source), output_sha256=sha(out / filename), fatal_guard=guard)
    write_json(out / 'export_input_transformations.json', dict(accepted=False,
        text_only=True, transformations=transformed,
        scope='Previously used exact tile combinational actual and guarded nine-bit T80 mask transforms; no tool run.'))
    return order

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--phase', choices=('prepare', 'export', 'build', 'run'), default='prepare')
    parser.add_argument('--game', choices=('rabiolep', 'rpunch'))
    parser.add_argument('--wall-timeout', type=int, default=1200)
    parser.add_argument('--diagnostic', action='store_true', help='Permit an explicitly unqualified debug build/run while native admission is incomplete')
    parser.add_argument('--require-active-audio', action='store_true')
    parser.add_argument('--require-active-checkpoint', type=int, choices=(1, 2), action='append', default=[])
    args = parser.parse_args()
    assert not (args.require_active_audio and args.require_active_checkpoint), 'Select all or explicit audio checkpoints'
    bundle = args.bundle.resolve()
    out = args.out.resolve()
    assert out.drive.upper() == 'D:' and bundle.drive.upper() == 'D:'
    assert 1 <= args.wall_timeout <= 14400
    assert bundle != out and bundle not in out.parents, 'Keep immutable bundle separate from generated attempt'
    order = json.loads((bundle / 'source_order.json').read_text())
    ghdl = TOOLS_ROOT / '.local/tools/ghdl-6.0.0/bin/ghdl.exe'
    suite = TOOLS_ROOT / '.local/tools/oss-cad-suite-20261018/oss-cad-suite'
    dev = TOOLS_ROOT / '.local/tools/w64devkit-2.10.1/w64devkit/bin'
    env = dict(os.environ)
    env['PATH'] = ';'.join((str(dev), str(suite / 'bin'), str(suite / 'lib'), env['PATH']))
    env['VERILATOR_ROOT'] = (suite / 'share/verilator').as_posix()
    env['CCACHE_DISABLE'] = '1'
    env['TEMP'] = env['TMP'] = env['TMPDIR'] = str(ROOT / '.local/tmp')
    if args.phase == 'prepare':
        assert not out.exists(), 'Use a fresh immutable attempt directory'
        out.mkdir(parents=True)
        order = prepare(bundle, out)
        write_json(out / 'plan.json', dict(accepted=False, prepared_only=True,
            bundle=str(bundle), manifest_sha256=sha(bundle / 'manifest.json'),
            tool_input_sha256={name: sha(bundle/name) for name in (
                'source_order.json', 'state_machine_restore_eval.vhd', 'restore_transport.cpp')},
            continuation_checker_sha256=sha(ROOT/'scripts/check_state_game_continuation.py'),
            export_input_sha256={name: sha(bundle/'export_inputs'/name)
                for name in json.loads((bundle/'manifest.json').read_text())['source_sha256']
                if (bundle/'export_inputs'/name).exists()},
            transformed_file_sha256={name: sha(out/name) for name in (
                'rabbitpunch_tiles.vhd', 'T80_original.vhd', 'T80_state.vhd')},
            runner_sha256=sha(Path(__file__)), compiler_run=False,
            stages=['native RAM/state-bank admission', 'GHDL state_t80 analysis/export',
                    'exact unknown-mux audit', 'SDRAM inout audit/native readback',
                    'Verilator + at most 2 C++ jobs', 'both-set bounded continuation + independent comparison'],
            remaining='Native RAM/DQ/event admission and actual complete-game continuation.'))
        print(out / 'plan.json')
        return
    require_window()
    plan = json.loads((out / 'plan.json').read_text())
    assert plan['runner_sha256'] == sha(Path(__file__)), 'Diagnostic runner changed after preparation'
    assert plan['manifest_sha256'] == sha(bundle / 'manifest.json')
    for name, expected in plan['tool_input_sha256'].items():
        assert sha(bundle/name) == expected, 'Frozen tool changed: '+name
    for name, expected in plan['export_input_sha256'].items():
        assert sha(bundle/'export_inputs'/name) == expected, 'Export input changed: '+name
    for name, expected in plan['transformed_file_sha256'].items():
        assert sha(out/name) == expected, 'Prepared transform changed: '+name
    assert sha(ROOT/'scripts/check_state_game_continuation.py') == plan['continuation_checker_sha256']
    manifest = json.loads((bundle/'manifest.json').read_text())
    for name, expected in manifest['source_sha256'].items():
        original = bundle/name if name.startswith('reference/') else bundle/'inputs'/name
        assert sha(original) == expected, 'Frozen source changed: '+name
    if args.phase == 'export':
        library = out / 'state_t80'
        library.mkdir()
        for index, name in enumerate(order['state_t80']):
            source = out / 'T80_state.vhd' if index == 3 else bundle / 'export_inputs' / name
            run([str(ghdl), '-a', '--std=08', '-fsynopsys', '--work=state_t80', '--workdir=' + str(library), str(source)], out, f'state_t80_analyze_{index}', 90, env)
        overrides = {'rtl/rabbitpunch_tiles.vhd': out / 'rabbitpunch_tiles.vhd',
                     'rtl/cpu/t80/T80.vhd': out / 'T80_original.vhd',
                     'rtl/rabbitpunch_ram16.vhd': bundle / 'reference/sim/fast/rabbitpunch_ram16_model.vhd',
                     'rtl/rabbitpunch_ram8.vhd': bundle / 'reference/sim/fast/rabbitpunch_ram8_model.vhd'}
        vhdl = [str(overrides.get(name, bundle / 'export_inputs' / name)) for name in order['work'] if name.endswith('.vhd')]
        command = [str(ghdl), '--synth', '--std=08', '-fsynopsys', '--latches', '--out=verilog', '-P' + str(library)] + vhdl + [str(bundle / 'state_machine_restore_eval.vhd'), '-e', 'state_machine_restore_eval']
        result = run(command, out, 'ghdl_export', min(args.wall_timeout, 600), env)
        (out / 'fixture_ghdl.v').write_text(result.stdout)
        pattern = re.compile(r"^  assign (\w+) = 1'bZ \? (\w+|1'b[01XZ]) : (\w+|1'b[01XZ]);$", re.M)
        (out / 'fixture.v').write_text(pattern.sub(lambda m: '  assign ' + m[1] + " = 1'bX;", result.stdout))
        audit_source = bundle / 'reference/scripts/check_corrected_sound_state_music.py'
        node = next(n for n in ast.parse(audit_source.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == 'export_identity')
        namespace = dict(re=re, sha=sha)
        exec(compile(ast.Module(body=[node], type_ignores=[]), str(audit_source), 'exec'), namespace)
        write_json(out / 'export_mux_cleanup.json', namespace['export_identity'](out))
        print('Raw export and exact scalar mux audit ready. SDRAM alias/native admission remains mandatory.')
        return
    pending = []
    for admission in ('native_state_ram_admission.json', 'dq_native_readback_admission.json', 'event_monitor_admission.json'):
        if not (out / admission).exists():
            pending.append(admission)
            continue
        receipt = json.loads((out / admission).read_text())
        assert receipt['accepted'], admission
        assert receipt['bundle_manifest_sha256'] == plan['manifest_sha256'], admission
    if pending:
        assert args.diagnostic, 'Missing admission receipts: '+str(pending)
        audit = json.loads((out / 'dq_alias_audit.json').read_text())
        assert audit['diagnostic_only'] and sha(out / 'fixture_dq.v') == audit['normalized_export_sha256']
        write_json(out / ('diagnostic_'+args.phase+'.json'), dict(accepted=False,
            pending_admissions=pending, bundle_manifest_sha256=plan['manifest_sha256'],
            scope='Diagnostic debugging only. Cannot qualify whole-game continuation before native/export admission is complete.'))
    else:
        admitted = json.loads((out / 'dq_native_readback_admission.json').read_text())
        assert sha(out / 'fixture_dq.v') == admitted['normalized_export_sha256']
    if args.phase == 'build':
        assert not (out / 'obj').exists()
        for name in ('microrom.mem', 'nanorom.mem'):
            target = out / 'rtl/cpu/fx68k' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((bundle / 'inputs/rtl/state/vendor/konamigx/fx68k' / name).read_bytes())
        sv = [str(bundle / 'export_inputs' / name) for name in order['work'] if name.endswith(('.v', '.sv'))]
        command = [str(suite / 'bin/verilator_bin.exe'), '--cc', '--exe', str(bundle / 'restore_transport.cpp'), '--assert', '--no-assert-case', '-Wno-fatal', '-Wno-ENUMVALUE', '--no-timing', '--timescale', '1ps/1ps', '--top-module', 'state_machine_restore_eval', '--Mdir', str(out / 'obj'), '-o', 'sim.exe', '-CFLAGS', '-O2 -DVL_USER_FATAL', str(out / 'fixture_dq.v')] + sv
        # Paths embedded into generated GNU make recipes must use forward
        # slashes, as in the existing verified fast-game runners.
        command = [argument.replace('\\', '/') for argument in command]
        run(command, out, 'verilate', min(args.wall_timeout, 600), env)
        run([str(dev / 'make.exe'), '-C', str(out / 'obj'), '-f', 'Vstate_machine_restore_eval.mk', '-j2'], out, 'build', args.wall_timeout, env)
        return
    assert args.game
    profile = manifest.get('scenario', {}).get('hiscore_profile')
    assert not profile or profile['game'] == args.game, 'High-score descriptor belongs to another set'
    case = out / args.game
    assert not case.exists()
    case.mkdir()
    for name in ('microrom.mem', 'nanorom.mem'):
        target = case / 'rtl/cpu/fx68k' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((out / 'rtl/cpu/fx68k' / name).read_bytes())
    run([str(out / 'obj/sim.exe'), str(bundle / 'roms' / (args.game + '.bin'))], case, 'run', args.wall_timeout, env)
    run(['python', '-B', str(ROOT/'scripts/check_state_game_continuation.py'),
         str(case), '--manifest', str(bundle/'manifest.json'), '--game', args.game] +
        (['--require-active-audio'] if args.require_active_audio else []) +
        [item for checkpoint in args.require_active_checkpoint
              for item in ('--require-active-checkpoint', str(checkpoint))],
        case, 'comparison', 120, env)

if __name__ == '__main__':
    main()
