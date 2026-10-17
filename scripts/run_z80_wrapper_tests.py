"""Exercise the descriptive T80 wrapper with clock enables and a stretched read."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = [f"rtl/cpu/t80/{name}.vhd" for name in ("T80_Pack", "T80_Reg", "T80_MCode", "T80_ALU", "T80", "T80se")]
    sources += ["rtl/rabbitpunch_z80.vhd", "sim/sound/z80_wrapper_tb.vhd"]
    result = run_case("z80_wrapper", sources, "z80_wrapper_tb", "60 us", "Z80_WRAPPER_PASS")
    result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
        log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
        scope="Already-baselined T80 behind active-high unsigned VHDL adapter: instruction fetch, memory and I/O writes, WAIT stretching and clock-enable stop; no real sound ROM, sound bus or interrupt timing proof")
    (root / "docs/reference/z80_wrapper_checks.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
