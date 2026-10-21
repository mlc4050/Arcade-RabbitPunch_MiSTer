# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Render a complete native frame from passive savestate continuation records."""
import argparse
import hashlib
import json
from pathlib import Path

from png_rgb import read_rgb, write_rgb


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trace', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    trace, out = args.trace.resolve(), args.out.resolve()
    assert trace.drive.upper() == out.drive.upper() == 'D:'
    assert trace.is_file() and out.parent.is_dir() and not out.exists()
    assert not out.with_suffix('.json').exists(), 'Preserve previous extraction'
    width, height, left = 288, 216, 8
    pixels = bytearray(width*height*3)
    seen = set()
    complete = []
    digest = hashlib.sha256()
    first_clock = None
    with trace.open('rb') as source:
        for line in source:
            digest.update(line)
            fields = line.split()
            if fields[0] != b'P' or fields[2] != b'1':
                continue
            assert len(fields) == 8
            x, y = int(fields[5])-left, int(fields[6])
            assert 0 <= x < width and 0 <= y < height
            if (x, y) == (0, 0):
                seen.clear()
                first_clock = int(fields[1])
            if first_clock is None:
                continue
            position = y*width+x
            assert position not in seen, 'Repeated active coordinate within a frame'
            seen.add(position)
            pixels[position*3:position*3+3] = int(fields[7], 16).to_bytes(3, 'big')
            if len(seen) == width*height:
                complete.append((first_clock, int(fields[1]), bytes(pixels)))
    assert complete, 'No complete frame in continuation'
    start, end, rgb = complete[-1]
    write_rgb(out, width, height, rgb)
    assert read_rgb(out) == (width, height, rgb)
    report = dict(trace_sha256=digest.hexdigest(), width=width, height=height,
        renderer_left=left, complete_frames=len(complete), first_clock=start, last_clock=end,
        rgb_sha256=hashlib.sha256(rgb).hexdigest(), png_sha256=hashlib.sha256(out.read_bytes()).hexdigest(),
        extractor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        scope='Passive trace visualization only. Every coordinate of the last complete '
              'native 288x216 frame is present once; no ROM, memory or model state is changed. '
              'This is not an independent MAME comparison or gameplay qualification.')
    out.with_suffix('.json').write_text(json.dumps(report, indent=2)+'\n', newline='\n')
    print('EXTRACTED '+str(out)+'; complete frames='+str(len(complete)))


if __name__ == '__main__':
    main()
