-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.rabbitpunch_layout.all;

entity system_boot_tb is
    generic (
        GBOOL_PLL_CLOCK : boolean := false;
        GBOOL_CONTINUOUS_VIDEO : boolean := false;
        GINT_MAIN_WRITE_LIMIT : positive := 2000;
        GINT_SOUND_WRITE_LIMIT : positive := 256;
        GINT_DIP_DEFAULT : natural := 0
    );
end entity;

architecture test of system_boot_tb is
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
    signal s_reference_clk : std_logic := '0';
    signal s_clk, s_chip_clk : std_logic := '0';
    signal s_main_phase_enable, s_fractional_sound, s_fractional_ym, s_fractional_half, s_fractional_adpcm : std_logic;
    signal s_download, s_word_valid, s_pause, s_game_reset, s_view_enable : std_logic := '0';
    signal s_word_ready, s_ready, s_loading, s_image_valid, s_error, s_done, s_paused, s_view_valid : std_logic;
    signal s_cpu_request, s_cpu_write : std_logic;
    signal su27_address, su27_loaded : unsigned(26 downto 0) := (others => '0');
    signal su16_data, su16_cpu_data, su16_view_data : unsigned(15 downto 0) := (others => '0');
    signal su16_expected : unsigned(15 downto 0) := x"CAFE";
    signal su24_cpu_address : unsigned(23 downto 0);
    signal su2_cpu_bytes : unsigned(1 downto 0);
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_cpu_writes, sint_stream_words : natural := 0;
    signal s_run : std_logic := '0';
    signal s_enable, s_half_enable, s_adpcm_enable : std_logic;
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_adpcm_divider : natural range 0 to 74 := 0;
    signal s_adpcm_busy, s_sample_marker, s_audio_request, s_audio_write, s_sound_pending : std_logic;
    signal su9_adpcm_pcm : unsigned(8 downto 0);
    signal su16_audio_address : unsigned(15 downto 0);
    signal su8_audio_data, su8_audio_view_data : unsigned(7 downto 0);
    signal s_audio_view : std_logic := '0';
    signal sint_samples, sint_audio_commands : natural := 0;
    signal s_vblank_start, s_half_frame, s_line_valid, s_line_ready, s_render_bank, s_line_done : std_logic := '0';
    signal s_pixel_request, s_pixel_ready, s_pixel_bank, s_rgb_valid, s_rgb_error : std_logic := '0';
    signal su9_line_y, su9_pixel_x, su9_rgb_x : unsigned(8 downto 0) := (others => '0');
    signal su8_pixel_y, su8_rgb_y, su8_red, su8_green, su8_blue : unsigned(7 downto 0) := (others => '0');
    signal s_output_enable, s_output_active, s_output_sync, s_armed, s_underflow : std_logic := '0';
    signal su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_output_y, su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0) := (others => '0');

