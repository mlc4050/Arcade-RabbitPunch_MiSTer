-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tile_test_support.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_sdram_types.all;

entity scanout_capture_tb is
    generic (GBOOL_PLL_CLOCK : boolean := false);
end entity;

architecture test of scanout_capture_tb is
    constant C_MAIN_ROM : t_unsigned_words := read_hex("maincpu.hex", 131072, 16);
    signal sint_rom_reads, sint_sdram_bursts : natural := 0;
    constant C_SETTINGS : t_unsigned_words := read_hex("video_settings.hex", 7, 16);
    constant C_SPRITES : t_unsigned_words := read_hex("spriteram.hex", 2048, 16);
    constant C_TILES : t_unsigned_words := read_hex("vram.hex", 8192, 16);
    constant C_BITMAP : t_unsigned_words := read_hex("bitmap.hex", 32768, 16);
    constant C_PALETTE : t_unsigned_words := read_hex("palette.hex", 1024, 16);
    signal s_reference_clk : std_logic := '0';
    signal s_clk, s_chip_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_line_valid, s_bank : std_logic := '0';
    signal s_line_ready, s_line_done : std_logic;
    signal su9_line_y, su9_background_x, su9_background_y, su9_foreground_x, su9_foreground_y : unsigned(8 downto 0) := (others => '0');
    signal su6_count, su6_priority : unsigned(5 downto 0) := (others => '0');
    signal su16_flags : unsigned(15 downto 0) := (others => '0');
    type t_rom_addresses is array (0 to 1) of unsigned(16 downto 0);
    type t_rom_words is array (0 to 1) of unsigned(31 downto 0);
    signal su2_rom_request : unsigned(1 downto 0);
    signal su2_rom_valid, su2_rom_pending : unsigned(1 downto 0) := "00";
    signal su17_rom_addresses : t_rom_addresses;
    signal su32_rom_words : t_rom_words := (others => (others => '0'));
    signal s_rom_foreground : std_logic;
    signal s_cpu_request, s_preload_done : std_logic := '0';
    signal s_cpu_response : std_logic;
    signal s_patch_request, s_patch_done : std_logic := '0';
    signal su24_cpu_address : unsigned(23 downto 0) := (others => '0');
    signal su16_cpu_data : unsigned(15 downto 0) := (others => '0');
    signal sint_cpu_writes : natural := 0;
    signal s_pixel_valid, s_pixel_bank : std_logic := '0';
    signal s_pixel_ready, s_output_valid, s_output_error : std_logic;
    signal su9_pixel_x, su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_pixel_y, su8_output_y : unsigned(7 downto 0) := (others => '0');
    signal su16_pixel_flags : unsigned(15 downto 0) := (others => '0');
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal su24_output_rgb, su24_first_rgb : unsigned(23 downto 0);
    signal s_record, s_expect_error : std_logic := '0';
    signal s_force_delay : std_logic := '0';
    signal sint_lines_done, sint_pixels, sint_max_cycles : natural := 0;
    signal s_initialize : std_logic := '1';
    signal s_scan_enable, s_scan_active, s_scan_hsync, s_scan_vsync, s_scan_hblank, s_scan_vblank : std_logic;
    signal s_armed, s_underflow : std_logic;
    signal su9_scan_x, su9_horizontal, su9_vertical : unsigned(8 downto 0);
    signal su8_scan_y, su8_scan_red, su8_scan_green, su8_scan_blue : unsigned(7 downto 0);
