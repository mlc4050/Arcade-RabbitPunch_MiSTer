"""Execute downloaded main-CPU sound commands through the connected logical system."""
import hashlib
import json
import struct
from coretools import core_root
from run_baselines import run_case
from run_system_download_tests import system_sources
from run_audio_sdram_tests import synthetic_image


def main():
    root = core_root()
    sources = system_sources()[:-1] + ['sim/board/system_audio_tb.vhd']
    image = synthetic_image((root/'sim/sound/audio_sdram_tb.vhd').read_text())
    out = root/'debug/baselines/system_audio'
    out.mkdir(parents=True, exist_ok=True)
    memory_file = out/'rom_words.mti'
    with memory_file.open('w') as file:
        file.write('// memory data file (do not edit following line - required for mem load use)\n')
        file.write('// instance=/system_audio_tb/chip/mem\n')
        file.write('// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n')
        for index, (word,) in enumerate(struct.iter_unpack('<H', image)):
            file.write(f'{index:x}: {word:04x}\n')
    result = run_case('system_audio', sources, 'system_audio_tb', '8 ms', 'SYSTEM_AUDIO_PASS', wall_timeout=300,
        setup_commands=(f'mem load -format mti -infile {{{memory_file.as_posix()}}} /system_audio_tb/chip/mem',))
    result.update(source_sha256={name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
        fixture_source_sha256=hashlib.sha256((root/'sim/sound/audio_sdram_tb.vhd').read_bytes()).hexdigest(),
        synthetic_image_sha256=hashlib.sha256(image).hexdigest(),
        log_sha256=hashlib.sha256((root/result['log']).read_bytes()).hexdigest(),
        scope='Production logical system with executing fx68k/T80, native main/sound RAM, JT51/JT7759 and shared cached SDRAM: two downloaded 32-byte main diagnostics send commands through the internal sound latch/IRQ/ack, trigger both synthetic sample banks and verify sound RAM plus continued playback/cadence during coordinated CPU pause; sound/sample regions directly preloaded, logical video idle; no real game audio/full image loader/HPS/PLL/raster/electrical proof')
    (root/'docs/reference/system_audio_checks.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
