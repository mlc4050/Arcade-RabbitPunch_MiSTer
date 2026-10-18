"""Exercise zero-storage shared CRT/HDMI coordinate flip and transaction guards."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case

root = core_root()
sources = ["rtl/rabbitpunch_view_flip.vhd", "sim/video/view_flip_tb.vhd"]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = run_case("view_flip", sources, "view_flip_tb", "200 us", "VIEW_FLIP_PASS")
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(source_sha256=hashes, coordinate_points=124416,
    log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
    scope="Coordinate and transaction-guard unit simulation; no renderer integration, routed timing or physical CRT proof")
(root / "docs/reference/view_flip_checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
