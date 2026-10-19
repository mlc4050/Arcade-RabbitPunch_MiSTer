"""Generate development MRAs and check each ROM stream against source region assembly."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from coretools import core_root, mame_exe, mame_src, mame_version, setting, NO_WINDOW
import extract_dips
import mra
from mame_capture import mame_cmd, lua_runner_env


REGIONS = ("maincpu", "audiocpu", "tiles1", "tiles2", "sprites", "upd")
NAMES = {"rabiolep": "Rabio Lepus (Japan)", "rpunch": "Rabbit Punch (US)"}


def layout():
    text = (core_root() / "rtl/rabbitpunch_layout.vhd").read_text()
    values = {k: int(v, 16) for k, v in re.findall(
        r"constant\s+CINT_(ROM_\w+)\s*:\s*natural\s*:=\s*16#([0-9a-fA-F]+)#", text)}
    cursor = 0
    for tag in REGIONS:
        if values[f"ROM_{tag.upper()}_BASE"] != cursor:
            raise ValueError(f"Noncontiguous ROM layout at {tag}")
        cursor += values[f"ROM_{tag.upper()}_SIZE"]
    if cursor != values["ROM_IMAGE_SIZE"]:
        raise ValueError("ROM_IMAGE_SIZE disagrees with regions")
    return values


def button_names():
    text = (core_root() / "rtl/rabbitpunch_layout.vhd").read_text()
    slots = {name: int(value) for name, value in re.findall(
        r"constant\s+CINT_JOY_(\w+)\s*:\s*natural\s*:=\s*(\d+)", text)}
    labels = {"FIRE_PUNCH": "Fire/Punch", "MISSILE": "Missile", "START": "Start", "COIN": "Coin",
              "PAUSE": "Pause", "SERVICE": "Service", "TEST": "Test"}
    if set(slots) != set(labels) or len(set(slots.values())) != len(slots) or min(slots.values()) < 4:
        raise ValueError("Invalid VHDL joystick slot definitions")
    names = ["-"] * (max(slots.values()) - 3)
    for key, slot in slots.items():
        names[slot - 4] = labels[key]
    return ",".join(names)


def hiscore_metadata(name):
    reference = {row['set']: row for row in json.loads(
        (core_root() / 'docs/reference/hiscore_reference.json').read_text())}
    row = reference[name]
    expected = (0xFFE01, 119, 0, 0x80) if name == 'rabiolep' else (0xFFE01, 115, 0, 0x17)
    actual = tuple(row[key] for key in ('address', 'length', 'first', 'last'))
    if actual != expected or row['mame_version'] != '0289':
        raise ValueError('Score metadata differs from the pinned MAME profile')
    # Clock counts for the 48 MHz logical platform: wait one second, then
    # retry the initialization sentinels at most once per 65536 clocks.
    header = (48_000_000).to_bytes(4, 'big') + bytes.fromhex('FFFF00020002000100000000')
    record = row['address'].to_bytes(4, 'big') + row['length'].to_bytes(2, 'big') + bytes([row['first'], row['last']])
    payload = header + record
    if len(payload) != 24:
        raise ValueError('Score metadata must have one 8-byte length-width-2 record')
    return payload, row['length']


def emit_hiscore(parent, name):
    payload, length = hiscore_metadata(name)
    config = ET.SubElement(parent, 'rom', index='3')
    ET.SubElement(config, 'part').text = payload.hex(' ').upper()
    ET.SubElement(parent, 'nvram', index='4', size=str(length))
    # Main_MiSTer's XML events load each section in document order.
    order = [(node.tag, node.get('index')) for node in parent
             if node.tag in ('rom', 'nvram')]
    if order != [('rom', '0'), ('rom', '3'), ('nvram', '4')]:
        raise ValueError('Expected ROM image, score configuration, then optional NVRAM dump')
    return {'config_index': 3, 'dump_index': 4, 'bytes': length,
            'config_sha256': hashlib.sha256(payload).hexdigest(),
            'load_order': ['rom0', 'config3', 'nvram4']}


def fill(parent, value, length):
    if length:
        ET.SubElement(parent, "part", repeat=hex(length)).text = f"{value:02X}"


def part(parent, record, **attrs):
    return ET.SubElement(parent, "part", name=record["file"], crc=record["crc32"],
                         length=hex(record["length"]), **attrs)


def emit_region(parent, region):
    default = 255 if region["flags"] == "ROMREGION_ERASEFF" else 0
    if region["flags"] not in ("0", "ROMREGION_ERASEFF"):
        raise ValueError(f"Unsupported region flags: {region['flags']}")
    pending = {record["offset"]: record for record in region["loads"]}
    if len(pending) != len(region["loads"]):
        raise ValueError("Duplicate load offsets")
    events = []
    while pending:
        offset = min(pending)
        record = pending.pop(offset)
        if record["kind"] == "load16_byte":
            other = pending.pop(offset + 1, None)
            if offset % 2 or other is None or other["kind"] != "load16_byte" or other["length"] != record["length"]:
                raise ValueError("Unpaired or unequal ROM_LOAD16_BYTE")
            events.append((offset, record["length"] * 2, "pair", (record, other)))
        elif record["kind"] == "load":
            events.append((offset, record["length"], "load", record))
        else:
            raise ValueError(f"Unsupported load kind: {record['kind']}")
    events += [(item["offset"], item["length"], "fill", item["value"]) for item in region["fills"]]
    cursor = 0
    for offset, length, kind, value in sorted(events):
        if offset < cursor or offset + length > region["size"]:
            raise ValueError("Overlapping/out-of-range ROM event")
        fill(parent, default, offset - cursor)
        if kind == "pair":
            group = ET.SubElement(parent, "interleave", output="16")
            part(group, value[0], map="01")
            part(group, value[1], map="10")
        elif kind == "load":
            part(parent, value)
        else:
            fill(parent, value, length)
        cursor = offset + length
    fill(parent, default, region["size"] - cursor)


def source_image(regions, archives):
    """Address-based assembly, independent of the sequential XML emitter."""
    images = []
    with zipfile.ZipFile(archives[0]) as archive:
        for region in regions:
            image = bytearray([255 if region["flags"] == "ROMREGION_ERASEFF" else 0]) * region["size"]
            for record in region["loads"]:
                payload = mra._zip_read(archive, record["file"], record["crc32"])
                if len(payload) != record["length"]:
                    raise ValueError(f"ROM size mismatch: {record['file']}")
                stride = 2 if record["kind"] == "load16_byte" else 1
                start = record["offset"]
                image[start:start + len(payload)*stride:stride] = payload
            for item in region["fills"]:
                image[item["offset"]:item["offset"]+item["length"]] = bytes([item["value"]]) * item["length"]
            images.append(bytes(image))
    return b"".join(images)


def switches(parent, name, driver):
    blocks = extract_dips.blocks(driver)
    missing = set()
    dips = extract_dips.parse_ports(blocks[name], blocks, missing)["DSW"]
    if missing:
        raise ValueError(f"Unknown DIP labels: {missing}")
    default = 0
    for _, _, value, _ in dips:
        default |= value
    node = ET.SubElement(parent, "switches", default=f"{default & 255:02X},{default >> 8:02X}", base="0")
    for label, mask, _, settings in dips:
        if settings is None:
            continue
        # US manual plus actual US/Japan ROM accounting establish two omitted values.
        # Preserve each set's MAME defaults and other switches; see MANUAL_DIPS.md.
        if name in ("rpunch", "rabiolep") and label in ("Coin A", "Coin B"):
            shift = 0 if label == "Coin A" else 4
            if mask != (0xF << shift):
                raise ValueError("Manual coinage override no longer matches the driver mask")
            settings = dict(settings)
            for nibble, title in ((1, "1C/1C+2C/3C"), (14, "4C/1C")):
                raw = nibble << shift
                if raw in settings:
                    raise ValueError("MAME now defines a manual coinage override; review it")
                settings[raw] = title
        bits = [i for i in range(16) if mask & (1 << i)]
        ids = []
        for packed in range(1 << len(bits)):
            raw = sum(((packed >> j) & 1) << bit for j, bit in enumerate(bits))
            # Unspecified encodings remain unavailable; verified additions are above.
            ids.append(extract_dips._short(settings.get(raw, "-")))
        if any("," in value for value in ids) or 2 + len(label) + max(map(len, ids)) > 28:
            raise ValueError(f"DIP too wide/invalid for OSD: {label}")
        if bits != list(range(bits[0], bits[-1] + 1)):
            raise ValueError(f"Noncontiguous DIP mask: {label}")
        bit_range = str(bits[0]) if len(bits) == 1 else f"{bits[0]},{bits[-1]}"
        ET.SubElement(node, "dip", name=label, bits=bit_range, ids=",".join(ids))


def main():
    root = core_root()
    manifest = json.loads((root / "docs/reference/rom_manifest.json").read_text())
    driver = mame_src().read_text()
    if hashlib.sha256(mame_src().read_bytes()).hexdigest() != manifest["sources"]["rpunch.cpp"]:
        raise SystemExit("Driver changed; regenerate reference_manifest.py first")
    version = mame_version()
    if not version:
        raise SystemExit("MAME executable version could not be read")
    sizes = layout()
    rompaths = [Path(value) for value in setting("MAME_ROMPATH", "").split(";") if value]
    archives = [path / "rabiolep.zip" for path in rompaths if (path / "rabiolep.zip").exists()]
    if not archives:
        raise SystemExit("Merged rabiolep.zip not found in MAME_ROMPATH")
    out = root / "releases"
    out.mkdir(parents=True, exist_ok=True)
    reports = []
    for name, title in NAMES.items():
        xml = subprocess.check_output([str(mame_exe()), "-listxml", name], **NO_WINDOW)
        info = ET.fromstring(xml).find(f"machine[@name='{name}']")
        regions = {item["tag"]: item for item in manifest["sets"][name]["regions"]}
        ordered = [regions[tag] for tag in REGIONS]
        for tag in REGIONS:
            if regions[tag]["size"] != sizes[f"ROM_{tag.upper()}_SIZE"]:
                raise ValueError(f"VHDL/source size mismatch: {name}/{tag}")
        for region in ordered:
            for load in region["loads"]:
                if not any(item.get("crc") == load["crc32"] and int(item.get("size", "0")) == load["length"]
                           and item.get("region") == region["tag"] for item in info.findall("rom")):
                    raise ValueError(f"Source/listxml mismatch: {name}/{load['file']}")
        doc = ET.Element("misterromdescription")
        for tag, value in (("name", title), ("setname", name), ("rbf", "RabbitPunch"),
                           ("mameversion", version), ("year", info.findtext("year")),
                           ("manufacturer", info.findtext("manufacturer")),
                           ("rotation", "horizontal"), ("players", "2"),
                           ("about", "Development ROM/control definition; no playable core release yet.")):
            ET.SubElement(doc, tag).text = value
        ET.SubElement(doc, "joystick", ways="8")
        rom = ET.SubElement(doc, "rom", index="0", zip="rabiolep.zip" if name == "rabiolep" else "rpunch.zip|rabiolep.zip", md5="None")
        for region in ordered:
            emit_region(rom, region)
        hiscore = emit_hiscore(doc, name)
        switches(doc, name, driver)
        ET.SubElement(doc, "buttons", names=button_names(), count="2")
        ET.indent(doc, space="    ")
        path = out / (title + ".mra")
        ET.ElementTree(doc).write(path, encoding="utf-8", xml_declaration=True)
        actual = mra.build_image(path, archives[:1], size=sizes["ROM_IMAGE_SIZE"])
        expected = source_image(ordered, archives[:1])
        if actual != expected:
            raise ValueError(f"MRA/source ROM image mismatch: {name}")
        dump_dir = root / "debug/rom_regions" / name
        dump_dir.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, **lua_runner_env("check_rom_regions.lua"),
                   ROMCHECK_OUT=dump_dir.as_posix(), CORE_OUT=dump_dir.as_posix())
        run = subprocess.run(mame_cmd(mame_exe(), name, "check_rom_regions.lua", mame_exe().parent,
                                      ["-seconds_to_run", "3"]),
                             cwd=mame_exe().parent, env=env, capture_output=True, text=True,
                             timeout=60, **NO_WINDOW)
        if run.returncode or "ROM_REGIONS_OK" not in run.stdout:
            raise ValueError("MAME ROM-region dump failed: " + run.stdout + run.stderr)
        mame_image = b"".join((dump_dir / (tag + ".bin")).read_bytes() for tag in REGIONS)
        if actual != mame_image:
            mismatch = next((i for i, (a, b) in enumerate(zip(actual, mame_image)) if a != b), None)
            raise ValueError(f"MRA/emulator ROM image mismatch: {name}, first offset {mismatch}, "
                             f"sizes {len(actual)}/{len(mame_image)}")
        report = {"set": name, "mameversion": version, "bytes": len(actual),
                  "sha256": hashlib.sha256(actual).hexdigest(), "source_and_listxml_checked": True,
                  "xml_vs_address_assembly": "identical", "xml_vs_mame_regions": "identical",
                  "mra": path.relative_to(root).as_posix(), "hiscore": hiscore}
        reports.append(report)
        print(f"PASS {name}: {len(actual):#x} bytes; MRA matches source assembly and actual MAME regions")
    (root / "docs/reference/mra_checks.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
