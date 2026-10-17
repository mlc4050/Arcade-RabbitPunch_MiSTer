"""Exercise ROM region/lane mapping and queued request backpressure in VHDL."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_sdram_types.vhd",
           "rtl/memory/sdram/sdram.sv", "rtl/rabbitpunch_sdram.vhd",
           "sim/vendor/sdram/sdram_chip_model_wide.sv",
           "rtl/rabbitpunch_rom_requests.vhd", "rtl/synth_check/rom_requests/rom_requests_check.vhd", "sim/memory/rom_requests_tb.vhd"]
results = []
for pin_backend in (False, True):
    case = "rom_requests_pin" if pin_backend else "rom_requests"
    result = run_case(case, sources, "rom_requests_tb", "1 ms", "ROM_REQUESTS_PASS",
                      sim_args=("-gUSE_PIN_BACKEND=true",) if pin_backend else ())
    results.append(result)
for result in results:
    result["source_sha256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
    result["scope"] = ("Synthetic byte-address-dependent data with " +
        ("actual SDRAM controller and command model" if result["case"].endswith("_pin") else "delayed/backpressured burst clients") +
        "; region offsets, banks, word lanes and CPU endian assembly; no analog timing or full-game proof")
(root / "docs/reference/rom_request_checks.json").write_text(json.dumps(results, indent=2) + "\n")