begin
    s_reference_clk <= not s_reference_clk after 10 ns;
    synthetic_clock : if (not GBOOL_PLL_CLOCK) generate
        s_clk <= not s_clk after 10417 ps;
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
    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => s_clk,
            i_reset => '0',
            o_pixel_enable => open,
            o_main_phase_enable => s_main_phase_enable,
            o_sound_cpu_enable => s_fractional_sound,
            o_ym_enable => s_fractional_ym,
            o_ym_half_enable => s_fractional_half,
            o_adpcm_enable => s_fractional_adpcm
        );
    s_enable <= s_fractional_sound when GBOOL_PLL_CLOCK else '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_half_enable <= s_fractional_half when GBOOL_PLL_CLOCK else '1' when sint_divider = 23 else '0';
    s_adpcm_enable <= s_fractional_adpcm when GBOOL_PLL_CLOCK else '1' when sint_adpcm_divider = 74 else '0';
    cadence : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 23) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            if (sint_adpcm_divider = 74) then
                sint_adpcm_divider <= 0;
            else
                sint_adpcm_divider <= sint_adpcm_divider + 1;
            end if;
            if (s_sample_marker = '1') then
                sint_samples <= sint_samples + 1;
            end if;
            if (s_audio_request = '1' and s_audio_write = '1' and su16_audio_address = 16#F600#) then
                sint_audio_commands <= sint_audio_commands + 1;
            end if;
        end if;
    end process;
    continuous_video : if (GBOOL_CONTINUOUS_VIDEO) generate
        scanout : entity work.rabbitpunch_scanout
            port map (
                i_clk => s_clk,
                i_initialize => '0',
                i_game_ready => s_ready,
                o_main_phase_enable => open,
                o_sound_cpu_enable => open,
                o_ym_enable => open,
                o_ym_half_enable => open,
                o_adpcm_enable => open,
                o_vblank_start => s_vblank_start,
                o_half_frame => s_half_frame,
                o_line_valid => s_line_valid,
                i_line_ready => s_line_ready,
                o_render_bank => s_render_bank,
                ou9_line_y => su9_line_y,
                i_line_done => s_line_done,
                o_pixel_valid => s_pixel_request,
                i_pixel_ready => s_pixel_ready,
                o_pixel_bank => s_pixel_bank,
                ou9_pixel_x => su9_pixel_x,
                ou8_pixel_y => su8_pixel_y,
                i_rgb_valid => s_rgb_valid,
                i_rgb_error => s_rgb_error,
                iu9_rgb_x => su9_rgb_x,
                iu8_rgb_y => su8_rgb_y,
                iu8_red => su8_red,
                iu8_green => su8_green,
                iu8_blue => su8_blue,
                o_pixel_enable => s_output_enable,
                o_active => s_output_active,
                o_hsync => open,
                o_vsync => s_output_sync,
                o_hblank => open,
                o_vblank => open,
                ou9_output_x => su9_output_x,
                ou8_output_y => su8_output_y,
                ou8_red => su8_output_red,
                ou8_green => su8_output_green,
                ou8_blue => su8_output_blue,
                ou9_horizontal_position => open,
                ou9_vertical_position => open,
                o_armed => s_armed,
                o_underflow => s_underflow
            );
    end generate;
    system : entity work.rabbitpunch_system
        generic map (
            GINT_IMAGE_BYTES => 32,
            GBOOL_EXTERNAL_PHASE_ENABLE => GBOOL_PLL_CLOCK,
            GINT_SDRAM_READ_CAPTURE_ADJUST => boolean'pos(GBOOL_PLL_CLOCK)
        )
        port map (
            i_clk => s_clk,
            i_main_phase_enable => s_main_phase_enable,
            i_initialize => '0',
            i_game_reset => s_game_reset,
            i_pause => not s_run,
            o_paused => s_paused,
            i_vblank_start => s_vblank_start,
            i_half_frame => s_half_frame,
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            i_render_bank => s_render_bank,
            iu9_line_y => su9_line_y,
            o_line_done => s_line_done,
            i_pixel_valid => s_pixel_request,
            o_pixel_ready => s_pixel_ready,
            i_pixel_bank => s_pixel_bank,
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            o_pixel_valid => s_rgb_valid,
            o_pixel_error => s_rgb_error,
            ou9_pixel_x => su9_rgb_x,
            ou8_pixel_y => su8_rgb_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue,
            i_view_enable => s_view_enable,
            iu5_view_target => CU5_TARGET_WORKRAM,
            iu15_view_word_address => (others => '0'),
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => to_unsigned(GINT_DIP_DEFAULT, 16),
            i_sound_cpu_enable => s_enable and s_run,
            i_ym_enable => s_enable,
            i_ym_half_enable => s_half_enable,
            i_adpcm_enable => s_adpcm_enable,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            ou9_adpcm_pcm => su9_adpcm_pcm,
            ou16_mono_pcm => open,
            o_audio_sample_marker => s_sample_marker,
            o_adpcm_busy => s_adpcm_busy,
            i_audio_view_enable => s_audio_view,
            iu11_audio_view_address => (others => '0'),
            ou8_audio_view_data => su8_audio_view_data,
            o_audio_debug_request => s_audio_request,
            o_audio_debug_write => s_audio_write,
            ou16_audio_debug_address => su16_audio_address,
            ou8_audio_debug_data => su8_audio_data,
            i_sound_command_read => '0',
            o_sound_command_write => open,
            ou8_sound_command => open,
            o_sound_pending => s_sound_pending,
            ou16_video_flags => open,
            ou9_scroll0_y => open,
            ou9_scroll0_x => open,
            ou9_scroll1_y => open,
            ou9_scroll1_x => open,
            ou6_sprite_count => open,
            ou6_sprite_priority => open,
            ou4_gga_selected => open,
            iu4_gga_view_address => (others => '0'),
            ou8_gga_view_data => open,
            o_gga_write => open,
            ou4_gga_write_address => open,
            ou8_gga_write_data => open,
            o_cpu_request => s_cpu_request,
            o_cpu_request_write => s_cpu_write,
            ou24_cpu_request_address => su24_cpu_address,
            ou16_cpu_request_data => su16_cpu_data,
            ou2_cpu_request_bytes => su2_cpu_bytes,
            i_download => s_download,
            i_word_valid => s_word_valid,
            o_word_ready => s_word_ready,
            iu27_word_byte_address => su27_address,
            iu16_word_data => su16_data,
            o_image_valid => s_image_valid,
            o_error => s_error,
            o_done => s_done,
            ou27_bytes_loaded => su27_loaded,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_sdram_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_chip,
            o_sdram_write_n => s_write_n,
            o_sdram_row_n => s_row_n,
            o_sdram_column_n => s_column_n,
            o_sdram_clock_enable => s_cke,
            o_ready => s_ready,
            o_loading => s_loading
        );
    chip : sdram_chip_model_wide
        port map (
            clk => s_chip_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_sdram_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_chip,
            SDRAM_nWE => s_write_n,
            SDRAM_nRAS => s_row_n,
            SDRAM_nCAS => s_column_n
        );

    monitor : process(s_clk)
        file main_trace : text open write_mode is "rtl_main_writes.txt";
        file sound_trace : text open write_mode is "rtl_sound_writes.txt";
        file progress_file : text open write_mode is "progress.txt";
        file pixel_file : text open write_mode is "boot_pixels.hex";
        variable v_line : line;
        variable vu16_mask : unsigned(15 downto 0);
        variable vint_main, vint_sound : natural := 0;
        variable vint_progress : natural range 0 to 47999 := 0;
        variable vint_pixels, vint_frames, vint_lines, vint_render_cycles, vint_max_line_cycles : natural := 0;
        variable v_rendering : boolean := false;
        variable v_previous_sync : std_logic := '1';
    begin
        if (rising_edge(s_clk)) then
            if (s_run = '1') then
                if (GBOOL_CONTINUOUS_VIDEO) then
                    assert (s_underflow = '0' and s_error = '0')
                        report "Live CPU/video boot reported underflow or load error" severity failure;
                    if (s_line_valid = '1' and s_line_ready = '1') then
                        assert (not v_rendering) report "Overlapping live video rows" severity failure;
                        v_rendering := true;
                        vint_render_cycles := 0;
                    end if;
                    if (v_rendering) then
                        vint_render_cycles := vint_render_cycles + 1;
                    end if;
                    if (s_line_done = '1') then
                        assert (v_rendering and vint_render_cycles <= 3024)
                            report "Live render row exceeded line budget" severity failure;
                        v_rendering := false;
                        vint_lines := vint_lines + 1;
                        if (vint_render_cycles > vint_max_line_cycles) then
                            vint_max_line_cycles := vint_render_cycles;
                        end if;
                    end if;
                    if (s_output_enable = '1') then
                        if (s_output_sync = '0' and v_previous_sync = '1') then
                            vint_frames := vint_frames + 1;
                        end if;
                        v_previous_sync := s_output_sync;
                        if (s_output_active = '1' and vint_pixels < 62208) then
                            assert (su9_output_x = to_unsigned(8 + (vint_pixels mod 288), 9) and
                                    su8_output_y = to_unsigned(vint_pixels / 288, 8))
                                report "Live boot RGB coordinate ordering mismatch" severity failure;
                            for vint_bit in 0 to 7 loop
                                assert ((su8_output_red(vint_bit) = '0' or su8_output_red(vint_bit) = '1') and
                                        (su8_output_green(vint_bit) = '0' or su8_output_green(vint_bit) = '1') and
                                        (su8_output_blue(vint_bit) = '0' or su8_output_blue(vint_bit) = '1'))
                                    report "Unknown live boot RGB bit" severity failure;
                            end loop;
                            hwrite(v_line, su8_output_red & su8_output_green & su8_output_blue);
                            writeline(pixel_file, v_line);
                            vint_pixels := vint_pixels + 1;
                        end if;
                    end if;
                end if;
                if (s_cpu_request = '1' and s_cpu_write = '1' and vint_main < GINT_MAIN_WRITE_LIMIT) then
                    hwrite(v_line, su24_cpu_address and x"0FFFFF");
                    write(v_line, string'(" "));
                    vu16_mask := (others => '0');
                    if (su2_cpu_bytes(1) = '1') then
                        vu16_mask(15 downto 8) := (others => '1');
                    end if;
                    if (su2_cpu_bytes(0) = '1') then
                        vu16_mask(7 downto 0) := (others => '1');
                    end if;
                    hwrite(v_line, vu16_mask);
                    write(v_line, string'(" "));
                    hwrite(v_line, su16_cpu_data and vu16_mask);
                    writeline(main_trace, v_line);
                    vint_main := vint_main + 1;
                end if;
                if (s_audio_request = '1' and s_audio_write = '1' and vint_sound < GINT_SOUND_WRITE_LIMIT) then
                    hwrite(v_line, su16_audio_address);
                    write(v_line, string'(" "));
                    write(v_line, string'("FF "));
                    hwrite(v_line, su8_audio_data);
                    writeline(sound_trace, v_line);
                    vint_sound := vint_sound + 1;
                end if;
                if (vint_progress = 47999) then
                    write(v_line, now);
                    write(v_line, string'(" main="));
                    write(v_line, vint_main);
                    write(v_line, string'(" sound="));
                    write(v_line, vint_sound);
                    write(v_line, string'(" pixels="));
                    write(v_line, vint_pixels);
                    write(v_line, string'(" lines="));
                    write(v_line, vint_lines);
                    writeline(progress_file, v_line);
                    flush(progress_file);
                    vint_progress := 0;
                else
                    vint_progress := vint_progress + 1;
                end if;
                if (vint_main = GINT_MAIN_WRITE_LIMIT and vint_sound = GINT_SOUND_WRITE_LIMIT and
                        (not GBOOL_CONTINUOUS_VIDEO or (vint_pixels = 62208 and vint_frames >= 2))) then
                    report "SYSTEM_BOOT_PASS main_writes=" & integer'image(vint_main) &
                        " sound_writes=" & integer'image(vint_sound) &
                        " video_pixels=" & integer'image(vint_pixels) &
                        " frames=" & integer'image(vint_frames) &
                        " lines=" & integer'image(vint_lines) &
                        " max_line_cycles=" & integer'image(vint_max_line_cycles);
                    finish;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        file header : text open read_mode is "main_header.hex";
        variable v_line : line;
        variable vu16_word : unsigned(15 downto 0);
    begin
        wait until falling_edge(s_clk);
        s_download <= '1';
        for vint_word in 0 to 15 loop
            if (s_word_ready /= '1') then
                wait until s_word_ready = '1' for 200 us;
            end if;
            assert (s_word_ready = '1') report "Boot header download stalled" severity failure;
            wait until falling_edge(s_clk);
            readline(header, v_line);
            hread(v_line, vu16_word);
            su27_address <= to_unsigned(vint_word * 2, 27);
            su16_data <= vu16_word;
            s_word_valid <= '1';
            wait until falling_edge(s_clk);
            s_word_valid <= '0';
        end loop;
        s_download <= '0';
        wait until s_ready = '1' for 10 us;
        assert (s_ready = '1' and s_image_valid = '1' and s_error = '0')
            report "Boot header did not release system reset" severity failure;
        wait;
    end process;
    process
    begin
        wait for 100 ms;
        assert false report "Connected system boot timeout" severity failure;
    end process;
end architecture;
