// SPDX-License-Identifier: GPL-3.0-or-later
// Clocks and observations only. VHDL owns every read/write command and check.
#include "Vstate_sdram_alias_eval.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>

double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file, int line, const char*, const char* message) {
    std::fprintf(stderr, "VHDL_ASSERTION %s:%d %s\n", file, line, message);
    std::exit(1);
}
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::randReset(0);
    Vstate_sdram_alias_eval m;
    m.i_clk = 0;
    m.i_chip_clk = 0;
    m.i_initialize = 1;
    FILE* out = std::fopen("alias_trace.txt", "wb");
    if (!out) return 2;
    unsigned reads = 0;
    for (unsigned cycle = 0; cycle < 50000; ++cycle) {
        m.i_initialize = cycle < 32;
        m.i_clk = 0; m.eval();
        m.i_clk = 1; m.eval();
        if (m.o_initialized) {
            std::fprintf(out, "C %u %X %X %X %X %06X\n", unsigned(m.ou32_clock),
                unsigned(m.ou3_requests), unsigned(m.ou3_ready), unsigned(m.ou3_valid),
                unsigned(m.ou3_reads), unsigned(m.ou22_command));
            const uint64_t data[] = {m.ou64_data0, m.ou64_data1, m.ou64_data2};
            for (unsigned port = 0; port < 3; ++port) {
                if (m.ou3_reads & (1u << port)) {
                    std::fprintf(out, "R %u %u %016llX\n", unsigned(m.ou32_clock),
                        port, (unsigned long long)data[port]);
                    ++reads;
                }
            }
            if (m.o_complete) {
                std::fclose(out);
                m.final();
                if (reads != 192) return 3;
                std::puts("STATE_SDRAM_ALIAS_FAST_COMPLETE");
                return 0;
            }
        }
        Verilated::timeInc(5357); m.i_chip_clk = 1; m.eval();
        Verilated::timeInc(5357); m.i_clk = 0; m.eval();
        Verilated::timeInc(5357); m.i_chip_clk = 0; m.eval();
        Verilated::timeInc(5357);
    }
    std::fclose(out);
    return 4;
}
