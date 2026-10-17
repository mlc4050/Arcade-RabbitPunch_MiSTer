"""Compare the connected native-RAM sound board to MAME startup traces."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    sources = [f'rtl/cpu/t80/{name}.vhd' for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources += [row['target'] for row in manifest['files'] if row['target'].startswith(('rtl/sound/jt51/', 'sim/vendor/jt51/')) and row['target'].endswith('.v')]
    sources += ['rtl/rabbitpunch_z80.vhd', 'rtl/rabbitpunch_soundcpu.vhd', 'rtl/rabbitpunch_ym2151.vhd', 'rtl/rabbitpunch_ram8.vhd', 'rtl/rabbitpunch_sound_bus.vhd', 'rtl/rabbitpunch_sound_board.vhd', 'sim/sound/sound_board_boot_tb.vhd']
    reports = []
    for reference in json.loads((root/'docs/reference/sound_boot_reference.json').read_text()):
        game = reference['set']
        rom = root/'debug/rom_regions'/game/'audiocpu.bin'
        trace = root/reference['trace']
        assert sha(rom) == reference['audiocpu_sha256'] and sha(trace) == reference['trace_sha256']
        case = f'sound_board_boot_{game}'
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
        result = run_case(case, sources, 'sound_board_boot_tb', '101 ms', 'SOUND_BOARD_BOOT_PASS',
                          sim_args=(f'-gWRITE_LIMIT={reference["writes"]}',), wall_timeout=600, setup_commands=setup)
        expected = [tuple(int(word, 16) for word in line.split()) for line in trace.read_text().splitlines()]
        actual = [tuple(int(word, 16) for word in line.split()) for line in (out/'rtl_sound_writes.txt').read_text().splitlines()]
        if actual != expected:
            index = next((i for i, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]), min(len(actual), len(expected)))
            raise SystemExit(f'{game}: sound write mismatch #{index}, MAME={expected[index:index+1]}, HDL={actual[index:index+1]}')
        result.update(set=game, writes_compared=len(actual), audiocpu_sha256=sha(rom), mame_trace_sha256=sha(trace), reset_state_sha256=sha(state_file),
            simulation_cpu_seed='Vendor DIR state-load input initialized from captured MAME reset state after reset; no production RTL reset change',
            rtl_trace_sha256=sha(out/'rtl_sound_writes.txt'), log_sha256=sha(root/result['log']),
            source_sha256={name: sha(root/name) for name in sources},
            scope='Connected T80, production sound bus, native 2048-byte RAM and actual JT51; behavioral audio-ROM transport with periodic 53-clock replies; explicitly normalized MAME CPU/RAM seed, startup writes only, no main commands/uPD/SDRAM/physical timing proof')
        reports.append(result)
        print(f'PASS {game}: {len(actual)} sound CPU startup writes match MAME', flush=True)
    (root/'docs/reference/sound_board_boot_checks.json').write_text(json.dumps(reports, indent=2)+'\n')


if __name__ == '__main__':
    main()
