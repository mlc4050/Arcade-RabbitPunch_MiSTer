"""Verify physical loader writes, cached ROM reads and safe image replacement."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_sdram_types.vhd", "rtl/memory/sdram/sdram.sv",
    "rtl/rabbitpunch_sdram.vhd", "rtl/rabbitpunch_rom_requests.vhd", "rtl/rabbitpunch_rom_cache.vhd",
    "rtl/rabbitpunch_read_arbiter.vhd", "rtl/rabbitpunch_audio_roms.vhd", "rtl/rabbitpunch_audio_rom_transport.vhd", "rtl/state/rabbitpunch_state_sdram_phase.vhd", "rtl/rabbitpunch_roms.vhd", "sim/vendor/sdram/sdram_chip_model_wide.sv", "sim/memory/roms_tb.vhd"]
result = run_case("roms", sources, "roms_tb", "2 ms", "ROMS_PASS")
result["source_sha256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
result["scope"] = "Production ROM subsystem with actual word loader, cache invalidation and SDRAM chip-command model; no HPS download or electrical timing proof"
(root / "docs/reference/rom_subsystem_checks.json").write_text(json.dumps(result, indent=2) + "\n")
