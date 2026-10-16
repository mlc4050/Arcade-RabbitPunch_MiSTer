"""Check actual VHDL/SystemVerilog compilation, elaboration and execution."""
import subprocess
from coretools import core_root, modelsim_bin, NO_WINDOW
from hwlock import require_no_jtag


def main():
    require_no_jtag("Rabbit Punch mixed-language toolchain check")
    root = core_root()
    tools = modelsim_bin()
    run_dir = root / "debug" / "toolchain"
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "run.do").write_text(
        "onerror {quit -code 1 -f}\n"
        "onbreak {quit -code 1 -f}\n"
        "vsim -onfinish exit work.smoke_tb\n"
        "run -all\nquit -code 0 -f\n", encoding="utf-8")
    commands = [
        [tools / "vlib.exe", "work"],
        [tools / "vcom.exe", "-93", "-work", "work", root / "sim/toolchain/smoke.vhd"],
        [tools / "vlog.exe", "-sv", "-work", "work", root / "sim/toolchain/smoke_tb.sv"],
        [tools / "vsim.exe", "-c", "-do", "do run.do"],
    ]
    logs = []
    for command in commands:
        result = subprocess.run([str(c) for c in command], cwd=run_dir,
                                capture_output=True, text=True, timeout=90, **NO_WINDOW)
        output = result.stdout + result.stderr
        logs.append(output)
        (run_dir / "result.log").write_text("\n".join(logs), encoding="utf-8")
        if result.returncode:
            raise SystemExit(output)
    if "TOOLCHAIN_SMOKE_PASS" not in logs[-1]:
        raise SystemExit("Simulation did not reach the pass marker:\n" + logs[-1])
    print("PASS: ModelSim compiled, elaborated and ran VHDL + SystemVerilog")
    print(run_dir / "result.log")


if __name__ == "__main__":
    main()
