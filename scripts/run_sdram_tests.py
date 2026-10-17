"""Verify the unchanged SDRAM controller through the VHDL pulse adapter and pin model."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root = core_root()
sources = ["rtl/rabbitpunch_sdram_types.vhd", "rtl/memory/sdram/sdram.sv",
           "rtl/rabbitpunch_sdram.vhd", "sim/vendor/sdram/sdram_chip_model_wide.sv",
           "sim/memory/sdram_tb.vhd"]
manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
for row in manifest["files"]:
    if row["donor"] == "vamphalf":
        assert hashlib.sha256((root / row["target"]).read_bytes()).hexdigest() == row["sha256"]
result = run_case("sdram", sources, "sdram_tb", "2 ms", "SDRAM_PASS", wall_timeout=180)
result["source_sha256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
result["scope"] = "Pin-command functional model, two chips, three clients, burst order, byte masks and refresh cadence at 48 MHz; no analog/board timing proof"
(root / "docs/reference/sdram_checks.json").write_text(json.dumps(result, indent=2) + "\n")
