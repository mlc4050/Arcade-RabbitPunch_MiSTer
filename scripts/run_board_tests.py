"""ModelSim checks of new VHDL board interfaces, before game integration."""
import json
from coretools import core_root
from run_baselines import run_case


def main():
    results = [run_case("board_decode", ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                                      "sim/board/decode_tb.sv"],
                      "decode_tb", "1 us", "BOARD_DECODE_PASS"),
               run_case("board_bus", ["rtl/rabbitpunch_bus.vhd", "sim/board/bus_tb.sv"],
                        "bus_tb", "100 us", "BOARD_BUS_PASS")]
    (core_root() / "debug/board_test_results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
