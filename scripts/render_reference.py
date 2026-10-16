"""Render captured board state and compare every RGB pixel against MAME's screenshot.

This is an offline reference model, not the FPGA renderer's memory architecture.
"""
import argparse
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import struct

from coretools import core_root
from png_rgb import read_rgb, write_rgb

WIDTH, HEIGHT, LEFT = 288, 216, 8


def words(path, count):
    data = path.read_bytes()
    if len(data) != count*2: raise ValueError(f"Unexpected size: {path}")
    return struct.unpack(f">{count}H",data)


def render(capture, roms):
    tilemap = words(capture/"videoram.bin",8192)
    sprites = words(capture/"spriteram.bin",2048)
    palette = words(capture/"palette.bin",1024)
    registers = (capture/"reg_vregs.bin").read_bytes()
    bitmap = (capture/"bitmap.bin").read_bytes()
    if len(registers) != 42 or len(bitmap) != 65536: raise ValueError("Bad capture region size")
    flags = int.from_bytes(registers[12:14],"big")
    scroll = [int.from_bytes(registers[n:n+2],"big")&511 for n in (0,2,4,6)]
    sprite_count, sprite_priority = registers[17]&63,registers[19]&63
    graphics = [(roms/(tag+".bin")).read_bytes() for tag in ("tiles1","tiles2","sprites")]
    if any(len(data)!=0x80000 for data in graphics): raise ValueError("Bad graphics ROM region size")

    @lru_cache(None)
    def tile(layer,code):
        data = graphics[layer][code*32:code*32+32]
        return bytes(pen for value in data for pen in (value&15,value>>4))

    @lru_cache(None)
    def sprite(code):
        data = graphics[2][code*256:code*256+256]
        return bytes((data[y*8+(x//4)*2+1-(x%4)//2] >> (4*(x%2)))&15
                     for y in range(32) for x in range(16))

    indices = [0]*(WIDTH*HEIGHT)
    priorities = [1]*(WIDTH*HEIGHT)
    layer_coverage = [0,0,0,0]
    for layer in range(2):
        for y in range(HEIGHT):
            sy = (y+scroll[layer*2])&511
            for x in range(WIDTH):
                sx = (x+LEFT+scroll[layer*2+1])&511
                entry = tilemap[layer*4096+(sx//8)*64+sy//8]
                code = ((entry&0xfff)|0x2000) if flags&(0x400<<layer) else entry&0x1fff
                pen = tile(layer,code)[(sy%8)*8+sx%8]
                if layer and pen==15: continue
                position = y*WIDTH+x
                color = ((flags&(0x10<<layer))>>(1+layer))|((entry>>13)&7)
                indices[position] = layer*256+color*16+pen
                priorities[position] |= 1<<layer
                layer_coverage[layer] += 1

    for number in reversed(range(sprite_count)):
        data0,data1,data2,_ = sprites[number*4:number*4+4]
        x_start,y_start = (data2&511)+8,513-(data0&511)
        if x_start>LEFT+WIDTH-1: x_start-=512
        if y_start>HEIGHT-1: y_start-=512
        pens = sprite(data1&0x7ff)
        color = ((data1>>13)&7)|((flags&0x40)>>3)
        mask = 0x80000000 | (0xcccc if number<sprite_priority else 0)
        for dy in range(32):
            y = y_start+dy
            if not 0<=y<HEIGHT: continue
            py = 31-dy if data1&0x800 else dy
            for dx in range(16):
                x = x_start+dx-LEFT
                if not 0<=x<WIDTH: continue
                px = 15-dx if data1&0x1000 else dx
                pen = pens[py*16+px]
                if pen==15: continue
                position=y*WIDTH+x
                if not (1<<priorities[position])&mask:
                    indices[position]=768+color*16+pen
                    layer_coverage[2]+=1
                priorities[position]=31

    for y in range(HEIGHT):
        for x in range(WIDTH):
            sx=(x+LEFT+4)&511
            value=bitmap[y*256+sx//2]
            pen=(value>>4) if sx%2==0 else value&15
            if pen!=15:
                indices[y*WIDTH+x]=512+((flags&15)<<4)+pen
                layer_coverage[3]+=1
    colors = [bytes(((value>>shift&31)<<3)|(value>>shift&31)>>2 for shift in (10,5,0)) for value in palette]
    rgb = b"".join(colors[index] for index in indices)
    return rgb,dict(flags=f"{flags:04x}",scroll=scroll,sprite_count=sprite_count,
                    sprite_priority=sprite_priority,layer_coverage=layer_coverage)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--fixture",action="append",metavar="SET:CAPTURE_DIR")
    args=parser.parse_args()
    root=core_root()
    fixtures=args.fixture or [f"{item['set']}:{root/item['capture']}" for item in
                             json.loads((root/"scripts/mame/video_fixtures.json").read_text(encoding="utf-8"))]
    reports=[]
    failures=[]
    for fixture in fixtures:
        game,folder=fixture.split(":",1)
        capture=Path(folder).resolve()
        expected_width,expected_height,expected=read_rgb(capture/"reference.png")
        if (expected_width,expected_height)!=(WIDTH,HEIGHT): raise ValueError("Unexpected capture dimensions")
        actual,state=render(capture,root/"debug/rom_regions"/game)
        write_rgb(capture/"rendered.png",WIDTH,HEIGHT,actual)
        differences=[index for index in range(WIDTH*HEIGHT) if actual[index*3:index*3+3]!=expected[index*3:index*3+3]]
        report=dict(set=game,capture=str(capture.relative_to(root)),pixels=WIDTH*HEIGHT,
                    differing_pixels=len(differences),state=state,
                    expected_rgb_sha256=hashlib.sha256(expected).hexdigest(),
                    rendered_rgb_sha256=hashlib.sha256(actual).hexdigest())
        report["capture_sha256"]={name:hashlib.sha256((capture/name).read_bytes()).hexdigest()
                                  for name in ("videoram.bin","spriteram.bin","palette.bin","bitmap.bin","reg_vregs.bin")}
        reports.append(report)
        if differences:
            first=differences[0]
            failures.append(f"{game}: {len(differences)} pixels differ, first ({first%WIDTH+LEFT},{first//WIDTH}) "
                            f"RGB {actual[first*3:first*3+3].hex()} vs {expected[first*3:first*3+3].hex()}")
        else: print(f"PASS {game}: all {WIDTH*HEIGHT} RGB pixels identical to MAME")
    (root/"debug/video_checks.json").write_text(json.dumps(reports,indent=2)+"\n",encoding="utf-8")
    if failures: raise SystemExit("\n".join(failures))
    (root/"docs/reference/video_checks.json").write_text(json.dumps(reports,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__": main()
