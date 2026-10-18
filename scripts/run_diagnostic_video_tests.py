# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Execute original firmware and score its complete native scanout image."""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
from coretools import core_root, NO_WINDOW
from png_rgb import write_rgb
from run_baselines import run_case
from run_system_download_tests import system_sources

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--corrupt', action='store_true')
parser.add_argument('--full-download', action='store_true')
parser.add_argument('--wall-timeout', type=int, default=3600)
args = parser.parse_args()
if args.wall_timeout <= 0:
    parser.error('Wall timeout must be positive')
root = core_root()
subprocess.check_call([sys.executable, str(root / 'scripts/build_diagnostic_rom.py')], **NO_WINDOW)
image = bytearray((root / 'debug/diagnostic/full/image.bin').read_bytes())
assert len(image) == 0x210000 and image[0x20000:0x20002] == bytes.fromhex('A55A')
if args.corrupt:
    image[0x20001] ^= 1
name = 'diagnostic_video_' + ('full_download_' if args.full_download else 'preloaded_') + ('corrupt' if args.corrupt else 'known')
out = root / 'debug/baselines' / name
out.mkdir(parents=True, exist_ok=True)
download = image if args.full_download else image[:32]
(out / 'download.hex').write_text(''.join(f'{word:04X}\n' for word, in struct.iter_unpack('<H', download)))
setup = []
if not args.full_download:
    memory = out / 'rom_words.mti'
    with memory.open('w') as file:
        file.write('// memory data file (do not edit following line - required for mem load use)\n')
        file.write('// instance=/diagnostic_video_tb/chip/mem\n')
        file.write('// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n')
        for index, (word,) in enumerate(struct.iter_unpack('<H', image)):
            file.write(f'{index:x}: {word:04x}\n')
    setup = [f'mem load -format mti -infile {{{memory.as_posix()}}} /diagnostic_video_tb/chip/mem']
sources = system_sources()[:-1] + ['rtl/rabbitpunch_clock_enables.vhd', 'rtl/rabbitpunch_pll.vhd',
    'rtl/rabbitpunch_raster.vhd', 'rtl/rabbitpunch_scanline_scheduler.vhd', 'rtl/rabbitpunch_video_output.vhd',
    'rtl/rabbitpunch_scanout.vhd', 'sim/board/diagnostic_video_tb.vhd']
hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result = run_case(name, sources, 'diagnostic_video_tb', '1001 ms', 'DIAGNOSTIC_VIDEO_PASS',
    sim_args=['-L', 'altera_lnsim_ver', '-L', 'altera_ver', '-L', 'lpm_ver',
              '-gGINT_DOWNLOAD_WORDS=' + str(len(download) // 2),
              '-gGBOOL_EXPECT_FAILURE=' + str(args.corrupt).lower()],
    wall_timeout=args.wall_timeout, setup_commands=setup)
assert hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
pixels = (out / 'pixels.hex').read_text().splitlines()
assert len(pixels) == 62208 and all(re.fullmatch('[0-9A-F]{6}', pixel) for pixel in pixels)
row = bytes.fromhex('FF0000 00FF00 0000FF ' + ('FF0000' if args.corrupt else 'FFFFFF')) * 72
expected = row * 216
actual = bytes.fromhex(''.join(pixels))
assert actual == expected
write_rgb(out / 'video.png', 288, 216, actual)
transcript = (root / result['log']).read_text()
result.update(corrupt_rom=args.corrupt, full_download=args.full_download, downloaded_bytes=len(download),
    image_bytes=len(image), image_sha256=hashlib.sha256(image).hexdigest(),
    bitmap_words=32768, pixels=62208, differing_pixels=0,
    max_line_cycles=int(re.search(r'max_line_cycles=\s*(\d+)', transcript)[1]),
    rgb_sha256=hashlib.sha256(actual).hexdigest(), source_sha256=hashes,
    log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
    download_sha256=hashlib.sha256((out / 'download.hex').read_bytes()).hexdigest(),
    scope=('Full original 0x210000-byte image through actual native word download into SDRAM; no ROM memory deposit. ' if args.full_download else 'ROM fixture directly preloaded, with a real 32-byte header download; not a full-image loader proof. ') +
          'Unchanged fx68k and Z80, native RAM initialization, vendor PLL/5357-ps chip clock and fractional enables, shared SDRAM/graphics, complete 32768-word executed bitmap fill, native work-RAM signature read after drained pause, and one complete 288x216 frame against independent R/G/B/white (or corrupt-ROM red) stripes. No CPU register force or board-RAM deposit. Not a game-ROM boot, HPS frontend, fitted/SDF/electrical, audible-audio or physical display proof.')
(root / ('docs/reference/' + name + '_checks.json')).write_text(json.dumps(result, indent=2) + '\n')
print('PASS native diagnostic frame: 62208 exact RGB pixels', flush=True)
