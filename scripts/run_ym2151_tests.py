"""Check the unchanged selected JT51's reset, silence, sample cadence and timers."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    manifest = json.loads((root / "docs/reference/vendor_manifest.json").read_text())
    rows = [row for row in manifest["files"] if row["target"].startswith(("rtl/sound/jt51/", "sim/vendor/jt51/"))]
    for row in rows:
        assert hashlib.sha256((root / row["target"]).read_bytes()).hexdigest() == row["sha256"]
    sources = [row["target"] for row in rows if row["target"].endswith(".v")]
    sources += ["rtl/rabbitpunch_ym2151.vhd", "sim/sound/jt51_baseline_tb.vhd"]
    results = []
    for wrapped in (False, True):
        result = run_case("jt51_wrapper" if wrapped else "jt51_baseline", sources, "jt51_baseline_tb", "1 ms",
            "JT51_BASELINE_PASS", sim_args=(f"-gGBOOL_USE_WRAPPER={'true' if wrapped else 'false'}",), wall_timeout=120)
        result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
            log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(), wrapper=wrapped,
            scope="Unchanged JT51 baseline and descriptive VHDL wrapper: reset flags/explicitly muted PCM, 4 MHz enables, sample cadence, timer A/B flags and IRQ clearing; no keyed waveform/game audio or MAME trace comparison")
        results.append(result)
    (root / "docs/reference/ym2151_checks.json").write_text(json.dumps(results, indent=2) + "\n")



if __name__ == "__main__":
    main()
