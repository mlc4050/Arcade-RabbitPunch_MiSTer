#!/usr/bin/env python3
"""Build Quartus from a staged snapshot of HEAD, leaving the tree free.

A Quartus compile takes minutes, and for all of it the tree has to be left
alone. The compile runs in a dedicated git worktree at <repo>/build
(gitignored), so the main tree is free the moment the build starts, and every
scrap of Quartus scratch -- db/, incremental_db/, output_files/, the log --
lands under build/ instead of the repo root.

The build is exactly HEAD:
  * a dirty tree is refused by default, so what is in the editor and what is
    compiled cannot silently diverge. --allow-dirty builds HEAD anyway,
    explicitly acknowledging the uncommitted edits are EXCLUDED.
  * the built commit is written to build/BUILT_COMMIT beside the log, so
    every .rbf maps to one commit.

    python scripts/build_staged.py                     # compile HEAD, default revision
    python scripts/build_staged.py --rev <project>     # another revision
    python scripts/build_staged.py --seed 12345        # try another placement
    python scripts/build_staged.py --allow-dirty       # HEAD, ignoring edits

The revision defaults to CORE_REV, else the one .qsf, else the last
PROJECT_REVISION in the .qpf (scripts/coretools.py). A core with an
instrumented <project>_stp.qsf (DEBUG_ISSP) and a release <project>.qsf
builds the instrumented one by default when it is listed last.

Outputs, all inside the stage, named after the revision:
    build/q_staged.log                     the build log (deploy.py's gate reads it)
    build/output_files/<rev>.rbf           the bitstream
    build/output_files/<rev>.sta.summary
    build/BUILT_COMMIT                     commit, time and SEED

Deploy it by pointing deploy.py at the stage (its defaults):
    python scripts/deploy.py --rbf-only

The worktree persists between builds -- Quartus's db/ with it -- and each run
hard-resets it to HEAD. A .build_running marker refuses two overlapping
staged builds.

scripts/build.sh still builds in-tree; use it when you want the compile to
see uncommitted work and are willing to leave the tree alone.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coretools import core_root, revision, quartus_bin, NO_WINDOW   # noqa: E402

REV = None          # set in main() from --rev / coretools
QUARTUS_BIN = None

# --- core-specific: edit for this core -------------------------------------
# Every block that MUST survive to the fitted netlist, by the name Quartus
# writes into the fit report. A build that passes timing because part of the
# design was optimised away is the worst kind of green (an undriven clock
# takes a whole video chain out and the build reports TIMING MET). Slack alone
# cannot catch that; presence is asserted separately. Add each name in the
# commit that adds the module it names, so the gate grows with the design.
REQUIRED_INSTANCES = (
    "hps_io", "rabbitpunch_clocked_machine", "rabbitpunch_scanout",
    "rabbitpunch_scanline_scheduler", "rabbitpunch_rom_cache", "fx68k",
    "T80se", "jt51", "jt7759", "jtframe_draw", "rabbitpunch_hiscore_service", "rabbitpunch_video_options",
    "video_mixer", "scandoubler", "Hq2x",
    # "fx68k", "sdram", "arcade_video", "Hq2x", "screen_rotate_two", ...
)

# Macros the design needs defined in the .qsf, and what breaks without each.
# Presence is not connection: a module can stay in the netlist with its ports
# bound to implicitly declared wires because a VERILOG_MACRO went missing.
REQUIRED_MACROS = {
    # "MISTER_FB": "HDMI rotation and 180 flip need the FB_* ports",
}

# Files the compile expects in the project directory that the repo keeps
# elsewhere, copied inside the stage before Quartus runs: (source, destination),
# both relative to the repo root. fx68k's $readmemb looks for its microcode in
# the directory Quartus runs from, not beside the RTL.
STAGE_COPIES = (
    # ("rtl/cpu/fx68k/microrom.mem", "microrom.mem"),
    # ("rtl/cpu/fx68k/nanorom.mem", "nanorom.mem"),
)
# ---------------------------------------------------------------------------


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        sys.exit("FAILED: %s\n%s%s" % (" ".join(cmd), r.stdout, r.stderr))
    return r.stdout.strip()


def read_slacks(summary):
    """Require a timing summary and gate every reported check, including hold."""
    path = Path(summary)
    if not path.is_file():
        raise SystemExit(f"Timing unverified: missing {path}")
    text = path.read_text(errors="replace")
    rows = []
    for block in re.split(r"\n\s*\n", text):
        kind = re.search(r"Type\s*:\s*(.+)", block)
        slack = re.search(r"Slack\s*:\s*(-?[\d.]+)", block)
        tns = re.search(r"TNS\s*:\s*(\S+)", block)
        if kind and slack:
            rows.append((kind[1].strip(), float(slack[1]), tns[1] if tns else "unknown"))
    if not rows or not all(any(check in name for name, _, _ in rows)
                           for check in ("Setup", "Hold", "Minimum Pulse Width")):
        raise SystemExit("Timing unverified: setup, hold or minimum pulse width missing")
    print(f"  {len(rows)} timing checks inspected, including setup/hold and pulse width")
    return [(name[-100:], slack, tns) for name, slack, tns in rows if slack < 0]


def check_timing_coverage(report, framework_scope=None, stage=None, revision=None):
    """Fail closed when illegal/unconstrained paths remain or the table is absent."""
    path = Path(report)
    if not path.is_file():
        raise SystemExit(f"Timing coverage unverified: missing {path}")
    rows = re.findall(r";\s*(Illegal Clocks|Unconstrained [^;]+?)\s*;\s*(\d+)\s*;\s*(\d+)\s*;",
                      path.read_text(errors="replace"))
    expected = {"Illegal Clocks", "Unconstrained Clocks", "Unconstrained Input Ports",
                "Unconstrained Input Port Paths", "Unconstrained Output Ports",
                "Unconstrained Output Port Paths"}
    if {name.strip() for name, _, _ in rows} != expected:
        raise SystemExit("Timing coverage unverified: expected all six coverage categories")
    bad = [(name.strip(), int(setup), int(hold)) for name, setup, hold in rows
           if int(setup) or int(hold)]
    if bad and framework_scope is not None:
        # Retain inherited framework I/O gaps as visible, source-locked scope.
        # Never turn these into broad false paths or exempt clocks/core/SDRAM.
        if stage is None:
            raise SystemExit("Framework coverage scope requires the fitted stage")
        scope = json.loads(Path(framework_scope).read_text())
        for name, expected_hash in scope["source_sha256"].items():
            actual = hashlib.sha256((Path(stage) / name).read_text().encode()).hexdigest()
            if actual != expected_hash:
                raise SystemExit(f"Framework timing scope source changed: {name}")
        if any("Clocks" in name for name, _, _ in bad):
            raise SystemExit(f"Illegal or unconstrained clocks: {bad}")
        debug_scope = None
        if revision is not None and revision.endswith("_stp"):
            qsf = (Path(stage) / f"{revision}.qsf").read_text()
            if not re.search(r'^set_global_assignment -name VERILOG_MACRO "DEBUG_ISSP=1"', qsf, re.M):
                raise SystemExit("Reserved JTAG scope requires the instrumented revision macro")
            debug_scope = scope["instrumented_jtag"]
            for name, expected_hash in debug_scope["source_sha256"].items():
                actual = hashlib.sha256((Path(stage) / name).read_text().encode()).hexdigest()
                if actual != expected_hash:
                    raise SystemExit(f"Instrumented JTAG scope source changed: {name}")
        ports = {"inputs": set(), "outputs": set()}
        direction = None
        for line in path.read_text(errors="replace").splitlines():
            if re.match(r"^;\s*Unconstrained Input Ports\s*;", line):
                direction = "inputs"
            elif re.match(r"^;\s*Unconstrained Output Ports\s*;", line):
                direction = "outputs"
            match = re.match(r"^;\s*([^;]+?)\s*;\s*(No (?:input|output) delay[^;]+|Partially constrained)\s*;", line)
            if match and direction:
                ports[direction].add(match[1].strip())
        for key in ports:
            allowed = set(scope["input_ports" if key == "inputs" else "output_ports"])
            if debug_scope is not None:
                allowed.update(debug_scope["input_ports" if key == "inputs" else "output_ports"])
            if not ports[key] or not ports[key] <= allowed:
                raise SystemExit(f"Unexpected untimed {key}: {sorted(ports[key] - allowed)}")
        categories = {name.strip(): (int(setup), int(hold)) for name, setup, hold in rows}
        for label, key in (("Input", "inputs"), ("Output", "outputs")):
            count = len(ports[key])
            if categories[f"Unconstrained {label} Ports"] != (count, count):
                raise SystemExit(f"Untimed {key} count disagrees with enumerated framework ports")
            setup, hold = categories[f"Unconstrained {label} Port Paths"]
            maximum = dict(scope["maximum_unconstrained_paths"])
            if debug_scope is not None:
                for name, extra in debug_scope["additional_unconstrained_paths"].items():
                    maximum[name] += extra
            if (setup > maximum[f"setup_{label.lower()}"] or
                    hold > maximum[f"hold_{label.lower()}"]):
                raise SystemExit(f"Framework untimed path count increased: {label}")
        destination = Path(stage) / "output_files/framework_timing_scope.json"
        destination.write_text(json.dumps(dict(scope=scope["scope"], input_ports=sorted(ports["inputs"]),
            output_ports=sorted(ports["outputs"]), raw_coverage=categories,
            instrumented_jtag_scope=debug_scope["scope"] if debug_scope else None), indent=2) + "\n")
        print(f"  clocks/core/SDRAM covered; framework/debug pin gaps retained: {len(ports['inputs'])} inputs, {len(ports['outputs'])} outputs")
        print("  HDMI/audio/SD/I2C and reserved JTAG pin electrical timing are outside this scoped gate")
    elif bad:
        raise SystemExit(f"Illegal clocks or unconstrained timing paths: {bad}")
    else:
        print("  all six timing-coverage categories clear")


def report_resources(stage):
    fit = os.path.join(stage, "output_files", "%s.fit.summary" % REV)
    if not os.path.exists(fit):
        return
    keep = ("Logic utilization", "Total registers", "Total block memory bits",
            "Total RAM Blocks", "Total DSP Blocks", "Total pins", "Total PLLs")
    for ln in open(fit, errors="replace"):
        if any(ln.strip().startswith(k) for k in keep):
            print("  " + ln.strip())


def check_macros(stage):
    """Fail if a required VERILOG_MACRO is missing or commented out."""
    qsf = os.path.join(stage, "%s.qsf" % REV)
    try:
        with open(qsf, encoding="utf8", errors="replace") as f:
            live = [ln for ln in f if not ln.lstrip().startswith("#")]
    except OSError as e:
        return ["cannot read %s: %s" % (qsf, e)]
    text = "".join(live)
    return ['%s is not defined in %s -- %s' % (m, os.path.basename(qsf), why)
            for m, why in REQUIRED_MACROS.items()
            if 'VERILOG_MACRO "%s=' % m not in text]


def check_present(stage):
    """Fail if a block that must exist is missing from the fitted netlist."""
    rpt = os.path.join(stage, "output_files", "%s.fit.rpt" % REV)
    try:
        text = open(rpt, errors="replace").read()
    except OSError:
        print("  (no fit report at %s -- cannot check)" % rpt)
        return []
    required = REQUIRED_INSTANCES + (("rabbitpunch_debug", "altsource_probe") if REV.endswith("_stp") else ())
    missing = [n for n in required if n not in text]
    for n in required:
        print("  %-18s %s" % (n, "present" if n in text else "MISSING"))
    return missing


def clear_stale_bitstreams(stage, rev):
    """A failed compile must not leave a previous bitstream looking current."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", rev):
        raise SystemExit("Invalid staged revision name")
    stage = Path(stage).resolve()
    output = stage / "output_files"
    if not output.exists():
        return
    if output.resolve().parent != stage:
        raise SystemExit("Staged output directory resolves outside the build")
    for suffix in ("rbf", "sof"):
        artifact = output / f"{rev}.{suffix}"
        if artifact.exists():
            if artifact.resolve().parent != output.resolve():
                raise SystemExit("Staged bitstream resolves outside the output directory")
            artifact.unlink()


