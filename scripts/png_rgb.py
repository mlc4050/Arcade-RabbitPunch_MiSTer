"""Small standard-library PNG RGB reader/writer for deterministic capture checks."""
import struct
import zlib


def read_rgb(path):
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not PNG: {path}")
    offset, compressed, palette = 8, bytearray(), None
    width = height = depth = color = None
    while offset < len(raw):
        length = struct.unpack_from(">I", raw, offset)[0]
        kind, payload = raw[offset+4:offset+8], raw[offset+8:offset+8+length]
        crc = struct.unpack_from(">I", raw, offset+8+length)[0]
        if zlib.crc32(kind+payload) & 0xffffffff != crc:
            raise ValueError(f"Bad PNG CRC: {path}/{kind}")
        if kind == b"IHDR":
            width,height,depth,color,method,filter_method,interlace = struct.unpack(">IIBBBBB",payload)
            if method or filter_method or interlace:
                raise ValueError("Only standard, noninterlaced PNG is supported")
        elif kind == b"PLTE":
            palette = payload
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
        offset += length+12
    channels = {2:3,3:1,6:4}.get(color)
    if channels is None or (color != 3 and depth != 8) or depth not in (1,2,4,8):
        raise ValueError(f"Unsupported PNG type {color}, depth {depth}")
    stride = (width*channels*depth+7)//8
    byte_step = max(1,(channels*depth+7)//8)
    decoded = zlib.decompress(compressed)
    if len(decoded) != height*(stride+1):
        raise ValueError("Incorrect PNG pixel payload size")
    pixels, previous = bytearray(), bytearray(stride)
    for y in range(height):
        start = y*(stride+1)
        mode = decoded[start]
        row = bytearray(decoded[start+1:start+1+stride])
        for x in range(stride):
            left = row[x-byte_step] if x >= byte_step else 0
            up = previous[x]
            upper_left = previous[x-byte_step] if x >= byte_step else 0
            if mode == 0: predictor = 0
            elif mode == 1: predictor = left
            elif mode == 2: predictor = up
            elif mode == 3: predictor = (left+up)//2
            elif mode == 4:
                p = left+up-upper_left
                distances = (abs(p-left),abs(p-up),abs(p-upper_left))
                predictor = (left,up,upper_left)[distances.index(min(distances))]
            else: raise ValueError(f"Unsupported PNG filter {mode}")
            row[x] = (row[x]+predictor)&255
        if color == 2:
            pixels.extend(row)
        elif color == 6:
            for x in range(width): pixels.extend(row[x*4:x*4+3])
        else:
            if palette is None: raise ValueError("Missing PNG palette")
            for x in range(width):
                bit = x*depth
                index = (row[bit//8] >> (8-depth-bit%8)) & ((1<<depth)-1)
                pixels.extend(palette[index*3:index*3+3])
        previous = row
    return width,height,bytes(pixels)


def write_rgb(path,width,height,pixels):
    if len(pixels) != width*height*3:
        raise ValueError("Incorrect RGB pixel count")
    def chunk(kind,payload):
        return struct.pack(">I",len(payload))+kind+payload+struct.pack(">I",zlib.crc32(kind+payload)&0xffffffff)
    scanlines = b"".join(b"\0"+pixels[y*width*3:(y+1)*width*3] for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",width,height,8,2,0,0,0))+
                     chunk(b"IDAT",zlib.compress(scanlines))+chunk(b"IEND",b""))
