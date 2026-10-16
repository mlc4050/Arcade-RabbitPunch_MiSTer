"""Run unchanged donor CPU regressions and the local JTFRAME row-interface test."""
import argparse
import hashlib
import json
import shutil
import subprocess

from coretools import core_root, modelsim_bin, NO_WINDOW
from hwlock import require_no_jtag


def run_case(name, sources, top, duration, marker):
    require_no_jtag(f"Rabbit Punch baseline: {name}")
    root, tools = core_root(), modelsim_bin()
    run_dir = root / "debug/baselines" / name
    run_dir.mkdir(parents=True, exist_ok=True)
    if any(path.startswith("rtl/cpu/fx68k/") for path in sources):
        for path in ("rtl/cpu/fx68k/microrom.mem", "rtl/cpu/fx68k/nanorom.mem"):
            target = run_dir / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / path, target)
    logs = []

    def command(exe, *args):
        result = subprocess.run([str(tools / (exe + ".exe")), *map(str, args)], cwd=run_dir,
                                capture_output=True, text=True, timeout=90, **NO_WINDOW)
        output = result.stdout + result.stderr
        logs.append(output)
        (run_dir / "result.log").write_text("\n".join(logs), encoding="utf-8")
        if result.returncode:
            raise SystemExit(f"{name}: {exe} failed\n{output}")

    command("vlib", "work")
    for path in sources:
        if path.endswith(".vhd"):
            command("vcom", "-2008", "-work", "work", root / path)
        else:
            command("vlog", "-sv", "+define+SIMULATION", "-suppress", "7061", "-work", "work", root / path)
    (run_dir / "run.do").write_text(
        "onerror {quit -code 1 -f}\nonbreak {quit -code 1 -f}\n"
        "set BreakOnAssertion 2\n"
        f"vsim -onfinish exit work.{top}\nrun {duration}\nquit -code 0 -f\n", encoding="utf-8")
    command("vsim", "-c", "-do", "do run.do")
    if marker not in logs[-1]:
        raise SystemExit(f"{name}: missing pass marker; see {run_dir / 'result.log'}")
    if "FAIL" in logs[-1] or "TIMEOUT" in logs[-1]:
        raise SystemExit(f"{name}: failure in transcript; see {run_dir / 'result.log'}")
    label = "MEASURED" if name == "tg68k_pace" else "PASS"
    print(f"{label} {name}: {marker}", flush=True)
    return {"case": name, "pass_marker": marker, "log": str((run_dir / "result.log").relative_to(root))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="+", help="Case names; default all")
    args = ap.parse_args()
    root = core_root()
    manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
    for item in manifest["files"]:
        if hashlib.sha256((root / item["target"]).read_bytes()).hexdigest() != item["sha256"]:
            raise SystemExit(f"Pinned donor file changed: {item['target']}")
    tg = [f"rtl/cpu/tg68k/{n}.vhd" for n in ("TG68K_Pack", "TG68K_ALU", "TG68KdotC_Kernel", "TG68K")]
    t80 = [f"rtl/cpu/t80/{n}.vhd" for n in ("T80_Pack", "T80_Reg", "T80_MCode", "T80_ALU", "T80", "T80se")]
    cases = [
        ("t80_donor", t80 + ["sim/vendor/t80/tb_t80_boot.vhd"],
                 "tb_t80_boot", "3 us", "PASS: T80se boots"),
        ("tg68k_donor", tg + ["sim/vendor/tg68k/tb_tg68k_boot.vhd"],
                 "tb_tg68k_boot", "250 us", "REACHED END: BFEXTU result write observed"),
        ("tg68k_68000", tg[:3] + ["sim/vendor/tg68k/tb_tg68k_smoke.sv"],
                 "tb_tg68k_smoke", "300 us", "PASS: kernel boots, executes, and writes the right result"),
        ("tg68k_ccr", tg[:3] + ["sim/vendor/tg68k/tb_tg68k_ccr.sv"],
                 "tb_tg68k_ccr", "300 us", "PASS: ori and andi to CCR"),
        ("tg68k_pace", tg[:3] + ["sim/vendor/tg68k/tb_tg68k_pace.sv"],
                 "tb_tg68k_pace", "200 ms", "fetches of the nop: 10273, expected 10273"),
        ("jtframe_draw", ["rtl/jtframe/jtframe_draw.v", "sim/jtframe_baseline/draw_tb.sv"],
                 "draw_tb", "100 us", "JTFRAME_DRAW_PASS"),
        ("jtframe_buffer", ["rtl/jtframe/jtframe_dual_ram.v", "rtl/jtframe/jtframe_obj_buffer.v",
                             "sim/jtframe_baseline/buffer_tb.sv"],
                 "buffer_tb", "100 us", "JTFRAME_BUFFER_PASS"),
        ("fx68k_pace", ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv",
                         "rtl/cpu/fx68k/uaddrPla.sv", "sim/vendor/fx68k/tb_fx68k_pace.sv"],
                 "tb_fx68k_pace", "200 ms", "one iteration: 14 clocks (68000: 14)"),
    ]
    known = {case[0] for case in cases}
    if args.only and set(args.only) - known:
        ap.error("Unknown cases: " + ", ".join(sorted(set(args.only) - known)))
    report = core_root() / "debug/baselines/results.json"
    previous = json.loads(report.read_text()) if report.exists() else []
    results = {item["case"]: item for item in previous}
    for case in cases:
        if not args.only or case[0] in args.only:
            results[case[0]] = run_case(*case)
            report.write_text(json.dumps(list(results.values()), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
