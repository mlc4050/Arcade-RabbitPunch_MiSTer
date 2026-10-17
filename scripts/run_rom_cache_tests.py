"""Check three independent read-only burst caches, stalls and ROM invalidation."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
sources = ["rtl/rabbitpunch_sdram_types.vhd", "rtl/rabbitpunch_rom_cache.vhd", "rtl/synth_check/rom_cache/rom_cache_check.vhd", "sim/memory/rom_cache_tb.vhd"]
result = run_case("rom_cache", sources, "rom_cache_tb", "1 ms", "ROM_CACHE_PASS")
result["source_sha256"] = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
result["log_sha256"] = hashlib.sha256((root / result["log"]).read_bytes()).hexdigest()
(root / "docs/reference/rom_cache_checks.json").write_text(json.dumps(result, indent=2) + "\n")
