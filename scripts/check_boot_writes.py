"""Compare a bounded real-ROM boot prefix against independent MAME write taps."""
import argparse
import hashlib
import json
import os
import subprocess
import xml.etree.ElementTree as ET

from coretools import core_root, mame_exe, mame_src, mame_version, NO_WINDOW
from mame_capture import mame_cmd, lua_runner_env, check_lua_error
from run_baselines import run_case


def reference_io_state(writes):
    """Reconstruct write-only state from MAME taps using the pinned driver semantics."""
    state = dict(flags=0, scroll0_y=0, scroll0_x=0, scroll1_y=0, scroll1_x=0,
                 sprite_count=0, sprite_priority=0, gga_selected=0)
    state.update({f"gga{index:02x}": 0 for index in range(16)})
    scroll = ("scroll0_y", "scroll0_x", "scroll1_y", "scroll1_x")
    for address, mask, data in writes:
        address &= 0xffffe
        if address == 0xc000c:
            state["flags"] = (state["flags"] & (~mask & 65535)) | (data & mask)
        elif 0xc0000 <= address <= 0xc0006 and mask == 65535:
            state[scroll[(address-0xc0000)//2]] = data & 511
        elif mask & 255:
            if address == 0xc0028:
                state["gga_selected"] = data & 15
            elif address == 0xc0008:
                state[f"gga{state['gga_selected']:02x}"] = data & 255
            elif address == 0xc0010:
                state["sprite_count"] = data & 63
            elif address == 0xc0012:
                state["sprite_priority"] = data & 63
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--writes", type=int, default=10000)
    args = parser.parse_args()
    if args.writes < 1:
        parser.error("--writes must be positive")
    root = core_root()
    version = mame_version()
    if version != "0289":
        raise SystemExit(f"Reference captures require pinned MAME 0289, got {version}")
    manifest = json.loads((root / "docs/reference/rom_manifest.json").read_text(encoding="utf-8"))
    if hashlib.sha256(mame_src().read_bytes()).hexdigest() != manifest["sources"]["rpunch.cpp"]:
        raise SystemExit("Reference driver changed; regenerate manifests before comparing")
    reports = []
    for game in ("rabiolep", "rpunch"):
        out = root / "debug/boot_writes" / game
        out.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, **lua_runner_env("boot_writes.lua"),
                   CORE_OUT=out.as_posix(), BOOT_WRITES=str(args.writes))
        with (out / "mame.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(mame_cmd(mame_exe(), game, "boot_writes.lua", mame_exe().parent,
                                ["-seconds_to_run", "3", "-cfg_directory", str(out / "cfg"),
                                 "-nvram_directory", str(out / "nvram")]),
                                cwd=mame_exe().parent, env=env, stdout=log, stderr=log, text=True,
                                timeout=30, **NO_WINDOW)
        output = (out / "mame.log").read_text(encoding="utf-8")
        check_lua_error(out)
        if result.returncode or f"BOOT_WRITES_OK writes={args.writes} " not in output:
            raise SystemExit(f"{game}: incomplete MAME reset trace; see {out / 'mame.log'}")
        rom = (root / "debug/rom_regions" / game / "maincpu.bin").read_bytes()
        vectors = [tuple(int(x, 16) for x in line.split())
                   for line in (out / "mame_vectors.txt").read_text().splitlines()]
        reset_vectors = [(offset, 65535, int.from_bytes(rom[offset:offset+2], "big"))
                         for offset in range(0, 8, 2)]
        if vectors[:4] != reset_vectors:
            raise SystemExit(f"{game}: trace does not start at the reset vectors: {vectors[:4]}")
        run_dir = root / "debug/baselines" / ("boot_" + game)
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / "program.hex").write_text(
            "\n".join(rom[i:i+2].hex() for i in range(0, len(rom), 2)) + "\n", encoding="ascii")
        mra_path = next(path for path in (root / "releases/_dev").glob("*.mra")
                        if ET.parse(path).findtext("setname") == game)
        dip_bytes = ET.parse(mra_path).find("switches").get("default").split(",")
        dip_default = int(dip_bytes[0], 16) | (int(dip_bytes[1], 16) << 8)
        run_case("boot_" + game, ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv",
                    "rtl/cpu/fx68k/uaddrPla.sv", "rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                    "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_memory.vhd", "rtl/rabbitpunch_bus.vhd",
                    "rtl/rabbitpunch_fx68k.vhd", "rtl/rabbitpunch_maincpu.vhd", "rtl/rabbitpunch_io.vhd",
                    "rtl/rabbitpunch_irq.vhd", "sim/board/boot_writes_tb.sv"],
                 "boot_writes_tb", "100 ms", "BOOT_PREFIX_COMPLETE",
                 # Native altsyncram models are slower than inferred RAM in ModelSim.
                 # Keep the simulated duration and complete ordered-write check unchanged.
                 [f"+BOOT_WRITES={args.writes}", f"+DSW={dip_default:04x}"], wall_timeout=900)
        expected = [tuple(int(x, 16) for x in line.split())
                    for line in (out / "mame_writes.txt").read_text().splitlines()]
        actual = [tuple(int(x, 16) for x in line.split())
                  for line in (run_dir / "rtl_writes.txt").read_text().splitlines()]
        if len(expected) != args.writes or actual != expected:
            mismatch = next((i for i, pair in enumerate(zip(expected, actual)) if pair[0] != pair[1]),
                            min(len(expected), len(actual)))
            raise SystemExit(f"{game}: write mismatch #{mismatch}: "
                             f"MAME {expected[mismatch:mismatch+1]}, RTL {actual[mismatch:mismatch+1]}")
        actual_state = {key: int(value, 16) for key, value in
                        (line.split() for line in (run_dir / "rtl_io_state.txt").read_text().splitlines())}
        expected_state = reference_io_state(expected)
        if actual_state != expected_state:
            raise SystemExit(f"{game}: IO state mismatch: expected {expected_state}, actual {actual_state}")
        reports.append({"set": game, "mameversion": version,
                        "writes_compared": len(actual), "comparison": "identical",
                        "maincpu_sha256": hashlib.sha256(rom).hexdigest(),
                        "mame_trace_sha256": hashlib.sha256((out / "mame_writes.txt").read_bytes()).hexdigest(),
                        "rtl_trace_sha256": hashlib.sha256((run_dir / "rtl_writes.txt").read_bytes()).hexdigest(),
                        "dip_default": f"{dip_default:04x}",
                        "io_state": "identical to state reconstructed from MAME writes",
                        "io_state_fields": len(actual_state),
                        "scope": "Early reset prefix with actual VHDL RAM and board IO; behavioral ROM transport, no raster event generation or sound CPU"})
        print(f"PASS {game}: first {len(actual)} writes and {len(actual_state)} IO state fields match MAME")
    (root / "docs/reference/boot_checks.json").write_text(json.dumps(reports, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
