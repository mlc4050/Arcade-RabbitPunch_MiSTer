"""Run existing VHDL functional tests against Quartus-generated synthesized logic.

First build the selected block through build_staged.py. No RTL implementation
sources are compiled into the gate simulation; only the generated netlist and
existing VHDL stimulus/scoreboard are used. TimeQuest checks routed timing separately.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from coretools import core_root, quartus_bin, NO_WINDOW
from hwlock import require_no_jtag
from run_baselines import run_case


BLOCKS = {
    "sound_board": ("sound_board_netlist_tb", "SOUND_BOARD_PASS", "sim/sound/sound_board_netlist_tb.vhd"),
    "roms": ("roms_tb", "ROMS_PASS", "sim/memory/roms_tb.vhd"),
    "rom_cache": ("rom_cache_tb", "ROM_CACHE_PASS", "sim/memory/rom_cache_tb.vhd"),
    "rom_requests": ("rom_requests_tb", "ROM_REQUESTS_PASS", "sim/memory/rom_requests_tb.vhd"),
    "sdram": ("sdram_tb", "SDRAM_PASS", "sim/memory/sdram_tb.vhd"),
    "tiles": ("tile_layer_tb", "TILE_LAYER_PASS", "sim/video/tile_layer_tb.vhd"),
    "sprites": ("sprite_row_tb", "SPRITE_ROW_PASS", "sim/video/sprite_row_tb.vhd"),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("block", choices=BLOCKS)
    args = parser.parse_args()
    root = core_root()
    require_no_jtag(f"Rabbit Punch {args.block} netlist export and simulation")
    stamp = (root / "build/BUILT_COMMIT").read_text().split()[0]
    fit = json.loads((root / f"debug/{args.block}_synth.json").read_text())
    if fit["commit"] != stamp:
        raise SystemExit("Selected fitted block does not match the current staged snapshot")
    project_name = f"{args.block}_check"
    project = root / "build/rtl/synth_check" / args.block
    destination = root / "debug/netlists" / f"{args.block}_{stamp[:7]}"
    destination.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for key, directory in (("TEMP", "tmp"), ("TMP", "tmp"), ("TMPDIR", "tmp"),
                           ("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"),
                           ("USERPROFILE", "profile")):
        path = root / ".local/quartus" / directory
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    result = subprocess.run([str(quartus_bin(root) / "quartus_eda.exe"), project_name,
                             "--simulation", "--functional=on", "--tool=modelsim", "--format=verilog"],
                            cwd=project, env=env, capture_output=True, text=True, timeout=120, **NO_WINDOW)
    (destination / "export.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise SystemExit(f"Netlist export failed: {destination / 'export.log'}")
    netlist = destination / f"{project_name}.vo"
    shutil.copyfile(project / "simulation/modelsim" / netlist.name, netlist)
    top, marker, bench = BLOCKS[args.block]
    vectors = {}
    if args.block == "sprites":
        case_directory = root / "debug/baselines/gate_sprites"
        case_directory.mkdir(parents=True, exist_ok=True)
        # Reuse the synthetic vectors from the preceding RTL regression.
        for filename in ("count.hex", "rows.hex", "expected.hex", "sprites.hex"):
            source = root / "debug/baselines/video_sprite_row" / filename
            shutil.copyfile(source, case_directory / filename)
            vectors[filename] = hashlib.sha256(source.read_bytes()).hexdigest()
    support = "rtl/rabbitpunch_sdram_types.vhd" if args.block in ("sdram", "rom_requests", "rom_cache", "roms") else "sim/video/tile_test_support.vhd"
    sources = [str(netlist.relative_to(root)).replace("\\", "/")]
    if args.block != "sound_board":
        sources.append(support)
    if args.block in ("sdram", "roms"):
        sources.append("sim/vendor/sdram/sdram_chip_model_wide.sv")
    if args.block == "rom_requests":
        sources += ["rtl/memory/sdram/sdram.sv", "rtl/rabbitpunch_sdram.vhd",
                    "sim/vendor/sdram/sdram_chip_model_wide.sv"]
    sources.append(bench)
    libraries = [item for library in ("cyclonev_ver", "altera_ver", "altera_lnsim_ver", "lpm_ver", "sgate_ver")
                 for item in ("-L", library)]
    check = run_case(f"gate_{args.block}", sources, top, "60 ms", marker,
                     sim_args=libraries, wall_timeout=300)
    check.update(commit=stamp, vectors_sha256=vectors, netlist_sha256=hashlib.sha256(netlist.read_bytes()).hexdigest(),
                 source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
                 log_sha256=hashlib.sha256((root / check["log"]).read_bytes()).hexdigest(),
                 scope="Quartus synthesized functional netlist against existing VHDL tests; no SDF back-annotation, routed timing checked by TimeQuest")
    (root / f"docs/reference/{args.block}_netlist_checks.json").write_text(json.dumps(check, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
