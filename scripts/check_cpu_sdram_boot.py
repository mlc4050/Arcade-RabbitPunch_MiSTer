"""Compare executing fx68k boot writes through cached physical SDRAM commands with MAME."""
import argparse
import hashlib
import json
import struct
import xml.etree.ElementTree as ET
from coretools import core_root
from run_baselines import run_case
from check_boot_writes import reference_io_state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=("rabiolep", "rpunch"))
    parser.add_argument("--writes", type=int, default=10000)
    args = parser.parse_args()
    if args.writes < 1 or args.writes > 10000:
        parser.error("Use 1..10000 writes from the existing verified reference prefix")
    root = core_root()
    sources = ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv", "rtl/cpu/fx68k/uaddrPla.sv",
        "rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd", "rtl/rabbitpunch_ram16.vhd",
        "rtl/rabbitpunch_board_memory.vhd", "rtl/rabbitpunch_memory.vhd", "rtl/rabbitpunch_bus.vhd",
        "rtl/rabbitpunch_fx68k.vhd", "rtl/rabbitpunch_maincpu.vhd", "rtl/rabbitpunch_io.vhd",
        "rtl/rabbitpunch_irq.vhd", "rtl/rabbitpunch_sdram_types.vhd", "rtl/memory/sdram/sdram.sv",
        "rtl/rabbitpunch_sdram.vhd", "rtl/rabbitpunch_rom_requests.vhd", "rtl/rabbitpunch_rom_cache.vhd",
        "rtl/rabbitpunch_read_arbiter.vhd", "rtl/rabbitpunch_audio_roms.vhd", "rtl/rabbitpunch_audio_rom_transport.vhd", "rtl/rabbitpunch_roms.vhd", "sim/vendor/sdram/sdram_chip_model_wide.sv", "sim/board/cpu_sdram_boot_tb.vhd"]
    old = {row["set"]: row for row in json.loads((root / "docs/reference/boot_checks.json").read_text())}
    results = []
    for game in ((args.only,) if args.only else ("rabiolep", "rpunch")):
        reference = root / "debug/boot_writes" / game / "mame_writes.txt"
        assert hashlib.sha256(reference.read_bytes()).hexdigest() == old[game]["mame_trace_sha256"]
        expected = [tuple(int(word, 16) for word in line.split()) for line in reference.read_text().splitlines()][:args.writes]
        assert len(expected) == args.writes
        regions = root / "debug/rom_regions" / game
        program = (regions / "maincpu.bin").read_bytes()
        assert hashlib.sha256(program).hexdigest() == old[game]["maincpu_sha256"]
        parts = [(regions / (name + ".bin")).read_bytes() for name in ("maincpu", "audiocpu", "tiles1", "tiles2", "sprites", "upd")]
        assert tuple(map(len, parts)) == (0x40000, 0x10000, 0x80000, 0x80000, 0x80000, 0x40000)
        image = b"".join(parts)
        case = f"cpu_sdram_boot_{game}_{args.writes}"
        directory = root / "debug/baselines" / case
        directory.mkdir(parents=True, exist_ok=True)
        memory_file = directory / "rom_words.mti"
        with memory_file.open("w") as output:
            output.write("// memory data file (do not edit following line - required for mem load use)\n")
            output.write("// instance=/cpu_sdram_boot_tb/chip/mem\n")
            output.write("// format=mti addressradix=h dataradix=h version=1.0 wordsperline=1\n")
            for index, (word,) in enumerate(struct.iter_unpack("<H", image)):
                output.write(f"{index:x}: {word:04x}\n")
        mra = next(ET.parse(path) for path in (root / "releases/_dev").glob("*.mra") if ET.parse(path).findtext("setname") == game)
        dip_bytes = mra.find("switches").get("default").split(",")
        dips = int(dip_bytes[0], 16) | (int(dip_bytes[1], 16) << 8)
        result = run_case(case, sources, "cpu_sdram_boot_tb", "100 ms", "CPU_SDRAM_BOOT_PASS",
            sim_args=(f"-gGINT_WRITE_LIMIT={args.writes}", f"-gGINT_DIP_DEFAULT={dips}"), wall_timeout=900,
            setup_commands=(f"mem load -format mti -infile {{{memory_file.as_posix()}}} /cpu_sdram_boot_tb/chip/mem",))
        actual = [tuple(int(word, 16) for word in line.split()) for line in (directory / "rtl_writes.txt").read_text().splitlines()]
        if actual != expected:
            mismatch = next((index for index, pair in enumerate(zip(expected, actual)) if pair[0] != pair[1]), min(len(expected), len(actual)))
            raise SystemExit(f"{game}: SDRAM boot mismatch #{mismatch}, MAME={expected[mismatch:mismatch+1]}, HDL={actual[mismatch:mismatch+1]}")
        state = {key: int(value, 16) for key, value in (line.split() for line in (directory / "rtl_io_state.txt").read_text().splitlines())}
        assert state == reference_io_state(expected), f"{game}: I/O state mismatch"
        result.update(set=game, writes_compared=len(actual), io_state_fields=len(state), comparison="identical ordered write values and IO state",
            maincpu_sha256=hashlib.sha256(program).hexdigest(), rom_image_sha256=hashlib.sha256(image).hexdigest(),
            mame_trace_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),
            rtl_trace_sha256=hashlib.sha256((directory / "rtl_writes.txt").read_bytes()).hexdigest(),
            source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
            log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
            scope="Executing fx68k at 48 MHz/6 phase cadence, native RAM/IO, production cached ROMs through SDRAM chip commands; direct model ROM preload, no video/raster interrupts or sound CPU")
        results.append(result)
        (root / f"debug/cpu_sdram_boot_{game}_{args.writes}_checks.json").write_text(json.dumps([result], indent=2) + "\n")
        print(f"PASS {game}: {len(actual)} executing-CPU writes through cached SDRAM and all 24 IO fields match MAME", flush=True)
    if not args.only and args.writes == 10000:
        (root / "docs/reference/cpu_sdram_boot_checks.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
