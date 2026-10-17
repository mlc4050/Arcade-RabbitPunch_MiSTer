"""Check sequential image loading, drain/reset ownership and malformed-image recovery."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_download.vhd", "sim/memory/download_tb.vhd"]
    result = run_case("download", sources, "download_tb", "30 us", "DOWNLOAD_PASS")
    result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
        log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
        scope="16-byte test images with synthetic delayed/backpressured loader; no HPS/DDR or physical memory integration proof")
    results = [result]
    sources = ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_download.vhd", "rtl/rabbitpunch_sdram_types.vhd",
        "rtl/memory/sdram/sdram.sv", "rtl/rabbitpunch_sdram.vhd", "rtl/rabbitpunch_rom_requests.vhd",
        "rtl/rabbitpunch_rom_cache.vhd", "rtl/rabbitpunch_roms.vhd",
        "sim/vendor/sdram/sdram_chip_model_wide.sv", "sim/memory/download_sdram_tb.vhd"]
    result = run_case("download_sdram", sources, "download_sdram_tb", "300 us", "DOWNLOAD_SDRAM_PASS")
    result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
        log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
        scope="Two 16-byte images written through production ROM loader/cache/controller and SDRAM chip commands; 16 CPU readbacks verify byte order and replacement; no HPS/DDR/physical electrical timing proof")
    results.append(result)
    (root / "docs/reference/download_checks.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
