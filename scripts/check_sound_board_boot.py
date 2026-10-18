# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare the connected native-RAM sound board to MAME startup traces."""
import argparse
import hashlib
import json
from pathlib import Path
from coretools import core_root
from run_baselines import run_case


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare_startup(expected, actual, native_reset=False):
    """Keep every address/mask strict; expose only audited bootstrap save bytes."""
    if len(expected) != len(actual):
        raise SystemExit(f'Sound startup write count mismatch: {len(actual)} != {len(expected)}')
    # Pinned program: PUSH AF/PUSH BC at 081A/081B (Japan) or 0817/0818 (US),
    # then PUSH AF at 0836 (Japan) or 0833 (US). Reset-dependent F/B and inherited flags are saved
    # before XOR A (0013) and LD BC (0014) establish the program's own state.
    allowed = {4: 0xFFFC, 5: 0xFFFB, 13: 0xFFF8, 18: 0xFFF8}
    differences = []
    peripheral = 0
    for index, (wanted, observed) in enumerate(zip(expected, actual)):
        if wanted[:2] != observed[:2]:
            raise SystemExit(f'Sound address/mask mismatch #{index}: {wanted} != {observed}')
        address = int(wanted[0], 16)
        if address < 0xF800:
            peripheral += 1
        if wanted[2] != observed[2]:
            if not native_reset or allowed.get(index) != address:
                raise SystemExit(f'Sound data mismatch #{index}: {wanted} != {observed}')
            differences.append(dict(index=index, address=wanted[0], mame=wanted[2], rtl=observed[2]))
    return dict(ordered_address_mask_checks=len(actual), peripheral_writes_compared=peripheral,
                ram_data_differences=differences, exact_ram_data_checks=len(actual)-peripheral-len(differences))


