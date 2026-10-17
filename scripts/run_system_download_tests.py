"""Boot two downloaded 68000 diagnostics through the complete logical system."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def system_sources():
    sources = ['rtl/cpu/fx68k/fx68k.sv', 'rtl/cpu/fx68k/fx68kAlu.sv', 'rtl/cpu/fx68k/uaddrPla.sv', 'rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_decode.vhd', 'rtl/rabbitpunch_ram16.vhd', 'rtl/rabbitpunch_board_memory.vhd', 'rtl/rabbitpunch_memory.vhd', 'rtl/rabbitpunch_bus.vhd', 'rtl/rabbitpunch_fx68k.vhd', 'rtl/rabbitpunch_maincpu.vhd', 'rtl/rabbitpunch_io.vhd', 'rtl/rabbitpunch_irq.vhd', 'rtl/rabbitpunch_sdram_types.vhd', 'rtl/memory/sdram/sdram.sv', 'rtl/rabbitpunch_sdram.vhd', 'rtl/rabbitpunch_rom_requests.vhd', 'rtl/rabbitpunch_rom_cache.vhd', 'rtl/rabbitpunch_read_arbiter.vhd', 'rtl/rabbitpunch_audio_roms.vhd', 'rtl/rabbitpunch_audio_rom_transport.vhd', 'rtl/rabbitpunch_roms.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv', 'rtl/jtframe/jtframe_draw.v', 'rtl/rabbitpunch_sprite_priority.vhd', 'rtl/rabbitpunch_pixel_mixer.vhd', 'rtl/rabbitpunch_tile_row.vhd', 'rtl/rabbitpunch_tile_lookup.vhd', 'rtl/rabbitpunch_tile_layer.vhd', 'rtl/rabbitpunch_tiles.vhd', 'rtl/rabbitpunch_sprite_scan.vhd', 'rtl/rabbitpunch_sprite_row.vhd', 'rtl/rabbitpunch_sprite_line.vhd', 'rtl/rabbitpunch_sprites.vhd', 'rtl/rabbitpunch_bitmap_pixel.vhd', 'rtl/rabbitpunch_video.vhd', 'rtl/rabbitpunch_palette_pixel.vhd', 'rtl/rabbitpunch_rgb_video.vhd', 'rtl/rabbitpunch_board_video.vhd', 'rtl/rabbitpunch_board.vhd', 'rtl/rabbitpunch_download.vhd', 'rtl/cpu/t80/T80_Pack.vhd', 'rtl/cpu/t80/T80_Reg.vhd', 'rtl/cpu/t80/T80_MCode.vhd', 'rtl/cpu/t80/T80_ALU.vhd', 'rtl/cpu/t80/T80.vhd', 'rtl/cpu/t80/T80se.vhd', 'rtl/sound/jt51/hdl/jt51_acc.v', 'rtl/sound/jt51/hdl/jt51_eg.v', 'rtl/sound/jt51/hdl/jt51_exp2lin.v', 'rtl/sound/jt51/hdl/jt51_exprom.v', 'rtl/sound/jt51/hdl/jt51_kon.v', 'rtl/sound/jt51/hdl/jt51_lfo.v', 'rtl/sound/jt51/hdl/jt51_lin2exp.v', 'rtl/sound/jt51/hdl/jt51_mmr.v', 'rtl/sound/jt51/hdl/jt51_mod.v', 'rtl/sound/jt51/hdl/jt51_noise_lfsr.v', 'rtl/sound/jt51/hdl/jt51_noise.v', 'rtl/sound/jt51/hdl/jt51_op.v', 'rtl/sound/jt51/hdl/jt51_pg.v', 'rtl/sound/jt51/hdl/jt51_phinc_rom.v', 'rtl/sound/jt51/hdl/jt51_phrom.v', 'rtl/sound/jt51/hdl/jt51_pm.v', 'rtl/sound/jt51/hdl/jt51_reg_ch.v', 'rtl/sound/jt51/hdl/jt51_csr_op.v', 'rtl/sound/jt51/hdl/jt51_reg.v', 'rtl/sound/jt51/hdl/jt51_sh.v', 'rtl/sound/jt51/hdl/jt51_timers.v', 'rtl/sound/jt51/hdl/jt51.v', 'sim/vendor/jt51/sep32.v', 'sim/vendor/jt51/sep32_cnt.v', 'rtl/sound/jt7759/hdl/jt7759.v', 'rtl/sound/jt7759/hdl/jt7759_adpcm.v', 'rtl/sound/jt7759/hdl/jt7759_ctrl.v', 'rtl/sound/jt7759/hdl/jt7759_data.v', 'rtl/sound/jt7759/hdl/jt7759_div.v', 'rtl/rabbitpunch_z80.vhd', 'rtl/rabbitpunch_soundcpu.vhd', 'rtl/rabbitpunch_ym2151.vhd', 'rtl/rabbitpunch_ram8.vhd', 'rtl/rabbitpunch_sound_bus.vhd', 'rtl/rabbitpunch_sound_board.vhd', 'rtl/rabbitpunch_upd7759.vhd', 'rtl/rabbitpunch_adpcm.vhd', 'rtl/rabbitpunch_audio.vhd', 'rtl/rabbitpunch_audio_mixer.vhd', 'rtl/rabbitpunch_system.vhd', 'sim/board/system_download_tb.vhd']
    return sources


def main():
    root = core_root()
    sources = system_sources()
    result = run_case("system_download", sources, "system_download_tb", "1 ms", "SYSTEM_DOWNLOAD_PASS", wall_timeout=180)
    result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
        log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
        scope="Three synthetic 32-byte 68000 program downloads and one rejected partial image through production SDRAM; actual CPU writes and native RAM inspection, hot-cache image replacement, soft reset without reload, partial-image reset hold and recovery; logical video idle, no HPS/DDR/PLL/raster/hardware proof")
    (root / "docs/reference/system_download_checks.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
