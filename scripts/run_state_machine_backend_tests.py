# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Exercise the coherent state barrier around the actual single-clock machine."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from coretools import core_root, modelsim_bin, NO_WINDOW
from hwlock import require_no_jtag
from run_baselines import run_case
from run_machine_tests import machine_sources


def state_machine_sources():
    capture = ['rtl/state/vendor/konamigx/fx68k/'+name for name in
               ('fx68k.sv', 'fx68kAlu.sv', 'uaddrPla.sv')]
    capture += ['rtl/state/vendor/konamigx/gx_ss_m68k.sv']
    capture += ['rtl/state/'+name+'.vhd' for name in (
        'rabbitpunch_state_fx68k', 'rabbitpunch_m68k_capture',
        'rabbitpunch_capture_stack_undo', 'rabbitpunch_capture_phase',
        'rabbitpunch_state_maincpu', 'rabbitpunch_state_layout',
        'rabbitpunch_t80_capture')]
    capture += ['rtl/state/generated/'+name+'_state_netlist.vhd' for name in ('jt51', 'jt7759')]
    capture += ['rtl/state/rabbitpunch_state_crc.vhd', 'rtl/state/rabbitpunch_rom_identity.vhd']
    originals = [name for name in machine_sources()[:-1] if not name.startswith('rtl/cpu/fx68k/')]
    originals.insert(originals.index('rtl/rabbitpunch_board.vhd'), 'rtl/state/rabbitpunch_state_main_bus.vhd')
    originals.insert(originals.index('rtl/rabbitpunch_scanout.vhd'), 'rtl/state/rabbitpunch_state_game_timing.vhd')
    sources = capture + originals + ['rtl/state/'+name+'.vhd' for name in (
        'rabbitpunch_state_memory', 'rabbitpunch_state_body', 'rabbitpunch_state_banks',
        'rabbitpunch_state_machine_access', 'rabbitpunch_state_machine_backend')]
    sources += ['rtl/state/rabbitpunch_state_'+name+'.vhd' for name in (
        'header', 'preflight', 'semantics', 'image_buffer', 'snapshot', 'slot_reader',
        'image_validator', 'apply', 'image_words', 'slot_writer', 'publish', 'service')]
    sources += ['rtl/state/rabbitpunch_state_machine.vhd', 'sim/state/state_machine_backend_tb.vhd']
    return sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--wall-timeout', type=int, default=1800)
    parser.add_argument('--rounds', type=int, choices=(1, 2), default=2)
    args = parser.parse_args()
    assert args.label.replace('_', '').isalnum()
    assert 1 <= args.wall_timeout <= 7200
    require_no_jtag('RabbitPunch connected state machine native test')
    root = core_root()
    case = 'state_machine_backend_' + args.label
    out = root/'debug/baselines'/case
    assert not out.exists(), 'Preserve previous attempts with a fresh label'
    out.mkdir(parents=True)
    for donor in ('konamigx', 'meatsauce_t80'):
        manifest = json.loads((root/'rtl/state/vendor'/donor/'vendor_manifest.json').read_text(encoding='utf-8-sig'))
        for item in manifest['files']:
            assert hashlib.sha256((root/item['target']).read_bytes()).hexdigest() == item['sha256'], item['target']
    state_t80 = ['rtl/state/vendor/meatsauce_t80/'+name+'.vhd'
                 for name in ('T80_Reg', 'T80_MCode', 'T80_ALU', 'T80')]
    sources = state_machine_sources()
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in state_t80+sources}
    for name in hashes:
        snapshot = out/'inputs'/name
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        snapshot.write_bytes((root/name).read_bytes())
    (out/'attempt.json').write_text(json.dumps(dict(accepted=False,
        source_sha256=hashes, native_wall_limit_seconds=args.wall_timeout,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        scope='Unfinished connected-machine attempt; not qualification.'), indent=2)+'\n')
    # A private ini prevents this bench's donor library mapping changing any
    # other worktree/test session. Installed vendor library mappings are retained.
    ini = out/'modelsim.ini'
    shutil.copyfile(Path(os.environ['MODELSIM']), ini)
    os.environ['MODELSIM'] = str(ini)
    tools = modelsim_bin()
    logs = []
    for command in [[str(tools/'vlib.exe'), 'state_t80'],
                    [str(tools/'vmap.exe'), 'state_t80', str(out/'state_t80')]] + [
                    [str(tools/'vcom.exe'), '-2008', '-work', 'state_t80', str(root/name)] for name in state_t80]:
        result = subprocess.run(command, cwd=out, text=True, capture_output=True, timeout=90, **NO_WINDOW)
        logs.append(result.stdout+result.stderr)
        (out/'state_library.log').write_text('\n'.join(logs), encoding='utf-8')
        assert result.returncode == 0, logs[-1]
    for filename in ('microrom.mem', 'nanorom.mem'):
        target = out/'rtl/cpu/fx68k'/filename
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root/'rtl/state/vendor/konamigx/fx68k'/filename, target)
    result = run_case(case, sources, 'state_machine_backend_tb', '101 ms',
        'STATE_MACHINE_BACKEND_PASS', wall_timeout=args.wall_timeout,
        sim_args=('-suppress', '8315', '-suppress', '8360', '-gGINT_ROUNDS='+str(args.rounds)),
        verilog_defines=(), vlog_options=('+initreg=r+0', '+initmem=r+0'))
    assert hashes == {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in hashes}
    result.update(source_sha256=hashes, acquisition_return_rounds=args.rounds,
        runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Actual state-capable machine, paired GX68000/T80 acquisition, '
              'production SDRAM/chip model and Intel main/sound RAM, generated '
              'FM and corrected189-bit ADPCM chip surfaces, real dense byte '
              'backend with selected RAM/CPU/board/chip reads and '+str(args.rounds)+' private '
              'returns at physical beam/phase alignment. Physical pixel cadence '
              'and sync checked continuously. Synthetic64-byte main program; '
              'sound ROM absent and uninitialized architectural fields are not '
              'claimed defined. No image apply, whole-game deterministic '
              'restore, real audio/video, DDR slots, FPGA or hardware qualification.')
    (root/('docs/reference/'+case+'_checks.json')).write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
