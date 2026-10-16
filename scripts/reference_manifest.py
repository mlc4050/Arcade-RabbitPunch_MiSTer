"""Export source ROM records and hashes, preserving this driver's ROM_FILL.

This is scoped to rpunch.cpp, not a general-purpose MAME macro parser.
No ROM content is written. Unsupported records and out-of-range loads fail closed.
"""
import hashlib
import json
from pathlib import Path
import re

from coretools import core_root, mame_src
from extract_romstart import blocks, region_records


def main():
    driver = Path(mame_src())
    source = driver.read_text(encoding="utf-8")
    sets = {}
    for name in ("rabiolep", "rpunch"):
        body = blocks(source)[name]
        regions = []
        headers = list(re.finditer(
            r'ROM_REGION\(\s*(0x[\da-fA-F]+),\s*"([^"]+)",\s*([^)]*)\)', body))
        for index, match in enumerate(headers):
            size = int(match[1], 16)
            tag = match[2]
            end = headers[index + 1].start() if index + 1 < len(headers) else len(body)
            section = body[match.start():end]
            records, unknown = region_records(section, tag)
            fills = []
            for line in unknown:
                fill = re.fullmatch(
                    r'ROM_FILL\(\s*(0x[\da-fA-F]+),\s*(0x[\da-fA-F]+),\s*(0x[\da-fA-F]+)\s*\)', line)
                if not fill:
                    raise ValueError(f"{name}/{tag}: unsupported record: {line}")
                offset, length, value = (int(v, 16) for v in fill.groups())
                if offset + length > size or not 0 <= value <= 255:
                    raise ValueError(f"{name}/{tag}: invalid fill")
                fills.append({"offset": offset, "length": length, "value": value})
            loads = []
            for kind, filename, offset, length, crc in records:
                if kind not in ("load", "load16_byte") or crc is None or length <= 0:
                    raise ValueError(f"{name}/{tag}: unsupported load: {kind}")
                stride = 2 if kind == "load16_byte" else 1
                if offset + (length - 1) * stride >= size:
                    raise ValueError(f"{name}/{tag}: load exceeds region: {filename}")
                loads.append({"kind": kind, "file": filename, "offset": offset,
                              "length": length, "crc32": f"{crc:08x}"})
            regions.append({"tag": tag, "size": size, "flags": match[3].strip(),
                            "loads": loads, "fills": fills})
        sets[name] = {"declared_bytes": sum(r["size"] for r in regions),
                      "loaded_bytes": sum(l["length"] for r in regions for l in r["loads"]),
                      "regions": regions}
    files = [driver, driver.with_name("vsystem_gga.cpp"), driver.with_name("vsystem_gga.h")]
    manifest = {"schema": 1, "reference_kind": "source-only; not checked against listxml",
                "sources": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                "sets": sets}
    out = core_root() / "docs" / "reference" / "rom_manifest.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    for name, info in sets.items():
        print(f"{name}: {info['declared_bytes']:#x} declared, {info['loaded_bytes']:#x} file-loaded")
    print(out)


if __name__ == "__main__":
    main()
