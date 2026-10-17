"""Standalone block checks invoked only through the staged-build snapshot."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from coretools import core_root, NO_WINDOW
from hwlock import require_no_jtag


CHECKS = {
    "audio_rom_transport": (0, ("rabbitpunch_audio_rom_transport", "rabbitpunch_audio_roms", "rabbitpunch_rom_cache", "rabbitpunch_read_arbiter")),
    "audio": (19403, ("rabbitpunch_audio", "rabbitpunch_sound_board", "rabbitpunch_adpcm", "jt51", "jt7759")),
    "adpcm": (0, ("rabbitpunch_adpcm", "rabbitpunch_upd7759", "jt7759_ctrl", "jt7759_adpcm")),
    "sound_board": (19403, ("rabbitpunch_sound_board", "rabbitpunch_soundcpu", "rabbitpunch_sound_bus", "rabbitpunch_ram8", "jt51")),
    "soundcpu": (0, ("rabbitpunch_soundcpu", "rabbitpunch_z80", "T80se")),
    "system": (927339, ("rabbitpunch_system", "rabbitpunch_board", "fx68k", "rabbitpunch_roms", "rabbitpunch_download", "jtframe_draw", "rabbitpunch_audio", "T80se", "jt51", "jt7759")),
    "download": (0, ("rabbitpunch_download",)),
    # Native RAM/lines 868352 + micro ROM 17*1024 + nano ROM 66*336.
    # Nano bits 2 and 23 are constant zero in the pinned donor and optimized out.
    "board": (907936, ("rabbitpunch_board", "rabbitpunch_maincpu", "fx68k", "rabbitpunch_io", "rabbitpunch_irq", "rabbitpunch_board_video", "jtframe_draw")),
    "roms": (0, ("rabbitpunch_roms", "rabbitpunch_rom_cache", "rabbitpunch_rom_requests", "rabbitpunch_sdram")),
    "rom_cache": (0, ("rabbitpunch_rom_cache",)),
    "rom_requests": (0, ("rabbitpunch_rom_requests",)),
    "sdram": (0, ("rabbitpunch_sdram", "sdram:memory_controller")),
    "memory": (835584, ("bitmap", "sprites", "tiles", "palette", "work_ram")),
    "tiles": (0, ("rabbitpunch_tile_lookup", "rabbitpunch_tile_row", "jtframe_draw")),
    "sprites": (0, ("rabbitpunch_sprite_row", "jtframe_draw")),
    "sprite_scan": (0, ("rabbitpunch_sprite_scan",)),
    "priority": (0, ("rabbitpunch_sprite_priority", "rabbitpunch_pixel_mixer")),
    "sprite_line": (16384, ("rabbitpunch_sprite_line", "rabbitpunch_sprite_priority", "line_ram")),
    "sprite_renderer": (16384, ("rabbitpunch_sprites", "rabbitpunch_sprite_scan", "rabbitpunch_sprite_row",
                               "rabbitpunch_sprite_line", "jtframe_draw")),
    "tile_line": (16384, ("rabbitpunch_tiles", "rabbitpunch_tile_layer", "line_ram", "jtframe_draw")),
    "video": (32768, ("rabbitpunch_video", "rabbitpunch_tiles", "rabbitpunch_sprites",
                      "rabbitpunch_bitmap_pixel", "rabbitpunch_pixel_mixer", "jtframe_draw")),
    "video_rgb": (32768, ("rabbitpunch_rgb_video", "rabbitpunch_video", "rabbitpunch_palette_pixel",
                          "rabbitpunch_tiles", "rabbitpunch_sprites", "jtframe_draw")),
    "board_video": (868352, ("rabbitpunch_board_video", "rabbitpunch_board_memory", "rabbitpunch_rgb_video",
                            "bitmap", "sprites", "tiles", "palette", "work_ram", "jtframe_draw")),
}


def run_check(stage, quartus_bin, stamp, name):
    expected_bits, required_instances = CHECKS[name]
    project_name=f"{name}_check"
    stage=Path(stage).resolve()
    if stage.parent!=core_root().resolve() or stage.name!="build":
        raise SystemExit("Block checks must run in the core's staged build checkout")
    require_no_jtag(f"Rabbit Punch standalone {name} fit")
    project=stage/"rtl/synth_check"/name
    marker=stage/".build_running"
    log_path=stage/f"q_{project_name}.log"
    scratch=core_root()/".local/quartus"
    env=dict(os.environ)
    # Scope application scratch redirection to this child; the shared JTAG guard
    # above still reads the normal machine-wide marker location.
    for key,folder in (("TEMP","tmp"),("TMP","tmp"),("TMPDIR","tmp"),
                       ("APPDATA","appdata"),("LOCALAPPDATA","localappdata"),
                       ("USERPROFILE","profile")):
        path=scratch/folder
        path.mkdir(parents=True,exist_ok=True)
        env[key]=str(path)
    marker.write_text(stamp,encoding="utf-8")
    try:
        with log_path.open("w",encoding="utf-8") as log:
            result=subprocess.run([str(Path(quartus_bin)/"quartus_sh.exe"),"--flow","compile",project_name],
                                  cwd=project,env=env,stdout=log,stderr=subprocess.STDOUT,**NO_WINDOW)
    finally:
        marker.unlink(missing_ok=True)
    log=log_path.read_text(encoding="utf-8",errors="replace")
    if result.returncode or "Full Compilation was successful" not in log:
        print("\n".join(log.splitlines()[-35:]))
        raise SystemExit(f"Standalone {name} compile failed: {log_path}")
    if name in ("tiles", "sprites", "sprite_renderer", "tile_line", "video", "video_rgb", "board_video", "board", "system"):
        stuck = re.findall(r'Pin "(ou17_(?:(?:sprite|tile)_)?rom_word_address\[\d+\])" is stuck', log)
        if stuck:
            raise SystemExit(f"Unexpected constant graphics ROM address bits: {stuck}")
    output=project/"output_files"
    fit=(output/f"{project_name}.fit.summary").read_text(encoding="utf-8",errors="replace")
    bits=re.search(r"Total block memory bits\s*:\s*([\d,]+)",fit)
    if not bits or int(bits[1].replace(",",""))!=expected_bits:
        raise SystemExit(f"Expected {expected_bits} RAM bits; memory missing, duplicated, or unexpectedly inferred")
    hierarchy=(output/f"{project_name}.map.rpt").read_text(encoding="utf-8",errors="replace")
    if any(instance not in hierarchy for instance in required_instances):
        raise SystemExit("A required block disappeared during synthesis")
    sound_memory = []
    if name in ("sound_board", "audio", "system"):
        expected_sound_memory = {
            "rabbitpunch_ram8:sound_ram": (2048, 8),
            "jt51_sh:u_acc": (8, 68),
            "jt51_sh:out_padding": (3, 15),
            "jt51_sh:u_eg1sh": (27, 10),
            "jt51_sh:u_statesh": (28, 2),
            "jt51_sh:u_reg1op": (32, 45),
            "altshift_taps:eg_VIII_rtl_0": (4, 21),
            "jt51_sh:u_phsh": (29, 20),
        }
        for line in hierarchy.splitlines():
            columns = [value.strip() for value in line.split(";")[1:-1]]
            if len(columns) == 9 and columns[1] in ("M10K block", "AUTO"):
                matches = [key for key in expected_sound_memory if key + "|" in columns[0]]
                if not matches and name == "system":
                    continue
                if len(matches) != 1:
                    raise SystemExit(f"Unexpected sound memory: {columns[0]}")
                key = matches[0]
                depth, width = int(columns[3]), int(columns[4])
                if (depth, width) != expected_sound_memory[key] or int(columns[7]) != depth * width:
                    raise SystemExit(f"Sound memory geometry changed: {key}")
                sound_memory.append(dict(instance=key, depth=depth, width=width, bits=depth*width))
        if len(sound_memory) != len(expected_sound_memory) or len({row["instance"] for row in sound_memory}) != len(expected_sound_memory):
            raise SystemExit("Sound memory missing or duplicated")
    summary=(output/f"{project_name}.sta.summary").read_text(encoding="utf-8",errors="replace")
    timings=[]
    for block in summary.split("\n\n"):
        kind=re.search(r"Type\s*:\s*(.+)",block)
        slack=re.search(r"Slack\s*:\s*(-?[\d.]+)",block)
        if kind and slack:
            timings.append({"type":kind[1].strip(),"slack_ns":float(slack[1])})
    if not timings or any(item["slack_ns"]<0 for item in timings):
        raise SystemExit(f"Block timing not verified or negative: {timings}")
    detail=(output/f"{project_name}.sta.rpt").read_text(encoding="utf-8",errors="replace")
    coverage={name.strip():{"setup":int(setup),"hold":int(hold)}
              for name,setup,hold in re.findall(
                  r";\s*(Illegal Clocks|Unconstrained [^;]+?)\s*;\s*(\d+)\s*;\s*(\d+)\s*;",detail)}
    if len(coverage)!=6 or any(count for row in coverage.values() for count in row.values()):
        raise SystemExit(f"Illegal clocks or unconstrained timing paths: {coverage}")
    assignments=(project/f"{project_name}.qsf").read_text(encoding="utf-8")
    seed_match=re.search(r"(?m)^set_global_assignment -name SEED (\d+)\s*$",assignments)
    if not seed_match:
        raise SystemExit("Isolated project must pin a fitter seed")
    scope = ("Standalone board/video logic with same-clock launch/capture registers; "
             "synthetic virtual inputs change at half a clock period, outputs use zero delay; "
             "all DUT paths remain single-cycle timed, no false/multicycle paths; "
             "not final MiSTer pin/PLL/SDRAM timing") if name in ("board_video", "board", "download", "soundcpu", "sound_board", "adpcm", "audio", "audio_rom_transport") else (
             f"Standalone {name} block with virtual I/O; not a complete core or hardware release")
    if name in ("rom_requests", "rom_cache"):
        scope = "ROM request logic with wire-only port flattening and half-period synthetic virtual input timing; not a final core or external pin proof"
    if name in ("sdram", "roms"):
        scope = ("SDRAM adapter/controller with registered synthetic tester and hypothetical half-period DQ input timing; "
                 "physical pin placement checked, no final PLL/SDRAM clock/PCB electrical timing proof")
    if name == "roms":
        scope = ("Production cached ROM subsystem and word loader with half-period synthetic virtual-input/DQ tester timing; "
                 "no evaluation registers added; not final PLL, HPS download or electrical timing proof")
    if name == "system":
        scope = ("Logical CPU/IO/video/RAM system, sequential loader and cached SDRAM controller; "
                 "registered logical test boundaries, wire-connected SDRAM pins and hypothetical half-period external tester; "
                 "no HPS/DDR, final PCM mixing, PLL/raster or PCB electrical timing proof")
    report={"commit":stamp.split()[0],"device":"5CSEBA6U23I7","project":project_name,
            "constraint_mhz":48,"seed":int(seed_match[1]),"memory_bits":expected_bits,"timings":timings,
            "timing_coverage":coverage,
            "fit_summary":fit.splitlines(),"log_sha256":hashlib.sha256(log_path.read_bytes()).hexdigest(),
            "scope":scope}
    if sound_memory:
        report["sound_memory"] = sound_memory
    destination=core_root()/f"debug/{name}_synth.json"
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(f"PASS standalone {name} fit: {expected_bits} RAM bits; all reported timing checks nonnegative")
    print(destination)
    return 0
