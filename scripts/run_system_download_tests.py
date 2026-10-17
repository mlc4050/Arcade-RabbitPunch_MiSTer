"""Boot two downloaded 68000 diagnostics through the complete logical system."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case


def main():
    root = core_root()
    sources = ['rtl/cpu/fx68k/fx68k.sv', 'rtl/cpu/fx68k/fx68kAlu.sv', 'rtl/cpu/fx68k/uaddrPla.sv', 'rtl/rabbitpunch_layout.vhd', 'rtl/rabbitpunch_decode.vhd', 'rtl/rabbitpunch_ram16.vhd', 'rtl/rabbitpunch_board_memory.vhd', 'rtl/rabbitpunch_memory.vhd', 'rtl/rabbitpunch_bus.vhd', 'rtl/rabbitpunch_fx68k.vhd', 'rtl/rabbitpunch_maincpu.vhd', 'rtl/rabbitpunch_io.vhd', 'rtl/rabbitpunch_irq.vhd', 'rtl/rabbitpunch_sdram_types.vhd', 'rtl/memory/sdram/sdram.sv', 'rtl/rabbitpunch_sdram.vhd', 'rtl/rabbitpunch_rom_requests.vhd', 'rtl/rabbitpunch_rom_cache.vhd', 'rtl/rabbitpunch_read_arbiter.vhd', 'rtl/rabbitpunch_audio_roms.vhd', 'rtl/rabbitpunch_audio_rom_transport.vhd', 'rtl/rabbitpunch_roms.vhd', 'sim/vendor/sdram/sdram_chip_model_wide.sv', 'rtl/jtframe/jtframe_draw.v', 'rtl/rabbitpunch_sprite_priority.vhd', 'rtl/rabbitpunch_pixel_mixer.vhd', 'rtl/rabbitpunch_tile_row.vhd', 'rtl/rabbitpunch_tile_lookup.vhd', 'rtl/rabbitpunch_tile_layer.vhd', 'rtl/rabbitpunch_tiles.vhd', 'rtl/rabbitpunch_sprite_scan.vhd', 'rtl/rabbitpunch_sprite_row.vhd', 'rtl/rabbitpunch_sprite_line.vhd', 'rtl/rabbitpunch_sprites.vhd', 'rtl/rabbitpunch_bitmap_pixel.vhd', 'rtl/rabbitpunch_video.vhd', 'rtl/rabbitpunch_palette_pixel.vhd', 'rtl/rabbitpunch_rgb_video.vhd', 'rtl/rabbitpunch_board_video.vhd', 'rtl/rabbitpunch_board.vhd', 'rtl/rabbitpunch_download.vhd', 'rtl/rabbitpunch_system.vhd', 'sim/board/system_download_tb.vhd']
    result = run_case("system_download", sources, "system_download_tb", "1 ms", "SYSTEM_DOWNLOAD_PASS", wall_timeout=180)
    result.update(source_sha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
        log_sha256=hashlib.sha256((root / result["log"]).read_bytes()).hexdigest(),
        scope="Three synthetic 32-byte 68000 program downloads and one rejected partial image through production SDRAM; actual CPU writes and native RAM inspection, hot-cache image replacement, soft reset without reload, partial-image reset hold and recovery; logical video idle, no HPS/DDR/PLL/raster/hardware proof")
    (root / "docs/reference/system_download_checks.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