def read_trace(path):
    return [tuple(word.upper() for word in line.split()) for line in path.read_text().splitlines()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-reset', action='store_true', help='Use native CPU reset and RAM configuration, with audited bootstrap save-byte exceptions')
    parser.add_argument('--reuse-existing', action='store_true', help='Retrospectively audit source/log-hashed native runs already recorded under debug')
    args = parser.parse_args()
    if args.reuse_existing and not args.native_reset:
        parser.error('--reuse-existing requires --native-reset')
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    sources = [f'rtl/cpu/t80/{name}.vhd' for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources += [row['target'] for row in manifest['files'] if row['target'].startswith(('rtl/sound/jt51/', 'sim/vendor/jt51/')) and row['target'].endswith('.v')]
    sources += ['rtl/rabbitpunch_z80.vhd', 'rtl/rabbitpunch_soundcpu.vhd', 'rtl/rabbitpunch_ym2151.vhd', 'rtl/rabbitpunch_ram8.vhd', 'rtl/rabbitpunch_sound_bus.vhd', 'rtl/rabbitpunch_sound_board.vhd', 'sim/sound/sound_board_boot_tb.vhd']
    source_hashes = {name: sha(root/name) for name in sources}
    reports = []
    for reference in json.loads((root/'docs/reference/sound_boot_reference.json').read_text()):
        game = reference['set']
        rom = root/'debug/rom_regions'/game/'audiocpu.bin'
        trace = root/reference['trace']
        assert sha(rom) == reference['audiocpu_sha256'] and sha(trace) == reference['trace_sha256']
        bootstrap_hash = hashlib.sha256(rom.read_bytes()[:0x867]).hexdigest()
        if args.native_reset:
            audited = {
                'rabiolep': '33e51d367c3298887142ff73f661a701c7951b7c294777ab6a9a3306a5524928',
                'rpunch': '2cc30a008dfbfc9e25a4edf2b229d9c86030dcfdfb016fb8eb21b98c9c60302a',
            }
            assert bootstrap_hash == audited[game], 'Bootstrap ROM changed; re-audit the native-reset exceptions'
        case = f'sound_board_native_{game}' if args.native_reset else f'sound_board_boot_{game}'
        out = root/'debug/baselines'/case
        out.mkdir(parents=True, exist_ok=True)
        (out/'audio_rom.hex').write_text(''.join(f'{byte:02x}\n' for byte in rom.read_bytes()))
        state_file = root/'debug/sound_boot'/game/'reset_state.txt'
        assert sha(state_file) == reference['reset_state_sha256']
        state = {name: int(value) for name, value in (line.split() for line in state_file.read_text().splitlines())}
        # Use the vendor's existing state-load input only in simulation. This
        # normalizes unspecified power-up registers without changing chip RTL.
        fields = [('A', 8), ('F', 8), ('AF2', 16), ('I', 8), ('R', 8), ('SP', 16), ('PC', 16),
                  ('BC', 16), ('DE', 16), ('HL', 16), ('IX', 16), ('BC2', 16), ('DE2', 16),
                  ('HL2', 16), ('IY', 16), ('IM', 2), ('IFF1', 1), ('IFF2', 1)]
        # T80 packs A' before F', opposite the usual AF word notation.
        state['AF2'] = ((state['AF2'] & 255) << 8) | (state['AF2'] >> 8)
        packed, shift = 0, 0
        for name, width in fields:
            packed |= state[name] << shift
            shift += width
        assert shift == 212
        path = '/sound_board_boot_tb/board/sound_cpu/cpu/cpu/u0'
        ram_path = '/sound_board_boot_tb/board/sound_bus/sound_ram/physical_ram/MEMORY'
        seed = tuple(f'mem load -filltype value -filldata 0 -fillradix hexadecimal {ram_path}/m_mem_data_{port}' for port in ('a', 'b'))
        setup = (*seed, 'run 2001 ns', f"force -freeze {path}/DIR 212'h{packed:053x}",
                 f'force -freeze {path}/DIRSet 1', 'run 21 ns',
                 f'noforce {path}/DIRSet', f'noforce {path}/DIR')
        if args.native_reset:
            setup = ()
        if args.reuse_existing:
            result = json.loads((root/f'debug/{case}_analysis.json').read_text())
            assert result['source_sha256'] == source_hashes
            assert result['rom_sha256'] == sha(rom) and result['log_sha256'] == sha(root/result['log'])
            assert 'SOUND_BOARD_BOOT_PASS' in (root/result['log']).read_text()
        else:
            result = run_case(case, sources, 'sound_board_boot_tb', '101 ms', 'SOUND_BOARD_BOOT_PASS',
                              sim_args=(f'-gGINT_WRITE_LIMIT={reference["writes"]}',), wall_timeout=900, setup_commands=setup)
        assert source_hashes == {name: sha(root/name) for name in sources}, 'Sources changed during sound simulation'
        expected = read_trace(trace)
        actual = read_trace(out/'rtl_sound_writes.txt')
        comparison = compare_startup(expected, actual, args.native_reset)
        if args.reuse_existing:
            prior = [{**row, 'address': row['address'].upper()} for row in result['ram_data_differences']]
            assert prior == comparison['ram_data_differences'], 'Saved native run trace changed after initial comparison'
        if args.native_reset:
            controls = []
            candidates = [('peripheral_data', 0, 2, '01'), ('ordinary_ram_data', 100, 2, '01'),
                          ('ordinary_address', 100, 0, 'F801'), ('byte_mask', 100, 1, 'FE')]
            for label, index, column, value in candidates:
                changed = [list(row) for row in actual]
                changed[index][column] = value
                try:
                    compare_startup(expected, changed, True)
                except SystemExit:
                    controls.append(label)
                else:
                    raise AssertionError(f'Native sound comparator accepted bad {label}')
            result['comparator_negative_controls'] = controls
        result.update(comparison)
        result.update(set=game, writes_compared=len(actual), audiocpu_sha256=sha(rom), mame_trace_sha256=sha(trace), reset_state_sha256=sha(state_file),
            simulation_cpu_seed='none; unchanged T80 reset' if args.native_reset else 'Vendor DIR state-load input initialized from captured MAME reset state after reset; no production RTL reset change',
            simulation_ram_seed='none; production RAM configuration' if args.native_reset else 'explicit zero RAM deposits',
            retrospective_audit=args.reuse_existing, audited_bootstrap_sha256=bootstrap_hash if args.native_reset else None, comparator_sha256=sha(Path(__file__)),
            rtl_trace_sha256=sha(out/'rtl_sound_writes.txt'), log_sha256=sha(root/result['log']),
            source_sha256={name: sha(root/name) for name in sources},
            scope='Connected T80, production sound bus, native 2048-byte RAM and actual JT51; behavioral audio-ROM transport with periodic 53-clock replies; ' + ('native CPU reset and production RAM configuration, all startup addresses/masks and peripheral data exact; four explicitly audited reset-dependent stack-save byte positions reported separately; ' if args.native_reset else 'explicitly normalized MAME CPU/RAM seed; ') + 'startup only, no main commands/uPD/SDRAM/physical timing or audible-game proof')
        reports.append(result)
        print(f'PASS {game}: {comparison["peripheral_writes_compared"]} peripheral writes and {len(actual)} addresses/masks; {len(comparison["ram_data_differences"])} audited bootstrap byte differences' if args.native_reset else f'PASS {game}: {len(actual)} sound CPU startup writes match MAME', flush=True)
    (root/'docs/reference'/('sound_board_native_reset_checks.json' if args.native_reset else 'sound_board_boot_checks.json')).write_text(json.dumps(reports, indent=2)+'\n')


if __name__ == '__main__':
    main()
