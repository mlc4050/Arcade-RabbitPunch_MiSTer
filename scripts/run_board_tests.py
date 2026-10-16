"""ModelSim checks of new VHDL board interfaces, before game integration."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    results = [run_case("board_decode", ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                                      "sim/board/decode_tb.sv"],
                      "decode_tb", "1 us", "BOARD_DECODE_PASS"),
               run_case("board_bus", ["rtl/rabbitpunch_bus.vhd", "sim/board/bus_tb.sv"],
                        "bus_tb", "100 us", "BOARD_BUS_PASS"),
               run_case("board_maincpu", ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv",
                         "rtl/cpu/fx68k/uaddrPla.sv", "rtl/rabbitpunch_bus.vhd",
                         "rtl/rabbitpunch_fx68k.vhd", "rtl/rabbitpunch_maincpu.vhd", "sim/board/maincpu_tb.sv"],
                        "maincpu_tb", "2 ms", "MAINCPU_PASS")]
    for result in results:
        result["log_sha256"] = hashlib.sha256((core_root() / result["log"]).read_bytes()).hexdigest()
    report = json.dumps(results, indent=2) + "\n"
    (core_root() / "debug/board_test_results.json").write_text(report, encoding="utf-8")
    (core_root() / "docs/reference/board_checks.json").write_text(report, encoding="utf-8")


if __name__ == "__main__":
    main()
