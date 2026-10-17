"""Verify the unchanged SDRAM controller through the VHDL pulse adapter and pin model."""
import hashlib
import json
import re
from coretools import core_root
from run_baselines import run_case

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--pll-clock', action='store_true', help='Use the vendor PLL and half-period physical chip clock')
parser.add_argument('--phase-ps', type=int, default=10714)
args = parser.parse_args()
if not 1 <= args.phase_ps < 21428:
    parser.error('Phase must be inside one system-clock period')
root = core_root()
sources = ["rtl/rabbitpunch_sdram_types.vhd", "rtl/memory/sdram/sdram.sv",
           "rtl/rabbitpunch_sdram.vhd", "rtl/synth_check/sdram/sdram_check.vhd", "sim/vendor/sdram/sdram_chip_model_wide.sv",
           "rtl/rabbitpunch_pll.vhd", "sim/memory/sdram_tb.vhd"]
manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
for row in manifest["files"]:
    if row["donor"] == "vamphalf":
        assert hashlib.sha256((root / row["target"]).read_bytes()).hexdigest() == row["sha256"]
case = "sdram_pll" if args.pll_clock else "sdram"
if args.pll_clock and args.phase_ps != 10714:
    case += f"_{args.phase_ps}ps"
libs = [item for library in ("altera_lnsim_ver", "altera_ver", "lpm_ver") for item in ("-L", library)]
source_hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result = run_case(case, sources, "sdram_tb", "2 ms", "SDRAM_PASS",
    sim_args=libs + (["-gGBOOL_PLL_CLOCK=true", f"-gGINT_SDRAM_PHASE_PS={args.phase_ps}"] if args.pll_clock else []), wall_timeout=180)
assert source_hashes == {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result["sdram_phase_ps"] = args.phase_ps if args.pll_clock else 0
result["source_sha256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
result["pll_clock"] = args.pll_clock
result["read_capture_adjust"] = int(args.pll_clock)
result["reinitialization_checked"] = args.pll_clock
log = (root / result["log"]).read_text()
for key in ("checked_words", "writes", "refresh_commands", "max_refresh_gap"):
    result[key] = int(re.search(rf"{key}=\s*(\d+)", log)[1])
result["scope"] = (f"Actual vendor PLL model at 46.6667 MHz with chip commands sampled on the external SDRAM clock shifted by {args.phase_ps} ps; " if args.pll_clock else "Same-phase 48 MHz command model; ") + "two chips, three clients, burst order, byte masks and refresh cadence; no analog/electrical or hardware timing proof"
(root / f"docs/reference/{case}_checks.json").write_text(json.dumps(result, indent=2) + "\n")
