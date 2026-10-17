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
        MAIN_WRITE_LIMIT : positive := 2000;
        SOUND_WRITE_LIMIT : positive := 256;
        DIP_DEFAULT : natural := 0
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
    signal s_clk : std_logic := '0';
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
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_half_enable <= '1' when sint_divider = 23 else '0';
    s_adpcm_enable <= '1' when sint_adpcm_divider = 74 else '0';
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
    system : entity work.rabbitpunch_system
        generic map (sint_IMAGE_BYTES => 32)
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            i_game_reset => s_game_reset,
            i_pause => not s_run,
            o_paused => s_paused,
            i_vblank_start => '0',
            i_half_frame => '0',
            i_line_valid => '0',
            o_line_ready => open,
            i_render_bank => '0',
            iu9_line_y => (others => '0'),
            o_line_done => open,
            i_pixel_valid => '0',
            o_pixel_ready => open,
            i_pixel_bank => '0',
            iu9_pixel_x => (others => '0'),
            iu8_pixel_y => (others => '0'),
            o_pixel_valid => open,
            o_pixel_error => open,
            ou9_pixel_x => open,
            ou8_pixel_y => open,
            ou8_red => open,
            ou8_green => open,
            ou8_blue => open,
            i_view_enable => s_view_enable,
            iu5_view_target => TARGET_WORKRAM,
            iu15_view_word_address => (others => '0'),
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => to_unsigned(DIP_DEFAULT, 16),
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
            clk => s_clk,
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
        variable v_line : line;
        variable vu16_mask : unsigned(15 downto 0);
        variable vint_main, vint_sound : natural := 0;
        variable vint_progress : natural range 0 to 47999 := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_run = '1') then
                if (s_cpu_request = '1' and s_cpu_write = '1' and vint_main < MAIN_WRITE_LIMIT) then
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
                if (s_audio_request = '1' and s_audio_write = '1' and vint_sound < SOUND_WRITE_LIMIT) then
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
                    writeline(progress_file, v_line);
                    flush(progress_file);
                    vint_progress := 0;
                else
                    vint_progress := vint_progress + 1;
                end if;
                if (vint_main = MAIN_WRITE_LIMIT and vint_sound = SOUND_WRITE_LIMIT) then
                    report "SYSTEM_BOOT_PASS main_writes=" & integer'image(vint_main) &
                        " sound_writes=" & integer'image(vint_sound);
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
