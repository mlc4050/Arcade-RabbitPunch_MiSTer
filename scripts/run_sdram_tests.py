"""Verify the unchanged SDRAM controller through the VHDL pulse adapter and pin model."""
import hashlib
import json
import re
from coretools import core_root
from run_baselines import run_case

import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--pll-clock', action='store_true', help='Use the vendor PLL and half-period physical chip clock')
args = parser.parse_args()
root = core_root()
sources = ["rtl/rabbitpunch_sdram_types.vhd", "rtl/memory/sdram/sdram.sv",
           "rtl/rabbitpunch_sdram.vhd", "rtl/synth_check/sdram/sdram_check.vhd", "sim/vendor/sdram/sdram_chip_model_wide.sv",
           "rtl/rabbitpunch_pll.vhd", "sim/memory/sdram_tb.vhd"]
manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
for row in manifest["files"]:
    if row["donor"] == "vamphalf":
        assert hashlib.sha256((root / row["target"]).read_bytes()).hexdigest() == row["sha256"]
case = "sdram_pll" if args.pll_clock else "sdram"
libs = [item for library in ("altera_lnsim_ver", "altera_ver", "lpm_ver") for item in ("-L", library)]
result = run_case(case, sources, "sdram_tb", "2 ms", "SDRAM_PASS",
    sim_args=libs + (["-gGBOOL_PLL_CLOCK=true"] if args.pll_clock else []), wall_timeout=180)
result["source_sha256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
result["pll_clock"] = args.pll_clock
result["read_capture_adjust"] = int(args.pll_clock)
result["reinitialization_checked"] = args.pll_clock
log = (root / result["log"]).read_text()
for key in ("checked_words", "writes", "refresh_commands", "max_refresh_gap"):
    result[key] = int(re.search(rf"{key}=\s*(\d+)", log)[1])
result["scope"] = ("Actual vendor PLL model at 46.6667 MHz with chip commands sampled on the half-period shifted external SDRAM clock; " if args.pll_clock else "Same-phase 48 MHz command model; ") + "two chips, three clients, burst order, byte masks and refresh cadence; no analog/electrical or hardware timing proof"
(root / ("docs/reference/sdram_pll_checks.json" if args.pll_clock else "docs/reference/sdram_checks.json")).write_text(json.dumps(result, indent=2) + "\n")
