# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Compare live boot frames with MAME and independently replayed CPU video writes."""
import argparse
import hashlib
import json
from pathlib import Path
from coretools import core_root
from png_rgb import read_rgb, write_rgb
from render_reference import render

REGIONS = [('bitmap',0x40000,65536,255), ('spriteram',0x60000,4096,0),
           ('videoram',0x80000,16384,0), ('palette',0xa0000,2048,0),
           ('workram',0xfc000,16384,0), ('reg_vregs',0xc0000,42,0)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def differences(first, second):
    assert len(first) == len(second) == 288 * 216 * 3
    return sum(first[index:index+3] != second[index:index+3] for index in range(0,len(first),3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', type=Path, required=True)
    parser.add_argument('--frames', type=int, default=120)
    args = parser.parse_args()
    root = core_root()
    reports = []
    for game in ('rabiolep','rpunch'):
        source = root / 'debug/fast_game' / (game + '_' + str(args.frames))
        capture = root / 'debug' / (game + '-liveboot' + str(args.frames))
        boot_path = root / f'docs/reference/fast_game_{game}_{args.frames}_checks.json'
        boot = json.loads(boot_path.read_text())
        assert boot['accepted'] and boot['set'] == game and boot['frames'] == args.frames
        manifest = (capture / 'manifest.txt').read_text()
        assert f'set {game}\n' in manifest and f'frame {args.frames}\n' in manifest and 'mame 0.289\n' in manifest
        width,height,live = read_rgb(source / 'video.png')
        assert (width,height) == (288,216) and hashlib.sha256(live).hexdigest() == boot['rgb_sha256']
        width,height,mame = read_rgb(capture / 'reference.png')
        assert (width,height) == (288,216)
        trace = source / 'rtl_main_writes.txt'
        before = sha(trace)
        arrays = {name:bytearray([initial])*size for name,base,size,initial in REGIONS}
        for line in trace.read_text().splitlines():
            address,mask,data = (int(word,16) for word in line.split())
            address &= 0xffffe
            for name,base,size,initial in REGIONS:
                if base <= address < base + size:
                    if mask & 0xff00:
                        arrays[name][address-base] = data >> 8
                    if mask & 0xff:
                        arrays[name][address-base+1] = data & 255
                    break
        replay = source / 'write_replay'
        replay.mkdir(exist_ok=True)
        for name,data in arrays.items():
            (replay / (name + '.bin')).write_bytes(data)
        reconstructed,state = render(replay,args.reference_root / 'debug/rom_regions' / game)
        write_rgb(replay / 'reconstructed.png',288,216,reconstructed)
        replay_difference = differences(live,reconstructed)
        mame_difference = differences(live,mame)
        assert before == sha(trace)
        report = dict(set=game,frame=args.frames,pixels=62208,
                      accepted_write_replay=replay_difference == 0,direct_mame_rgb_match=mame_difference == 0,
                      write_replay_differing_pixels=replay_difference,direct_mame_differing_pixels=mame_difference,
                      state=state,boot_report_sha256=sha(boot_path),main_trace_sha256=before,
                      live_png_sha256=sha(source / 'video.png'),mame_png_sha256=sha(capture / 'reference.png'),
                      mame_manifest_sha256=sha(capture / 'manifest.txt'),
                      live_rgb_sha256=hashlib.sha256(live).hexdigest(),mame_rgb_sha256=hashlib.sha256(mame).hexdigest(),
                      replay_sha256={name:sha(replay / (name+'.bin')) for name,base,size,initial in REGIONS},
                      source_sha256={name:sha(root/name) for name in ('scripts/compare_live_boot_frames.py','scripts/render_reference.py','scripts/png_rgb.py','scripts/mame_capture.py','scripts/mame/capture.lua','scripts/mame/run.lua','scripts/mame/regions.json')},
                      scope='Actual game CPU execution with continuous video; compare captured RGB against an independently MAME-validated software renderer fed by the complete requested-write trace and documented startup RAM contents. This is not a direct RAM dump and includes any final undrained request or writes after earlier captured rows. Direct raw MAME comparison is separately recorded; equal counted frames do not establish instruction, raster or vblank alignment. No physical hardware or general gameplay proof.')
        (root / f'docs/reference/live_boot_{game}_{args.frames}_image_checks.json').write_text(json.dumps(report,indent=2)+'\n')
        assert replay_difference == 0, f'{game}: live RGB differs from reconstructed video state by {replay_difference} pixels'
        reports.append(report)
        print(game, 'write-replay differences:', replay_difference, 'direct MAME differences:', mame_difference)
    assert all(report['accepted_write_replay'] for report in reports)


if __name__ == '__main__':
    main()
