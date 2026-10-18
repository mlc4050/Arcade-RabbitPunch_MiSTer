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
    "frame_publication": ("frame_publication_tb", "FRAME_PUBLICATION_PASS", "sim/video/frame_publication_tb.vhd"),
    "ddr_write_queue": ("ddr_write_queue_tb", "DDR_WRITE_QUEUE_PASS", "sim/video/ddr_write_queue_tb.vhd"),
    "hdmi_rotation": ("hdmi_rotation_tb", "HDMI_ROTATION_PASS", "sim/video/hdmi_rotation_tb.vhd"),
    "crt_adjust": ("crt_adjust_control_tb", "CRT_ADJUST_CONTROL_PASS", "sim/video/crt_adjust_control_tb.vhd"),
    "video_aspect": ("video_aspect_tb", "VIDEO_ASPECT_PASS", "sim/video/video_aspect_tb.vhd"),
    "memory": ("memory_powerup_tb", "MEMORY_POWERUP_PASS", "sim/memory/memory_powerup_tb.vhd"),
    "host": ("host_tb", "HOST_PASS", "sim/board/host_tb.vhd"),
    "audio": ("audio_netlist_tb", "AUDIO_PASS", "sim/sound/audio_netlist_tb.vhd"),
    "adpcm": ("adpcm_netlist_tb", "ADPCM_PASS", "sim/sound/adpcm_netlist_tb.vhd"),
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
    parser.add_argument("--wall-timeout", type=int, default=300, help="Maximum real seconds for the netlist simulation")
    args = parser.parse_args()
    if args.wall_timeout <= 0:
        parser.error("Wall timeout must be positive")
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
    if args.block not in ("frame_publication", "sound_board", "adpcm", "audio", "host", "memory", "video_aspect", "crt_adjust", "hdmi_rotation", "ddr_write_queue"):
        sources.append(support)
    if args.block in ("sdram", "roms"):
        sources.append("sim/vendor/sdram/sdram_chip_model_wide.sv")
    if args.block == "rom_requests":
        sources += ["rtl/memory/sdram/sdram.sv", "rtl/rabbitpunch_sdram.vhd",
                    "sim/vendor/sdram/sdram_chip_model_wide.sv"]
    if args.block == "memory":
        sources.append("rtl/rabbitpunch_layout.vhd")
    if args.block == "host":
        sources.append("rtl/rabbitpunch_config.vhd")
    if args.block == "frame_publication":
        # The fitted entity has its production 62208-pixel constant, not a
        # run-time generic. Keep the behavioral scenario, scale its stimulus.
        template = (root / bench).read_text(encoding="utf-8")
        generic_map = "        generic map (\n            GINT_FRAME_PIXELS => GINT_FRAME_PIXELS\n        )\n"
        assert template.count(generic_map) == 1
        template = template.replace(generic_map, "").replace("GINT_FRAME_PIXELS : positive := 4", "GINT_FRAME_PIXELS : positive := 62208")
        bench = "debug/frame_publication_netlist_tb.vhd"
        (root / bench).write_text(template, encoding="utf-8")
    sources.append(bench)
    libraries = [item for library in ("cyclonev_ver", "altera_ver", "altera_lnsim_ver", "lpm_ver", "sgate_ver")
                 for item in ("-L", library)]
    check = run_case(f"gate_{args.block}", sources, top, "60 ms", marker,
                     sim_args=libraries + (["-gGBOOL_EVALUATION_BOUNDARY=true", "-gGBOOL_EXHAUSTIVE=false"] if args.block == "memory" else []), wall_timeout=args.wall_timeout)
    check.update(commit=stamp, vectors_sha256=vectors, netlist_sha256=hashlib.sha256(netlist.read_bytes()).hexdigest(),
                 source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
                 log_sha256=hashlib.sha256((root / check["log"]).read_bytes()).hexdigest(),
                 scope="Quartus synthesized functional netlist against existing VHDL tests; no SDF back-annotation, routed timing checked by TimeQuest")
    if args.block == "frame_publication":
        check.update(frame_pixels=62208,
                     template_sha256=hashlib.sha256((root / "sim/video/frame_publication_tb.vhd").read_bytes()).hexdigest())
    if args.block == "memory":
        check.update(memory_initialization_addresses=408, memory_initialization_reads=816, exhaustive=False,
                     scope=check["scope"] + "; all five banks: first/last word of every 256-word region through both CPU and inspection, plus masked writes; full-address coverage is RTL only")
    (root / f"docs/reference/{args.block}_netlist_checks.json").write_text(json.dumps(check, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
