# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare bounded real-ROM main and sound startup in the production logical system."""
import argparse
import hashlib
import json
import re
import struct
import xml.etree.ElementTree as ET
from coretools import core_root
from run_baselines import run_case
from run_system_download_tests import system_sources


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=('rabiolep', 'rpunch'))
    parser.add_argument('--main-writes', type=int, default=2000)
    parser.add_argument('--sound-writes', type=int, default=256)
    parser.add_argument('--variant', default='', help='Optional artifact label to retain distinct source-generation runs')
    parser.add_argument('--wall-timeout', type=int, default=900)
    parser.add_argument("--pll-clock", action="store_true", help="Use production fractional enables and shifted SDRAM clock")
    parser.add_argument('--continuous-video', action='store_true', help='Execute real CPUs through a complete continuous rendered frame')
    args = parser.parse_args()
    if args.continuous_video and not args.pll_clock:
        parser.error('--continuous-video requires --pll-clock')
    if not 1 <= args.main_writes <= 10000 or not 1 <= args.sound_writes <= 4096:
        parser.error('Limits exceed the verified MAME startup prefixes')
    if args.variant and not re.fullmatch(r'[a-z0-9_]+', args.variant):
        parser.error('Variant must use lowercase letters, digits or underscores')
    root = core_root()
    sources = system_sources()[:-1]+['rtl/rabbitpunch_clock_enables.vhd','rtl/rabbitpunch_pll.vhd','rtl/rabbitpunch_raster.vhd','rtl/rabbitpunch_scanline_scheduler.vhd','rtl/rabbitpunch_video_output.vhd','rtl/rabbitpunch_scanout.vhd','sim/board/system_boot_tb.vhd']
    source_hashes = {name: sha(root/name) for name in sources}
    main_refs = {row['set']: row for row in json.loads((root/'docs/reference/boot_checks.json').read_text())}
    sound_refs = {row['set']: row for row in json.loads((root/'docs/reference/sound_boot_reference.json').read_text())}
    results = []
    for game in ((args.only,) if args.only else ('rabiolep', 'rpunch')):
        regions = root/'debug/rom_regions'/game
        parts = [(regions/(name+'.bin')).read_bytes() for name in ('maincpu','audiocpu','tiles1','tiles2','sprites','upd')]
        assert tuple(map(len, parts)) == (0x40000,0x10000,0x80000,0x80000,0x80000,0x40000)
        assert hashlib.sha256(parts[0]).hexdigest() == main_refs[game]['maincpu_sha256']
        assert hashlib.sha256(parts[1]).hexdigest() == sound_refs[game]['audiocpu_sha256']
        image=b''.join(parts)
        main_trace=root/'debug/boot_writes'/game/'mame_writes.txt'
        sound_trace=root/sound_refs[game]['trace']
        assert sha(main_trace)==main_refs[game]['mame_trace_sha256']
        assert sha(sound_trace)==sound_refs[game]['trace_sha256']
        case=f'system_boot_{game}_{args.main_writes}_{args.sound_writes}' + (f'_{args.variant}' if args.variant else '')
        if args.pll_clock:
            case += '_pll'
        if args.continuous_video:
            case += '_video'
        out=root/'debug/baselines'/case
        out.mkdir(parents=True,exist_ok=True)
        memory=out/'rom_words.mti'
        with memory.open('w') as file:
            file.write('// memory data file (do not edit following line - required for mem load use)\n')
            file.write('// instance=/system_boot_tb/chip/mem\n')
            file.write('// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n')
            for index,(word,) in enumerate(struct.iter_unpack('<H',image)):
                file.write(f'{index:x}: {word:04x}\n')
        (out/'main_header.hex').write_text(''.join(f'{word:04x}\n' for (word,) in struct.iter_unpack('<H',image[:32])))
        mra=next(ET.parse(path) for path in (root/'releases/_dev').glob('*.mra') if ET.parse(path).findtext('setname')==game)
        dip_bytes=mra.find('switches').get('default').split(',')
        dips=int(dip_bytes[0],16)|(int(dip_bytes[1],16)<<8)
        state_file=root/'debug/sound_boot'/game/'reset_state.txt'
        assert sha(state_file)==sound_refs[game]['reset_state_sha256']
        state={name:int(value) for name,value in (line.split() for line in state_file.read_text().splitlines())}
        state['AF2']=((state['AF2']&255)<<8)|(state['AF2']>>8)
        fields=[('A',8),('F',8),('AF2',16),('I',8),('R',8),('SP',16),('PC',16),('BC',16),('DE',16),('HL',16),('IX',16),('BC2',16),('DE2',16),('HL2',16),('IY',16),('IM',2),('IFF1',1),('IFF2',1)]
        packed=0;shift=0
        for name,width in fields:
            packed|=state[name]<<shift
            shift+=width
        assert shift==212
        cpu='/system_boot_tb/system/audio/sound_board/sound_cpu/cpu/cpu/u0'
        sound_ram='/system_boot_tb/system/audio/sound_board/sound_bus/sound_ram/physical_ram/MEMORY'
        setup=['run 1 ns',f'mem load -format mti -infile {{{memory.as_posix()}}} /system_boot_tb/chip/mem']
        # Board/sound RAM now initializes through its production altsyncram
        # configuration. Only the existing sound CPU register normalization remains.
        setup += ['run 200 us',f"force -freeze {cpu}/DIR 212'h{packed:053x}",f'force -freeze {cpu}/DIRSet 1','run 43 ns' if args.pll_clock else 'run 21 ns',f'noforce {cpu}/DIRSet',f'noforce {cpu}/DIR','force -freeze /system_boot_tb/s_run 1']
        result=run_case(case,sources,'system_boot_tb','101 ms','SYSTEM_BOOT_PASS',wall_timeout=args.wall_timeout,
            sim_args=tuple([item for name in ('altera_lnsim_ver','altera_ver','lpm_ver') for item in ('-L',name)]+[f'-gGINT_MAIN_WRITE_LIMIT={args.main_writes}',f'-gGINT_SOUND_WRITE_LIMIT={args.sound_writes}',f'-gGINT_DIP_DEFAULT={dips}']+(['-gGBOOL_PLL_CLOCK=true'] if args.pll_clock else [])+(['-gGBOOL_CONTINUOUS_VIDEO=true'] if args.continuous_video else [])),setup_commands=tuple(setup))
        for name,reference,count in [('main',main_trace,args.main_writes),('sound',sound_trace,args.sound_writes)]:
            expected=[tuple(int(word,16) for word in line.split()) for line in reference.read_text().splitlines()][:count]
            actual=[tuple(int(word,16) for word in line.split()) for line in (out/f'rtl_{name}_writes.txt').read_text().splitlines()]
            if actual!=expected:
                index=next((i for i,pair in enumerate(zip(expected,actual)) if pair[0]!=pair[1]),min(len(expected),len(actual)))
                raise SystemExit(f'{game} {name} mismatch #{index}: MAME={expected[index:index+1]}, HDL={actual[index:index+1]}')
        assert source_hashes=={name:sha(root/name) for name in sources}, 'Sources changed during simulation'
        result.update(set=game,main_writes_compared=args.main_writes,sound_writes_compared=args.sound_writes,
            pll_clock=args.pll_clock, sdram_read_capture_adjust=int(args.pll_clock),
            artifact_variant=args.variant, maintenance_bus_owner='rtl/rabbitpunch_bus_owner.vhd' in sources,ram_initialization='production configuration; no RAM deposits',
            source_sha256=source_hashes,rom_image_sha256=hashlib.sha256(image).hexdigest(),
            mame_main_trace_sha256=sha(main_trace),mame_sound_trace_sha256=sha(sound_trace),
            rtl_main_trace_sha256=sha(out/'rtl_main_writes.txt'),rtl_sound_trace_sha256=sha(out/'rtl_sound_writes.txt'),
            log_sha256=sha(root/result['log']),reset_state_sha256=sha(state_file),
            scope=('Vendor PLL system/shifted chip clocks with production fractional CPU/audio enables; ' if args.pll_clock else 'Legacy synthetic same-phase clocks; ') + 'Both real-ROM CPUs in production logical system and shared SDRAM; independent ordered startup write-prefix comparisons, configuration-initialized native RAM without simulator deposits; MAME-normalized sound CPU registers; 32-byte real header downloaded into otherwise directly preloaded image; logical video/raster events idle, no cycle alignment/full-image load/game audio/hardware timing proof')
        if args.continuous_video:
            log = (root / result['log']).read_text()
            for field in ('video_pixels', 'frames', 'lines', 'max_line_cycles'):
                result[field] = int(re.search(field + r'=\s*(\d+)', log)[1])
            assert result['video_pixels'] == 62208 and result['frames'] >= 2 and result['max_line_cycles'] <= 3024
            pixels = (out / 'boot_pixels.hex').read_text().splitlines()
            assert len(pixels) == 62208
            result['rgb_sha256'] = hashlib.sha256((out / 'boot_pixels.hex').read_bytes()).hexdigest()
            result['nonblack_pixels'] = sum(int(pixel, 16) != 0 for pixel in pixels)
            from png_rgb import write_rgb
            write_rgb(out / 'boot_video.png', 288, 216, b''.join(int(pixel, 16).to_bytes(3, 'big') for pixel in pixels))
            result['scope'] = result['scope'].replace('logical video/raster events idle, ', 'continuous provisional raster/IRQs/rendering execute alongside both real CPUs; one complete RGB frame checked for coordinate order, binary values and no underflow, without a temporally aligned MAME frame comparison; ')
            result['continuous_video'] = True
        results.append(result)
        (root/f'debug/{case}_checks.json').write_text(json.dumps([result],indent=2)+'\n')
        print(f'PASS {game}: {args.main_writes} main and {args.sound_writes} sound writes match MAME',flush=True)
    if not args.only:
        filename = 'system_boot_checks.json' if (args.main_writes, args.sound_writes) == (2000, 256) else f'system_boot_{args.main_writes}_{args.sound_writes}_checks.json'
        if args.continuous_video:
            filename = filename.replace('_checks.json', '_video_checks.json')
        if args.pll_clock:
            filename = filename.replace('_checks.json', '_pll_checks.json')
        (root/'docs/reference'/(filename.replace('_checks.json', f'_{args.variant}_checks.json') if args.variant else filename)).write_text(json.dumps(results,indent=2)+'\n')


if __name__=='__main__':
    main()
