"""Run all sound chips through shared cached SDRAM with competing read traffic."""
import hashlib
import json
import re
import struct
from coretools import core_root
from run_baselines import run_case


def synthetic_image(bench):
    image = bytearray(((address ^ (address >> 8) ^ (address >> 16)) & 255) for address in range(0x210000))
    image[0x40000:0x50000] = bytes(0x10000)
    program = bench.split('constant PROGRAM : t_program := (', 1)[1].split(');', 1)[0]
    for address, byte in re.findall(r'(16#[0-9A-F]+#|\d+)\s*=>\s*x"([0-9A-F]{2})"', program):
        index = int(address[3:-1], 16) if address.startswith('16#') else int(address)
        image[0x40000+index] = int(byte, 16)
    image[0x1d0000:] = bytes(0x40000)
    for bank in range(2):
        base = 0x1d0000 + bank*0x20000
        image[base:base+7] = bytes((0, 0x5a, 0xa5, 0x69, 0x55, 0, 0x20 if bank == 0 else 0x30))
        start = base + (0x41 if bank == 0 else 0x61)
        image[start:start+5] = bytes((0x89, 3, 0x77 if bank == 0 else 0x33, 0xff, 0))
    return image


def main():
    root = core_root()
    manifest = json.loads((root/'docs/reference/vendor_manifest.json').read_text())
    sources = ['rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_sdram_types.vhd',
               'rtl/memory/sdram/sdram.sv', 'rtl/rabbitpunch_sdram.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv']
    sources += [f'rtl/cpu/t80/{name}.vhd' for name in ('T80_Pack', 'T80_Reg', 'T80_MCode', 'T80_ALU', 'T80', 'T80se')]
    sources += [row['target'] for row in manifest['files'] if row['target'].startswith(('rtl/sound/jt51/', 'sim/vendor/jt51/', 'rtl/sound/jt7759/')) and row['target'].endswith('.v')]
    sources += [f'rtl/{name}.vhd' for name in ('rabbitpunch_z80', 'rabbitpunch_soundcpu', 'rabbitpunch_ym2151', 'rabbitpunch_ram8', 'rabbitpunch_sound_bus', 'rabbitpunch_sound_board', 'rabbitpunch_upd7759_control', 'rabbitpunch_upd7759_playback', 'rabbitpunch_upd7759', 'rabbitpunch_adpcm', 'rabbitpunch_audio', 'rabbitpunch_rom_cache', 'rabbitpunch_read_arbiter', 'rabbitpunch_audio_roms', 'rabbitpunch_audio_rom_transport')]
    sources += ['sim/sound/audio_sdram_tb.vhd']
    selected = set(sources)
    for row in manifest['files']:
        if row['target'] in selected:
            assert hashlib.sha256((root/row['target']).read_bytes()).hexdigest() == row['sha256'], row['target']
    image = synthetic_image((root/sources[-1]).read_text())
    out = root/'debug/baselines/audio_sdram'
    out.mkdir(parents=True, exist_ok=True)
    memory_file = out/'rom_words.mti'
    with memory_file.open('w') as file:
        file.write('// memory data file (do not edit following line - required for mem load use)\n')
        file.write('// instance=/audio_sdram_tb/chip/mem\n')
        file.write('// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n')
        for index, (word,) in enumerate(struct.iter_unpack('<H', image)):
            file.write(f'{index:x}: {word:04x}\n')
    result = run_case('audio_sdram', sources, 'audio_sdram_tb', '8 ms', 'AUDIO_SDRAM_PASS', wall_timeout=300,
        setup_commands=(f'mem load -format mti -infile {{{memory_file.as_posix()}}} /audio_sdram_tb/chip/mem',))
    log = (root/result['log']).read_text()
    match = re.search(r'AUDIO_SDRAM_PASS commands=2 sample_banks=2 main_bursts=(\d+) priority_bursts=(\d+) max_program_cycles=(\d+) max_sample_cycles=(\d+)', log)
    assert match, 'Missing measured shared-transport results'
    result.update(zip(('main_bursts', 'priority_bursts', 'max_program_cycles', 'max_sample_cycles'), map(int, match.groups())))
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        synthetic_image_sha256=hashlib.sha256(image).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Complete logical audio and byte caches through fair shared low-priority SDRAM port, unchanged controller and chip-command model; continuous synthetic main bursts and paced high-priority synthetic reads, two CPU-commanded sample banks and pause; directly preloaded synthetic image, no game ROMs/executing main CPU/rendered video/loader/physical timing proof')
    (root/'docs/reference/audio_sdram_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
