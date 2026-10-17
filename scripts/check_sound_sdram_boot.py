"""Compare real sound-ROM startup writes through shared cached SDRAM to MAME."""
import argparse
import hashlib
import json
import re
import struct
from coretools import core_root
from run_baselines import run_case


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--writes', type=int, default=4096)
    parser.add_argument('--only', choices=('rabiolep', 'rpunch'))
    parser.add_argument('--wall-timeout', type=int, default=900)
    args = parser.parse_args()
    if not 1 <= args.writes <= 4096:
        parser.error('--writes must be between 1 and the captured 4096-write prefix')
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    sources = ['rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_sdram_types.vhd',
               'rtl/memory/sdram/sdram.sv', 'rtl/rabbitpunch_sdram.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv']
    sources += [f'rtl/cpu/t80/{name}.vhd' for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources += [row['target'] for row in manifest['files'] if row['target'].startswith(('rtl/sound/jt51/', 'sim/vendor/jt51/', 'rtl/sound/jt7759/')) and row['target'].endswith('.v')]
    sources += [f'rtl/{name}.vhd' for name in ('rabbitpunch_z80', 'rabbitpunch_soundcpu', 'rabbitpunch_ym2151', 'rabbitpunch_ram8', 'rabbitpunch_sound_bus', 'rabbitpunch_sound_board', 'rabbitpunch_upd7759', 'rabbitpunch_adpcm', 'rabbitpunch_audio', 'rabbitpunch_rom_cache', 'rabbitpunch_read_arbiter', 'rabbitpunch_audio_roms', 'rabbitpunch_audio_rom_transport')]
    sources += ['sim/sound/sound_sdram_boot_tb.vhd']
    for row in manifest['files']:
        if row['target'] in sources:
            assert sha(root/row['target']) == row['sha256'], row['target']
    results = []
    for reference in json.loads((root/'docs/reference/sound_boot_reference.json').read_text()):
        game = reference['set']
        if args.only and args.only != game:
            continue
        regions = root/'debug/rom_regions'/game
        parts = [(regions/(name+'.bin')).read_bytes() for name in ('maincpu', 'audiocpu', 'tiles1', 'tiles2', 'sprites', 'upd')]
        assert tuple(map(len, parts)) == (0x40000, 0x10000, 0x80000, 0x80000, 0x80000, 0x40000)
        assert hashlib.sha256(parts[1]).hexdigest() == reference['audiocpu_sha256']
        image = b''.join(parts)
        trace = root/reference['trace']
        assert sha(trace) == reference['trace_sha256'] and not reference['command_events']
        expected = [tuple(int(word, 16) for word in line.split()) for line in trace.read_text().splitlines()][:args.writes]
        case = f'sound_sdram_boot_{game}_{args.writes}'
        out = root/'debug/baselines'/case
        out.mkdir(parents=True, exist_ok=True)
        memory = out/'rom_words.mti'
        with memory.open('w') as file:
            file.write('// memory data file (do not edit following line - required for mem load use)\n')
            file.write('// instance=/sound_sdram_boot_tb/chip/mem\n')
            file.write('// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n')
            for index, (word,) in enumerate(struct.iter_unpack('<H', image)):
                file.write(f'{index:x}: {word:04x}\n')
        for name, base, count in (('main', 0x10000, 256), ('priority0', 0x150000, 64), ('priority1', 0x50000, 64)):
            (out/f'{name}_words.hex').write_text(''.join(f'{int.from_bytes(image[base+i*8:base+i*8+8], "little"):016x}\n' for i in range(count)))
        state_file = root/'debug/sound_boot'/game/'reset_state.txt'
        assert sha(state_file) == reference['reset_state_sha256']
        state = {name: int(value) for name, value in (line.split() for line in state_file.read_text().splitlines())}
        state['AF2'] = ((state['AF2'] & 255) << 8) | (state['AF2'] >> 8)
        fields = [('A', 8), ('F', 8), ('AF2', 16), ('I', 8), ('R', 8), ('SP', 16), ('PC', 16),
                  ('BC', 16), ('DE', 16), ('HL', 16), ('IX', 16), ('BC2', 16), ('DE2', 16),
                  ('HL2', 16), ('IY', 16), ('IM', 2), ('IFF1', 1), ('IFF2', 1)]
        packed, shift = 0, 0
        for name, width in fields:
            packed |= state[name] << shift
            shift += width
        assert shift == 212
        cpu = '/sound_sdram_boot_tb/board/sound_board/sound_cpu/cpu/cpu/u0'
        ram = '/sound_sdram_boot_tb/board/sound_board/sound_bus/sound_ram/physical_ram/MEMORY'
        setup = (f'mem load -format mti -infile {{{memory.as_posix()}}} /sound_sdram_boot_tb/chip/mem',
                 *(f'mem load -filltype value -filldata 0 -fillradix hexadecimal {ram}/m_mem_data_{port}' for port in ('a', 'b')),
                 'run 200 us', f"force -freeze {cpu}/DIR 212'h{packed:053x}",
                 f'force -freeze {cpu}/DIRSet 1', 'run 21 ns',
                 f'noforce {cpu}/DIRSet', f'noforce {cpu}/DIR',
                 'force -freeze /sound_sdram_boot_tb/s_run 1')
        result = run_case(case, sources, 'sound_sdram_boot_tb', '101 ms', 'SOUND_SDRAM_BOOT_PASS',
                          sim_args=(f'-gWRITE_LIMIT={args.writes}',), wall_timeout=args.wall_timeout,
                          setup_commands=setup)
        actual = [tuple(int(word, 16) for word in line.split()) for line in (out/'rtl_sound_writes.txt').read_text().splitlines()]
        if actual != expected:
            index = next((i for i, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]), min(len(actual), len(expected)))
            raise SystemExit(f'{game}: shared-SDRAM sound write mismatch #{index}, MAME={expected[index:index+1]}, HDL={actual[index:index+1]}')
        log = (root/result['log']).read_text()
        match = re.search(r'SOUND_SDRAM_BOOT_PASS writes=\d+ main_bursts=(\d+) priority_bursts=(\d+) max_program_cycles=(\d+) max_sample_cycles=(\d+)', log)
        assert match
        result.update(zip(('main_bursts', 'priority_bursts', 'max_program_cycles', 'max_sample_cycles'), map(int, match.groups())))
        result.update(set=game, writes_compared=len(actual), audiocpu_sha256=reference['audiocpu_sha256'],
            rom_image_sha256=hashlib.sha256(image).hexdigest(), mame_trace_sha256=sha(trace),
            rtl_trace_sha256=sha(out/'rtl_sound_writes.txt'), reset_state_sha256=sha(state_file),
            log_sha256=sha(root/result['log']), source_sha256={name: sha(root/name) for name in sources},
            simulation_seed='Captured MAME CPU DIR state and zero sound RAM; CPU enable held until seed after SDRAM cold initialization; no production reset change',
            scope='Real audio ROM startup through connected T80/native RAM/JT51/JT7759 and shared cached SDRAM controller/chip model; competing synthetic main and paced priority reads; ordered startup writes with ADPCM reset-held, direct ROM preload, no executing main CPU/captured video/game audio/loader/physical timing proof')
        results.append(result)
        (root/f'debug/{case}_checks.json').write_text(json.dumps([result], indent=2)+'\n')
        print(f'PASS {game}: {len(actual)} shared-SDRAM sound CPU writes match MAME', flush=True)
    if not args.only:
        filename = 'sound_sdram_boot_checks.json' if args.writes == 4096 else 'sound_sdram_boot_smoke_checks.json'
        (root/'docs/reference'/filename).write_text(json.dumps(results, indent=2)+'\n')


if __name__ == '__main__':
    main()
