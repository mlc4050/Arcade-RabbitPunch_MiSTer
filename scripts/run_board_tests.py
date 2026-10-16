"""ModelSim checks of new VHDL board interfaces, before game integration."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    t80 = [f"rtl/cpu/t80/{name}.vhd" for name in
           ("T80_Pack", "T80_Reg", "T80_MCode", "T80_ALU", "T80", "T80se")]
    results = [run_case("board_decode", ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                                      "sim/board/decode_tb.sv"],
                      "decode_tb", "1 us", "BOARD_DECODE_PASS"),
               run_case("board_bus", ["rtl/rabbitpunch_bus.vhd", "sim/board/bus_tb.sv"],
                        "bus_tb", "100 us", "BOARD_BUS_PASS"),
               run_case("board_maincpu", ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv",
                         "rtl/cpu/fx68k/uaddrPla.sv", "rtl/rabbitpunch_bus.vhd",
                         "rtl/rabbitpunch_fx68k.vhd", "rtl/rabbitpunch_maincpu.vhd", "sim/board/maincpu_tb.sv"],
                        "maincpu_tb", "2 ms", "MAINCPU_PASS"),
               run_case("board_t80_wrapper", t80 + ["rtl/rabbitpunch_t80.vhd", "sim/board/t80_wrapper_tb.sv"],
                        "t80_wrapper_tb", "3 us", "T80_WRAPPER_PASS"),
               run_case("board_memory", ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                         "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_memory.vhd", "sim/board/memory_tb.sv"],
                        "memory_tb", "20 ms", "MEMORY_PASS")]
    results += [run_case("board_io", ["rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                         "rtl/rabbitpunch_io.vhd", "sim/board/io_tb.sv"], "io_tb", "10 us", "IO_PASS"),
                run_case("board_irq", ["rtl/rabbitpunch_irq.vhd", "sim/board/irq_tb.sv"],
                         "irq_tb", "10 us", "IRQ_PASS"),
                run_case("board_cpu_irq", ["rtl/cpu/fx68k/fx68k.sv", "rtl/cpu/fx68k/fx68kAlu.sv",
                         "rtl/cpu/fx68k/uaddrPla.sv", "rtl/rabbitpunch_layout.vhd", "rtl/rabbitpunch_decode.vhd",
                         "rtl/rabbitpunch_ram16.vhd", "rtl/rabbitpunch_memory.vhd", "rtl/rabbitpunch_bus.vhd",
                         "rtl/rabbitpunch_fx68k.vhd", "rtl/rabbitpunch_maincpu.vhd", "sim/board/cpu_irq_tb.sv"],
                         "cpu_irq_tb", "1 ms", "CPU_IRQ_PASS")]
    for result in results:
        result["log_sha256"] = hashlib.sha256((core_root() / result["log"]).read_bytes()).hexdigest()
    report = json.dumps(results, indent=2) + "\n"
    (core_root() / "debug/board_test_results.json").write_text(report, encoding="utf-8")
    (core_root() / "docs/reference/board_checks.json").write_text(report, encoding="utf-8")


if __name__ == "__main__":
    main()
