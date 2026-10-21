// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
#include "Vstate_presentation_constant_eval.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>

double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file, int line, const char*, const char* text) {
    std::fprintf(stderr, "%s:%d: %s\n", file, line, text);
    std::exit(2);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vstate_presentation_constant_eval model;
    for (unsigned cycle = 0; cycle < 160000; ++cycle) {
        model.i_initialize = cycle < 4;
        model.i_clk = 0;
        model.eval();
        Verilated::timeInc(5000);
        model.i_clk = 1;
        model.eval();
        Verilated::timeInc(5000);
        if (model.o_done) {
            FILE* result = std::fopen("constant_result.txt", "wb");
            if (!result) return 3;
            std::fprintf(result, "%u %u %u\n", unsigned(model.ou2_mode),
                unsigned(model.ou32_writes), unsigned(model.o_unblanked));
            std::fclose(result);
            model.final();
            return 0;
        }
    }
    return 4;
}