def quartus_child_environment(root):
    env = dict(os.environ)
    scratch = Path(root) / ".local/quartus"
    for key, folder in (("TEMP", "tmp"), ("TMP", "tmp"), ("TMPDIR", "tmp"),
                        ("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"),
                        ("USERPROFILE", "profile")):
        path = scratch / folder
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    return env


def inspect_full_clock_tree(stage, quartus_tools, rev):
    """Verify the fitted game PLL and forwarded pin, without changing assignments."""
    from hwlock import require_no_jtag
    require_no_jtag("fitted full-shell clock inspection")
    stage = Path(stage).resolve()
    script = Path(__file__).with_name("inspect_clock_tree.tcl")
    output = stage / "output_files"
    log_path = output / "full_clock_tree.log"
    with log_path.open("w") as log:
        result = subprocess.run([str(Path(quartus_tools) / "quartus_sta.exe"), "-t", str(script), rev],
            cwd=stage, env=quartus_child_environment(stage.parent), stdout=log,
            stderr=subprocess.STDOUT, **NO_WINDOW)
    if result.returncode:
        raise SystemExit(f"Full fitted clock-tree inspection failed: {log_path}")
    rows = []
    for line in (output / "clock_tree.tsv").read_text().splitlines()[1:]:
        name, period, rise, fall, positive, negative, multiply, divide = line.split("\t")
        rows.append(dict(name=name, period_ns=float(period), rise_ns=float(rise), fall_ns=float(fall),
            positive_timing_endpoints=int(positive), negative_timing_endpoints=int(negative),
            multiply_by=int(multiply), divide_by=int(divide)))
    game = [row for row in rows if "|machine|pll|clock_generator|" in row["name"]]
    system = [row for row in game if abs(row["period_ns"] - 150 / 7) < 0.002 and abs(row["rise_ns"]) < 0.03]
    shifted = [row for row in game if abs(row["period_ns"] - 150 / 7) < 0.002 and abs(row["rise_ns"] - 5.357) < 0.03]
    vco = [row for row in game if "vcoph" in row["name"]]
    exported = [row for row in rows if row["name"] == "sdram_pin"]
    reference = [row for row in rows if row["name"] == "FPGA_CLK2_50" and abs(row["period_ns"] - 20) < 0.002]
    if not (len(game) == 3 and len(system) == len(shifted) == len(vco) == len(exported) == len(reference) == 1):
        raise SystemExit(f"Unexpected game PLL clock topology: {game}")
    if (abs(exported[0]["rise_ns"] - 5.357) > 0.03 or abs(exported[0]["period_ns"] - 150 / 7) > 0.002 or
            system[0]["positive_timing_endpoints"] < 100 or
            shifted[0]["positive_timing_endpoints"] != 1 or shifted[0]["negative_timing_endpoints"] != 0 or
            exported[0]["positive_timing_endpoints"] != 0 or exported[0]["negative_timing_endpoints"] != 0):
        raise SystemExit("Unexpected game clock users or forwarded SDRAM pin phase")
    frequencies = [50_000_000 * vco[0]["multiply_by"] / vco[0]["divide_by"] *
                   row["multiply_by"] / row["divide_by"] for row in (system[0], shifted[0])]
    if any(abs(frequency - 140_000_000 / 3) > 1 for frequency in frequencies):
        raise SystemExit(f"Fitted game PLL integer ratios changed: {game}")
    report = dict(commit=(stage / "BUILT_COMMIT").read_text().split()[0], revision=rev,
        nominal_game_frequency_hz=frequencies[0], sdram_phase_ns=shifted[0]["rise_ns"], clocks=rows,
        inspector_sha256=hashlib.sha256(script.read_bytes()).hexdigest(),
        validator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        scope="Fitted game PLL ratios, system domain, forwarded quarter-period SDRAM clock and absence of functional users on its shifted output; framework/JTAG clocks remain separate; not an electrical or hardware execution proof")
    (output / "full_clock_tree.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"  fitted game clock {frequencies[0]:.6f} Hz, SDRAM phase {shifted[0]['rise_ns']:.3f} ns")
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--synth-check", choices=["video_options", "clocked_machine", "machine", "raster", "hiscore_service", "hiscore", "maintenance", "video_output", "platform", "controls", "host", "load_frontend", "ddr_copy", "audio_mixer", "audio_rom_transport", "audio", "adpcm", "sound_board", "soundcpu", "memory", "tiles", "sprites", "sprite_scan", "priority", "sprite_line", "sprite_renderer", "tile_line", "video", "video_rgb", "board_video", "board", "download", "system", "sdram", "rom_requests", "rom_cache", "roms"],
                    help="fit an isolated block from HEAD instead of the MiSTer core")
    ap.add_argument("--rev", help="Quartus revision (default: CORE_REV, else the one "
                                  ".qsf in the core root, else the .qpf's last)")
    ap.add_argument("--seed", type=int,
                    help="override the fitter SEED in the STAGED .qsf "
                         "(placement only; worth trying before restructuring "
                         "RTL for a sub-ns violation)")
    ap.add_argument("--allow-negative-slack", action="store_true",
                    help="do not fail on a build that misses timing; the "
                         "shortfall must then be stated wherever it is used")
    ap.add_argument("--allow-dirty", action="store_true",
                    help="build HEAD even though the tree has uncommitted "
                         "changes (they are NOT included in the build)")
    args = ap.parse_args()
    if args.synth_check and (args.seed is not None or args.rev or args.allow_negative_slack):
        ap.error("isolated checks pin their own revision/seed and require nonnegative timing")

    global REV, QUARTUS_BIN
    here = str(core_root())
    REV = f"{args.synth_check}_check" if args.synth_check else revision(Path(here), args.rev)
    QUARTUS_BIN = str(quartus_bin(Path(here)))
    stage = os.path.join(here, "build")

    # scripts/hwlock.py: a compile must not start while a JTAG tool is
    # reading the device. The marker is machine-wide, so this also refuses
    # while another core is probing.
    from hwlock import require_no_jtag
    require_no_jtag("this build")

    dirty = run(["git", "-C", here, "status", "--porcelain"])
    # Untracked files are not part of HEAD either, but they are usually
    # scratch; only tracked modifications are treated as a divergence worth
    # refusing over.
    tracked_dirty = "\n".join(ln for ln in dirty.splitlines()
                              if not ln.startswith("??"))
    if tracked_dirty and not args.allow_dirty:
        sys.exit("tree is dirty -- commit first (the build is exactly HEAD), "
                 "or pass --allow-dirty to build HEAD without these:\n"
                 + tracked_dirty)

    head = run(["git", "-C", here, "rev-parse", "HEAD"])
    head_short = run(["git", "-C", here, "rev-parse", "--short", "HEAD"])

    marker = os.path.join(stage, ".build_running")
    if os.path.exists(marker):
        sys.exit("a staged build already appears to be running (%s exists) -- "
                 "wait for it, or delete the marker if it is stale" % marker)

    # Create or update the stage worktree to exactly HEAD.
    if not os.path.isdir(os.path.join(stage, ".git")) and \
       not os.path.isfile(os.path.join(stage, ".git")):
        run(["git", "-C", here, "worktree", "add", "--detach", stage, head])
    else:
        # --force: a seed override patches the STAGED .qsf, and a leftover
        # patch must never wedge the next build. The stage is a disposable
        # copy of HEAD; local changes in it are always discardable.
        run(["git", "-C", stage, "checkout", "--force", "--detach", head])
        run(["git", "-C", stage, "reset", "--hard", head])

    # Fitter seed override, patched into the STAGE only, so a build stays
    # reproducible from its commit plus this flag.
    if args.seed is not None:
        qsf = os.path.join(stage, "%s.qsf" % REV)
        if not os.path.isfile(qsf):
            sys.exit("no %s to patch a SEED into" % qsf)
        text = open(qsf, encoding="utf-8", errors="replace").read()
        new, n = re.subn(r"(?m)^set_global_assignment -name SEED .*$",
                         "set_global_assignment -name SEED %d" % args.seed, text)
        if n == 0:
            new = text.rstrip("\n") + \
                "\nset_global_assignment -name SEED %d\n" % args.seed
        elif n > 1:
            sys.exit("expected at most one SEED assignment in %s, found %d" % (qsf, n))
        open(qsf, "w", encoding="utf-8", newline="\n").write(new)
        print("seed:   %d (stage only)" % args.seed)

    if not args.synth_check:
        # The value is part of this staged snapshot, never a guessed device identity.
        qsf = Path(stage) / f"{REV}.qsf"
        with qsf.open("a", encoding="utf-8", newline="\n") as output:
            output.write(f"\nset_global_assignment -name VERILOG_MACRO \"RABBITPUNCH_BUILD_ID=32'h{head[:8]}\"\n")

    # THE SEED IS PART OF THE BUILD. Two .rbf files from the same commit at
    # different seeds are not interchangeable: one placement with every clock
    # positive has broken games on hardware where another (worse worst slack)
    # ran them all. Record it, or a good build cannot be rebuilt.
    stamp = "%s  %s  seed=%s\n" % (
        head, datetime.datetime.now().isoformat(),
        args.seed if args.seed is not None else "default")
    open(os.path.join(stage, "BUILT_COMMIT"), "w").write(stamp)
    print("stage:  %s" % stage)
    print("rev:    %s" % REV)
    print("commit: %s (%s)" % (head_short, head))
    if dirty and args.allow_dirty:
        print("NOTE:   the tree has uncommitted changes and they are NOT in "
              "this build")

    if args.synth_check:
        from synth_checks import run_check
        return run_check(stage, QUARTUS_BIN, stamp, args.synth_check)

    for src, dst in STAGE_COPIES:
        with open(os.path.join(stage, src), "rb") as f_in, \
                open(os.path.join(stage, dst), "wb") as f_out:
            f_out.write(f_in.read())
        print("copied: %s -> %s (stage only)" % (src, dst))

    quartus = os.path.join(QUARTUS_BIN, "quartus_sh.exe")
    log_path = os.path.join(stage, "q_staged.log")
    open(marker, "w").write(stamp)
    try:
        clear_stale_bitstreams(stage, REV)
        # Keep Quartus caches/profile writes on D: as well as project scratch.
        env = quartus_child_environment(here)
        with open(log_path, "w") as log:
            compile_run = subprocess.run([quartus, "--flow", "compile", REV, "-c", REV],
                           cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT, **NO_WINDOW)
    finally:
        os.remove(marker)

    tail = open(log_path, errors="replace").read().splitlines()[-25:]
    ok = compile_run.returncode == 0 and any("Full Compilation was successful" in ln for ln in tail)
    for ln in tail:
        if any(k in ln for k in ("successful", "Error", "Elapsed")):
            print(ln.strip())

    print("")
    print("==== resource usage ====")
    report_resources(stage)
    print("")
    print("==== the design is still there ====")
    missing = check_present(stage)
    bad_macros = check_macros(stage)
    for m in REQUIRED_MACROS:
        print("  %-18s %s" % (m, "undefined" if any(m in b for b in bad_macros)
                                   else "defined"))

    print("")
    print("==== timing ====")
    if not ok:
        sys.exit("BUILD FAILED -- see %s" % log_path)
    check_timing_coverage(os.path.join(stage, "output_files", "%s.sta.rpt" % REV),
                          Path(stage) / "scripts/framework_timing_scope.json", stage, revision=REV)
    violations = read_slacks(
        os.path.join(stage, "output_files", "%s.sta.summary" % REV))

    if bad_macros:
        sys.exit("\nBUILD MISCONFIGURED --\n  " + "\n  ".join(bad_macros))

    if missing:
        sys.exit(
            "\nDESIGN INCOMPLETE -- %s missing from the fitted netlist.\n"
            "Whatever this build's timing says, it is not a measurement of the\n"
            "design you think you built. Look for an undriven clock or reset:\n"
            "  grep 'Stuck at GND due to stuck port clock' %s\n"
            % (", ".join(missing),
               os.path.join(stage, "output_files", "%s.map.rpt" % REV)))

    if not ok:
        sys.exit("BUILD FAILED -- see %s" % log_path)

    if violations and not args.allow_negative_slack:
        print("")
        for clk, slack, tns in violations:
            print("  FAILING: %-58s %8.3f  TNS %s" % (clk, slack, tns))
        sys.exit(
            "\nTIMING NOT MET -- %d clock(s) fail. The .rbf at\n"
            "  %s\nis not trustworthy. Close timing, try --seed, or pass\n"
            "--allow-negative-slack deliberately."
            % (len(violations),
               os.path.join(stage, "output_files", "%s.rbf" % REV)))
    if violations:
        print("")
        print("WARNING: --allow-negative-slack given; this build misses timing "
              "on %d clock(s)." % len(violations))

    inspect_full_clock_tree(stage, QUARTUS_BIN, REV)
    rbf = os.path.join(stage, "output_files", "%s.rbf" % REV)
    print("\nOK -- deploy with:\n"
          "  python scripts/deploy.py --rbf-only --rev %s --log \"%s\" \\\n"
          "      --rbf \"%s\" \\\n"
          "      --sta \"%s\""
          % (REV, log_path, rbf,
             os.path.join(stage, "output_files", "%s.sta.summary" % REV)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