begin
    s_reference_clk <= not s_reference_clk after 10 ns;
    synthetic_clock : if (not GBOOL_PLL_CLOCK) generate
        s_clk <= not s_clk after 10714 ps;
        s_chip_clk <= s_clk;
    end generate;
    physical_clock : if (GBOOL_PLL_CLOCK) generate
        pll : entity work.rabbitpunch_pll
            port map (
                i_reference_clk => s_reference_clk,
                i_reset => '0',
                o_system_clk => s_clk,
                o_sdram_clk => s_chip_clk,
                o_locked => open
            );
    end generate;
    su24_output_rgb <= su8_scan_red & su8_scan_green & su8_scan_blue;
    su6_count <= C_SETTINGS(5)(5 downto 0);
    su6_priority <= C_SETTINGS(6)(5 downto 0);
    su16_flags <= C_SETTINGS(0);
    su16_pixel_flags <= C_SETTINGS(0);
    su9_background_y <= C_SETTINGS(1)(8 downto 0);
    su9_background_x <= C_SETTINGS(2)(8 downto 0);
    su9_foreground_y <= C_SETTINGS(3)(8 downto 0);
    su9_foreground_x <= C_SETTINGS(4)(8 downto 0);
    scanout : entity work.rabbitpunch_scanout
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_ready => not s_reset,
            o_main_phase_enable => open,
            o_sound_cpu_enable => open,
            o_ym_enable => open,
            o_ym_half_enable => open,
            o_adpcm_enable => open,
            o_vblank_start => open,
            o_half_frame => open,
            o_line_valid => s_line_valid,
            i_line_ready => s_line_ready,
            o_render_bank => s_bank,
            ou9_line_y => su9_line_y,
            i_line_done => s_line_done,
            o_pixel_valid => s_pixel_valid,
            i_pixel_ready => s_pixel_ready,
            o_pixel_bank => s_pixel_bank,
            ou9_pixel_x => su9_pixel_x,
            ou8_pixel_y => su8_pixel_y,
            i_rgb_valid => s_output_valid,
            i_rgb_error => s_output_error,
            iu9_rgb_x => su9_output_x,
            iu8_rgb_y => su8_output_y,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            o_pixel_enable => s_scan_enable,
            o_active => s_scan_active,
            o_hsync => s_scan_hsync,
            o_vsync => s_scan_vsync,
            o_hblank => s_scan_hblank,
            o_vblank => s_scan_vblank,
            ou9_output_x => su9_scan_x,
            ou8_output_y => su8_scan_y,
            ou8_red => su8_scan_red,
            ou8_green => su8_scan_green,
            ou8_blue => su8_scan_blue,
            ou9_horizontal_position => su9_horizontal,
            ou9_vertical_position => su9_vertical,
            o_armed => s_armed,
            o_underflow => s_underflow
        );
    dut : entity work.rabbitpunch_board_video
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            i_render_bank => s_bank,
            iu9_line_y => su9_line_y,
            iu6_sprite_count => su6_count,
            iu6_sprite_priority => su6_priority,
            iu9_background_scroll_x => su9_background_x,
            iu9_background_scroll_y => su9_background_y,
            iu9_foreground_scroll_x => su9_foreground_x,
            iu9_foreground_scroll_y => su9_foreground_y,
            iu16_video_flags => su16_flags,
            o_line_done => s_line_done,
            o_sprite_rom_request => su2_rom_request(0),
            ou17_sprite_rom_word_address => su17_rom_addresses(0),
            i_sprite_rom_response_valid => su2_rom_valid(0),
            iu32_sprite_rom_response_data => su32_rom_words(0),
            o_tile_rom_request => su2_rom_request(1),
            ou17_tile_rom_word_address => su17_rom_addresses(1),
            o_tile_rom_foreground => s_rom_foreground,
            i_tile_rom_response_valid => su2_rom_valid(1),
            iu32_tile_rom_response_data => su32_rom_words(1),
            i_pixel_valid => s_pixel_valid,
            o_pixel_ready => s_pixel_ready,
            i_pixel_bank => s_pixel_bank,
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            iu16_pixel_video_flags => su16_pixel_flags,
            o_pixel_valid => s_output_valid,
            o_pixel_error => s_output_error,
            ou9_pixel_x => su9_output_x,
            ou8_pixel_y => su8_output_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue,
            i_request => s_cpu_request,
            i_request_write => '1',
            iu24_request_address => su24_cpu_address,
            iu16_request_data => su16_cpu_data,
            iu2_request_bytes => "11",
            o_request_supported => open,
            o_response_valid => s_cpu_response,
            ou16_response_data => open,
            o_rom_request => open,
            ou18_rom_byte_address => open,
            i_rom_response_valid => '0',
            iu16_rom_response_data => (others => '0'),
            i_view_enable => '0',
            iu5_view_target => CU5_TARGET_NONE,
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open
        );
    cpu_traffic : process
        procedure write_word(vint_address : natural; vu16_data : unsigned(15 downto 0)) is
            variable vint_wait : natural := 0;
        begin
            wait until falling_edge(s_clk);
            s_cpu_request <= '1';
            su24_cpu_address <= to_unsigned(vint_address, 24);
            su16_cpu_data <= vu16_data;
            wait until falling_edge(s_clk);
            s_cpu_request <= '0';
            while (s_cpu_response /= '1' and vint_wait < 100) loop
                wait until falling_edge(s_clk);
                vint_wait := vint_wait + 1;
            end loop;
            assert (s_cpu_response = '1') report "Board video CPU write timed out" severity failure;
            wait until falling_edge(s_clk);
        end procedure;
        variable vint_writes : natural := 0;
        variable v_patch_applied : boolean := false;
    begin
        for vint_word in C_SPRITES'range loop
            write_word(16#60000# + vint_word * 2, C_SPRITES(vint_word));
        end loop;
        for vint_word in C_TILES'range loop
            write_word(16#80000# + vint_word * 2, C_TILES(vint_word));
        end loop;
        for vint_word in C_BITMAP'range loop
            write_word(16#40000# + vint_word * 2, C_BITMAP(vint_word));
        end loop;
        for vint_word in C_PALETTE'range loop
            write_word(16#A0000# + vint_word * 2, C_PALETTE(vint_word));
        end loop;
        s_preload_done <= '1';
        -- Competing CPU transactions use the real work-RAM bank throughout
        -- render/scanout. This is transaction stimulus, not executing fx68k.
        loop
            if (s_patch_request = '1' and not v_patch_applied) then
                -- X=8, Y=0 selects the high nibble of bitmap word 3.
                -- Force pen 1 and make its palette entry green through CPU writes.
                write_word(16#40006#, x"1FFF");
                write_word(16#A0000# + (512 + to_integer(C_SETTINGS(0)(3 downto 0)) * 16 + 1) * 2, x"03E0");
                v_patch_applied := true;
                s_patch_done <= '1';
            end if;
            write_word(16#FC000# + (vint_writes mod 8192) * 2, to_unsigned(vint_writes mod 65536, 16));
            vint_writes := vint_writes + 1;
            sint_cpu_writes <= vint_writes;
        end loop;
    end process;

    shared_roms : block
        component sdram_chip_model_wide is
            port (
                clk : in std_logic;
                SDRAM_DQ : inout unsigned(15 downto 0);
                SDRAM_A : in unsigned(12 downto 0);
                SDRAM_BA : in unsigned(1 downto 0);
                SDRAM_nCS : in std_logic;
                SDRAM_nWE : in std_logic;
                SDRAM_nRAS : in std_logic;
                SDRAM_nCAS : in std_logic
            );
        end component;
        signal su3_requests, su3_ready, su3_gated_ready, su3_valid : unsigned(2 downto 0);
        signal su3_client_requests, su3_cache_ready, su3_client_valid : unsigned(2 downto 0);
        signal su27_client_addresses : t_sdram_addresses;
        signal su64_client_data : t_sdram_read_data;
        signal su27_addresses : t_sdram_addresses;
        signal su64_data : t_sdram_read_data;
        signal su16_dq : unsigned(15 downto 0);
        signal su13_address : unsigned(12 downto 0);
        signal su2_bank, su2_mask : unsigned(1 downto 0);
        signal s_chip, s_write_n, s_row_n, s_column_n, s_cke, s_initialized, s_idle : std_logic;
        signal s_program_request, s_program_valid : std_logic := '0';
        signal su18_program_address : unsigned(17 downto 0) := (others => '0');
        signal su16_program_data : unsigned(15 downto 0);
    begin
        su3_gated_ready <= su3_cache_ready when s_force_delay = '0' else "000";
        rom_requests : entity work.rabbitpunch_rom_requests
            port map (
                i_clk => s_clk,
                i_sprite_request => su2_rom_request(0),
                iu17_sprite_word_address => su17_rom_addresses(0),
                o_sprite_response_valid => su2_rom_valid(0),
                ou32_sprite_response_data => su32_rom_words(0),
                i_tile_request => su2_rom_request(1),
                iu17_tile_word_address => su17_rom_addresses(1),
                i_tile_foreground => s_rom_foreground,
                o_tile_response_valid => su2_rom_valid(1),
                ou32_tile_response_data => su32_rom_words(1),
                i_cpu_request => s_program_request,
                iu18_cpu_byte_address => su18_program_address,
                o_cpu_response_valid => s_program_valid,
                ou16_cpu_response_data => su16_program_data,
                o_idle => s_idle,
                ou3_backend_requests => su3_client_requests,
                iu3_backend_ready => su3_gated_ready,
                ou27_backend_byte_addresses => su27_client_addresses,
                iu3_backend_response_valid => su3_client_valid,
                iu64_backend_read_data => su64_client_data
            );
        burst_cache : entity work.rabbitpunch_rom_cache
            port map (
                i_clk => s_clk,
                i_invalidate => '0',
                o_idle => open,
                iu3_requests => su3_client_requests,
                ou3_ready => su3_cache_ready,
                iu27_byte_addresses => su27_client_addresses,
                ou3_response_valid => su3_client_valid,
                ou64_read_data => su64_client_data,
                ou3_backend_requests => su3_requests,
                iu3_backend_ready => su3_ready,
                ou27_backend_byte_addresses => su27_addresses,
                iu3_backend_response_valid => su3_valid,
                iu64_backend_read_data => su64_data
            );
        memory_transport : entity work.rabbitpunch_sdram
            generic map (
                GINT_READ_CAPTURE_ADJUST => boolean'pos(GBOOL_PLL_CLOCK)
            )
            port map (
                i_clk => s_clk,
                i_initialize => '0',
                o_initialized => s_initialized,
                iu3_requests => su3_requests,
                ou3_ready => su3_ready,
                iu3_writes => "000",
                iu27_byte_addresses => su27_addresses,
                iu16_write_data => (others => (others => '0')),
                iu2_byte_enables => (others => "00"),
                ou3_response_valid => su3_valid,
                ou64_read_data => su64_data,
                iou16_sdram_data => su16_dq,
                ou13_sdram_address => su13_address,
                ou2_sdram_bank => su2_bank,
                ou2_sdram_byte_mask => su2_mask,
                o_sdram_chip_select => s_chip,
                o_sdram_write_n => s_write_n,
                o_sdram_row_n => s_row_n,
                o_sdram_column_n => s_column_n,
                o_sdram_clock_enable => s_cke
            );
        chip : sdram_chip_model_wide
            port map (
                clk => s_chip_clk,
                SDRAM_DQ => su16_dq,
                SDRAM_A => su13_address,
                SDRAM_BA => su2_bank,
                SDRAM_nCS => s_chip,
                SDRAM_nWE => s_write_n,
                SDRAM_nRAS => s_row_n,
                SDRAM_nCAS => s_column_n
            );
        process(s_clk)
            variable v_pending : boolean := false;
            variable vint_address, vint_reads, vint_bursts : natural := 0;
        begin
            if (rising_edge(s_clk)) then
                s_program_request <= '0';
                if (s_program_request = '1') then
                    v_pending := true;
                end if;
                if (s_program_valid = '1') then
                    assert (v_pending and su16_program_data = C_MAIN_ROM(vint_address / 2))
                        report "Shared SDRAM CPU ROM read mismatch" severity failure;
                    vint_reads := vint_reads + 1;
                    vint_address := (vint_address + 2) mod 16#40000#;
                    v_pending := false;
                elsif (not v_pending and s_initialized = '1' and s_preload_done = '1') then
                    su18_program_address <= to_unsigned(vint_address, 18);
                    s_program_request <= '1';
                end if;
                for vint_client in 0 to 2 loop
                    if (su3_requests(vint_client) = '1' and su3_ready(vint_client) = '1') then
                        vint_bursts := vint_bursts + 1;
                    end if;
                end loop;
                sint_sdram_bursts <= vint_bursts;
                sint_rom_reads <= vint_reads;
                for vint_channel in 0 to 1 loop
                    if (su2_rom_request(vint_channel) = '1') then
                        assert (su2_rom_pending(vint_channel) = '0') report "Overlapping shared graphics request" severity failure;
                        su2_rom_pending(vint_channel) <= '1';
                    elsif (su2_rom_valid(vint_channel) = '1') then
                        assert (su2_rom_pending(vint_channel) = '1') report "Unrequested shared graphics reply" severity failure;
                        su2_rom_pending(vint_channel) <= '0';
                    end if;
                end loop;
            end if;
        end process;
    end block;

    scoreboard : process(s_clk)
        file v_output : text open write_mode is "pixels.hex";
        variable v_line : line;
        variable vint_clock, vint_started, vint_max, vint_pixels, vint_lines, vint_gap : natural := 0;
        variable v_seen_output : boolean := false;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            if (s_initialize = '1') then
                vint_gap := 0;
                v_seen_output := false;
            elsif (s_scan_enable = '1') then
                vint_gap := 0;
                v_seen_output := true;
            elsif (v_seen_output) then
                vint_gap := vint_gap + 1;
                assert (vint_gap < 7) report "Physical pixel cadence stalled" severity failure;
            end if;
            if (s_reset = '0') then
                assert (s_underflow = '0' and s_output_error = '0')
                    report "Real graphics missed the continuous scanout deadline" severity failure;
                if (s_line_valid = '1' and s_line_ready = '1') then
                    vint_started := vint_clock;
                end if;
                if (s_line_done = '1') then
                    vint_lines := vint_lines + 1;
                    if (vint_clock - vint_started > vint_max) then
                        vint_max := vint_clock - vint_started;
                    end if;
                end if;
                if (s_scan_enable = '1' and s_scan_active = '1') then
                    assert (to_integer(su9_scan_x) = vint_pixels mod 288 + 8 and
                        to_integer(su8_scan_y) = vint_pixels / 288)
                        report "Continuous output frame order mismatch" severity failure;
                    write(v_line, to_hstring(su24_output_rgb));
                    writeline(v_output, v_line);
                    vint_pixels := vint_pixels + 1;
                end if;
            end if;
            sint_lines_done <= vint_lines;
            sint_pixels <= vint_pixels;
            sint_max_cycles <= vint_max;
        end if;
    end process;
    stimulus : process
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_initialize <= '0';
        wait until falling_edge(s_clk) and s_preload_done = '1';
        s_reset <= '0';
        wait until sint_pixels = 62208 for 70 ms;
        assert (sint_pixels = 62208 and s_underflow = '0' and sint_lines_done >= 216)
            report "Continuous graphics capture incomplete" severity failure;
        assert (sint_cpu_writes > 1000 and sint_rom_reads > 1000)
            report "Competing RAM/ROM traffic was absent" severity failure;
        report "SCANOUT_CAPTURE_PASS pixels=62208 max_cycles=" & integer'image(sint_max_cycles) &
            " cpu_writes=" & integer'image(sint_cpu_writes) &
            " rom_reads=" & integer'image(sint_rom_reads) &
            " bursts=" & integer'image(sint_sdram_bursts);
        std.env.finish;
        wait;
    end process;
    progress : process
        file v_progress : text open write_mode is "progress.txt";
        variable v_line : line;
    begin
        loop
            wait for 250 us;
            write(v_line, time'image(now) & "; preloaded=" & std_logic'image(s_preload_done) &
                "; lines=" & integer'image(sint_lines_done) & "; pixels=" & integer'image(sint_pixels) &
                "; underflow=" & std_logic'image(s_underflow));
            writeline(v_progress, v_line);
            flush(v_progress);
        end loop;
    end process;
end architecture;
