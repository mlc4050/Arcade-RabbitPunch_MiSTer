// SPDX-License-Identifier: GPL-3.0-or-later
// Diagnostic transport only; this does not qualify a complete game restore.
// Clocks, external DDR storage and observations only; VHDL owns test commands.
#include "Vstate_machine_restore_eval.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <vector>

double sc_time_stamp() { return 0.0; }
void vl_fatal(const char* file, int line, const char*, const char* message) {
    std::fprintf(stderr, "VHDL_ASSERTION %s:%d %s\n", file, line, message);
    std::exit(1);
}
struct Response { uint64_t due, data; };
struct Port {
    std::deque<Response> pending;
    uint64_t reads = 0, writes = 0;
    bool busy(uint64_t cycle) const { return pending.size() > 256 || cycle % 31 == 7; }
    bool valid(uint64_t cycle) const { return !pending.empty() && pending.front().due <= cycle; }
    uint64_t data(uint64_t cycle) const { return valid(cycle) ? pending.front().data : 0; }
    void accept_response(uint64_t cycle) { if (valid(cycle)) pending.pop_front(); }
    void read(uint64_t cycle, uint64_t data) {
        uint64_t due = cycle + 3;
        if (!pending.empty() && due <= pending.back().due) due = pending.back().due + 1;
        pending.push_back({due, data});
        ++reads;
    }
};
uint64_t load64(const std::vector<uint8_t>& data, size_t offset) {
    if (offset + 8 > data.size()) throw std::runtime_error("DDR read outside bounded image");
    uint64_t word = 0;
    for (unsigned n = 0; n < 8; ++n) word |= uint64_t(data[offset + n]) << (8 * n);
    return word;
}
void store64(std::vector<uint8_t>& data, size_t offset, uint64_t word) {
    if (offset + 8 > data.size()) throw std::runtime_error("DDR write outside bounded slot");
    for (unsigned n = 0; n < 8; ++n) data[offset + n] = uint8_t(word >> (8 * n));
}
int main(int argc, char** argv) {
    try {
        if (argc != 2) throw std::runtime_error("usage: restore_eval path/to/real-rom-image.bin");
        Verilated::commandArgs(argc, argv);
        Verilated::randReset(0); // Qualified FPGA configuration-zero contract, not CPU/RAM deposits.
        std::ifstream input(argv[1], std::ios::binary);
        if (!input) throw std::runtime_error("ROM image missing");
        std::vector<uint8_t> rom((std::istreambuf_iterator<char>(input)), {});
        if (rom.size() != 0x210000) throw std::runtime_error("Full 0x210000-byte image required");
        std::vector<uint8_t> slot(0x40000, 0); // External DDR slot0 only, separate from loader.
        bool seeded = false;
        std::ifstream seed("../seed_slot0.bin", std::ios::binary);
        if (seed) {
            std::vector<uint8_t> data((std::istreambuf_iterator<char>(seed)), {});
            if (data.size() != slot.size() || load64(data, 0) != (uint64_t(107280 / 4) << 32 | 0xffffffffu))
                throw std::runtime_error("Cold reference requires an ARM file-loaded slot image");
            slot = data; // External persisted DDR contents, never an internal model write.
            std::ofstream saved("slot0_save1.bin", std::ios::binary);
            saved.write(reinterpret_cast<const char*>(slot.data()), slot.size());
            if (!saved) throw std::runtime_error("Cannot preserve external seed image");
            seeded = true;
        }
        Port loader, state;
        std::vector<uint8_t> rotation;
        uint64_t rotation_writes = 0;
        bool rotation_unblanked = false;
        Vstate_machine_restore_eval m;
        m.i_clk = 0;
        m.i_initialize = 0;
        m.iu128_status[0] = 0;
        m.iu128_status[1] = 0;
        m.iu128_status[2] = 0;
        m.iu128_status[3] = 0;
        m.iu2_host_buttons = 0;
        m.iu32_joystick0 = 0;
        m.iu32_joystick1 = 0;
        m.iu11_key_event = 0;
        m.i_osd_open = 0;
        m.i_debug_pause = 0;
        m.i_host_upload = 0;
        m.iu16_host_index = 0;
        m.i_host_write = 0;
        m.iu27_host_byte_address = 0;
        m.iu8_host_data = 0;
        m.i_maintenance_access = 0;
        m.i_maintenance_valid = 0;
        m.i_maintenance_write = 0;
        m.iu14_maintenance_byte_address = 0;
        m.iu8_maintenance_data = 0;
        m.i_ddr_busy = 0;
        m.iu64_ddr_read_data = 0;
        m.i_ddr_read_valid = 0;
        m.i_view_enable = 0;
        m.iu5_view_target = 0;
        m.iu15_view_word_address = 0;
        m.i_audio_view_enable = 0;
        m.iu11_audio_view_address = 0;
        m.iu4_gga_view_address = 0;
        m.i_state_ddr_busy = 0;
        m.i_state_ddr_read_valid = 0;
        m.iu64_state_ddr_read_data = 0;
        m.i_chip_clk = 0;
        std::array<FILE*, 7> traces{};
        for (unsigned n = 1; n <= 6; ++n) {
            char name[32]; std::snprintf(name, sizeof(name), "continuation_%u.txt", n);
            traces[n] = std::fopen(name, "wb");
            if (!traces[n]) throw std::runtime_error("Cannot create trace");
        }
        FILE* endpoints = std::fopen("endpoints.txt", "wb");
        if (!endpoints) throw std::runtime_error("Cannot create endpoint trace");
        FILE* progress = std::fopen("progress.txt", "wb");
        if (!progress) throw std::runtime_error("Cannot create progress trace");
        std::array<uint64_t, 7> relative{};
        bool identity_seen = false;
        bool profile_seen = false;
        bool scores_seen = false;
        unsigned published_saves = seeded ? 1 : 0;
        if (seeded) std::fprintf(endpoints, "EXTERNAL_SLOT counter=ffffffff bytes=%u\n", unsigned(slot.size()));
        unsigned previous_window = 0;
        for (uint64_t cycle = 0; cycle < 2000000000; ++cycle) {
            m.i_initialize = cycle < 32;
            m.i_ddr_busy = loader.busy(cycle);
            m.i_ddr_read_valid = loader.valid(cycle);
            m.iu64_ddr_read_data = loader.data(cycle);
            m.i_state_ddr_busy = state.busy(cycle);
            m.i_state_ddr_read_valid = state.valid(cycle);
            m.iu64_state_ddr_read_data = state.data(cycle);
            m.i_clk = 0; m.eval();
            // Accept only pre-edge commands with pre-edge busy low. Data returns
            // are also sampled at that same rising edge; no transparent RAM shortcut.
            loader.accept_response(cycle); state.accept_response(cycle);
            if (m.o_ddr_read && m.o_ddr_write) throw std::runtime_error("Overlapping external DDR read/write");
            if (m.o_ddr_read && !m.i_ddr_busy) {
                uint64_t address = m.ou29_ddr_word_address;
                if (m.o_eval_shared_ddr && address >= 0x07c00000 && address < 0x07c08000) {
                    if (m.ou8_ddr_burst_count != 1) throw std::runtime_error("Shared slot read must be single beat");
                    loader.read(cycle, load64(slot, (address - 0x07c00000) * 8));
                    ++state.reads; // Statistics only: the response uses the one external port.
                } else {
                    if (address < 0x06000000 || !m.ou8_ddr_burst_count)
                        throw std::runtime_error("Invalid loader DDR command");
                    for (unsigned n = 0; n < m.ou8_ddr_burst_count; ++n)
                        loader.read(cycle, load64(rom, (address - 0x06000000 + n) * 8));
                }
            }
            if (m.o_ddr_write && !m.i_ddr_busy) {
                if (!m.o_eval_shared_ddr || m.ou8_ddr_burst_count != 1)
                    throw std::runtime_error("Unexpected loader write");
                uint64_t address = m.ou29_ddr_word_address;
                if (address >= 0x07c00000 && address < 0x07c08000) {
                    if (m.ou8_ddr_byte_enables != 0xff) throw std::runtime_error("Partial shared slot write");
                    store64(slot, (address - 0x07c00000) * 8, m.ou64_ddr_write_data);
                    ++state.writes;
                } else if (address >= 0x04800000 && address < 0x04b00000) {
                    if (rotation.empty()) rotation.resize(0x1800000, 0);
                    size_t offset = (address - 0x04800000) * 8;
                    for (unsigned lane = 0; lane < 8; ++lane)
                        if (m.ou8_ddr_byte_enables & (1u << lane))
                            rotation[offset + lane] = uint8_t(m.ou64_ddr_write_data >> (8 * lane));
                    ++rotation_writes;
                } else throw std::runtime_error("Shared DDR write outside slot/rotation mappings");
            }
            if (m.o_eval_shared_ddr && (m.o_state_ddr_read || m.o_state_ddr_write))
                throw std::runtime_error("Shared mode also drove the separate state port");
            if ((m.o_state_ddr_read || m.o_state_ddr_write) && !m.i_state_ddr_busy) {
                if (m.ou29_state_ddr_word_address < 0x07c00000)
                    throw std::runtime_error("State DDR command below slot0");
                size_t offset = (uint64_t(m.ou29_state_ddr_word_address) - 0x07c00000) * 8;
                if (m.o_state_ddr_read) state.read(cycle, load64(slot, offset));
                if (m.o_state_ddr_write) { store64(slot, offset, m.ou64_state_ddr_write_data); ++state.writes; }
            }
            bool go = m.o_state_run_release;
            m.i_clk = 1; m.eval();
            if (m.o_eval_shared_ddr && m.o_eval_rotation_overflow)
                throw std::runtime_error("Shared presentation queue overflowed");
            if (rotation_writes && !m.o_eval_framebuffer_blank) rotation_unblanked = true;
            if (m.o_state_finished && m.o_state_success && !m.o_state_restoring) {
                ++published_saves;
                unsigned expected_counter = seeded ? published_saves - 2 : published_saves;
                if (published_saves > 2 || load64(slot, 0) !=
                    (uint64_t(107280 / 4) << 32 | expected_counter))
                    throw std::runtime_error("SAVE completion lacks atomic counter/length publication");
                char name[32]; std::snprintf(name, sizeof(name), "slot0_save%u.bin", published_saves);
                std::ofstream saved(name, std::ios::binary);
                saved.write(reinterpret_cast<const char*>(slot.data()), slot.size());
                if (!saved) throw std::runtime_error("Cannot preserve published slot image");
            }
            if ((cycle & 0xfffff) == 0) {
                std::fprintf(progress,
                    "cycle=%llu loader_reads=%llu state_reads=%llu state_writes=%llu bytes=%u ready=%u window=%u presentation=%02x player1=%02x service=%02x\n",
                    (unsigned long long)cycle, (unsigned long long)loader.reads,
                    (unsigned long long)state.reads, (unsigned long long)state.writes,
                    unsigned(m.ou27_bytes_loaded), unsigned(m.o_ready), unsigned(m.ou3_eval_window),
                    unsigned(m.ou8_eval_presentation_flags), unsigned(m.ou8_player1), unsigned(m.ou8_service));
                std::fflush(progress);
            }
            if (m.o_state_rom_identity_valid && !identity_seen) {
                std::fprintf(endpoints, "ROM_ID %08x cycle=%llu\n", unsigned(m.ou32_state_rom_identity), (unsigned long long)cycle);
                identity_seen = true;
                std::fflush(endpoints);
            }
            if (m.o_hiscore_enabled && !profile_seen) {
                std::fprintf(endpoints, "PROFILE enabled=1 error=%u cycle=%llu\n",
                    unsigned(m.o_hiscore_config_error), (unsigned long long)cycle);
                profile_seen = true;
                std::fflush(endpoints);
            }
            if (m.o_hiscore_initialized && !scores_seen) {
                std::fprintf(endpoints, "SCORES ready=1 saved=%u cycle=%llu\n",
                    unsigned(m.o_hiscore_saved_valid), (unsigned long long)cycle);
                scores_seen = true;
                std::fflush(endpoints);
            }
            unsigned window = m.ou3_eval_window;
            if (window > 6) throw std::runtime_error("Invalid continuation window");
            if (window != previous_window) {
                if (window && !go) throw std::runtime_error("Continuation did not begin at private GO");
                std::fprintf(endpoints, "WINDOW %u cycle=%llu go=%u stop=%u halt=%u irq=%x beam=%u,%u nvready=%u nvsaved=%u\n",
                    window, (unsigned long long)cycle, go, unsigned(m.o_state_cpu_stopped),
                    unsigned(m.o_eval_sound_halted), unsigned(m.ou4_eval_irq),
                    unsigned(m.ou9_horizontal_position), unsigned(m.ou9_vertical_position),
                    unsigned(m.o_hiscore_initialized), unsigned(m.o_hiscore_saved_valid));
                previous_window = window;
                std::fflush(endpoints);
            }
            if (window) {
                auto stamp = (unsigned long long)relative[window]++;
                FILE* out = traces[window];
                // Defined per-clock sound/cadence state, plus actual write and
                // pixel events. Idle bus fields have no event semantics.
                std::fprintf(out, "C %llu %04x %04x %04x %03x %u %u %u %u %u %u %u %u %x\n",
                    stamp, unsigned(m.ou16_left_pcm), unsigned(m.ou16_right_pcm),
                    unsigned(m.ou16_mono_pcm), unsigned(m.ou9_adpcm_pcm),
                    unsigned(m.o_audio_sample_marker), unsigned(m.o_pixel_enable),
                    unsigned(m.o_hsync), unsigned(m.o_vsync), unsigned(m.o_hblank), unsigned(m.o_vblank),
                    unsigned(m.o_state_cpu_stopped), unsigned(m.o_eval_sound_halted), unsigned(m.ou4_eval_irq));
                if (m.o_cpu_request && m.o_cpu_request_write) {
                    unsigned mask = ((m.ou2_cpu_request_bytes & 1) ? 0xff : 0) |
                                    ((m.ou2_cpu_request_bytes & 2) ? 0xff00 : 0);
                    std::fprintf(out, "M %llu %06x %04x %x\n", stamp,
                        unsigned(m.ou24_cpu_request_address), unsigned(m.ou16_cpu_request_data) & mask,
                        unsigned(m.ou2_cpu_request_bytes));
                }
                if (m.o_audio_debug_request && m.o_audio_debug_write)
                    std::fprintf(out, "S %llu %04x %02x\n", stamp,
                        unsigned(m.ou16_audio_debug_address), unsigned(m.ou8_audio_debug_data));
                if (m.o_pixel_enable) {
                    std::fprintf(out, "P %llu %u %u %u %u %u", stamp, unsigned(m.o_active),
                        unsigned(m.ou9_horizontal_position), unsigned(m.ou9_vertical_position),
                        unsigned(m.ou9_output_x), unsigned(m.ou8_output_y));
                    if (m.o_active)
                        std::fprintf(out, " %02x%02x%02x", unsigned(m.ou8_red), unsigned(m.ou8_green), unsigned(m.ou8_blue));
                    std::fputc('\n', out);
                }
            }
            if (m.o_eval_complete) {
                if (!identity_seen || !loader.reads || !state.reads || !state.writes || published_saves != 2)
                    throw std::runtime_error("Missing ROM identity or external DDR activity");
                if (m.o_eval_shared_ddr) {
                    if (!rotation_writes) throw std::runtime_error("Shared case produced no rotation traffic");
                    std::fprintf(endpoints, "SHARED_DDR rotation_writes=%llu unblanked=%u\n",
                        (unsigned long long)rotation_writes, unsigned(rotation_unblanked));
                }
                for (unsigned n = 1; n <= 6; ++n) std::fclose(traces[n]);
                std::fclose(endpoints);
                std::fclose(progress);
                std::ofstream saved("slot0.bin", std::ios::binary);
                saved.write(reinterpret_cast<const char*>(slot.data()), slot.size());
                m.final();
                return 0; // Offline comparison remains mandatory, zero exit alone is not PASS.
            }
            Verilated::timeInc(5357); m.i_chip_clk = 1; m.eval();
            Verilated::timeInc(5357); m.i_clk = 0; m.eval();
            Verilated::timeInc(5357); m.i_chip_clk = 0; m.eval();
            Verilated::timeInc(5357);
        }
        throw std::runtime_error("Bounded whole-machine cycle limit reached");
    } catch (const std::exception& error) {
        std::fprintf(stderr, "RESTORE_EVAL_FAIL %s\n", error.what()); return 2;
    }
}
