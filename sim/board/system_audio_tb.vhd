-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity system_audio_tb is
end entity;

architecture test of system_audio_tb is
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
    signal s_enable, s_half_enable, s_adpcm_enable : std_logic;
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_adpcm_divider : natural range 0 to 74 := 0;
    signal s_adpcm_busy, s_sample_marker, s_audio_request, s_audio_write, s_sound_pending : std_logic;
    signal su16_mono_pcm : unsigned(15 downto 0);
    signal su9_adpcm_pcm : unsigned(8 downto 0);
    signal su16_audio_address : unsigned(15 downto 0);
    signal su8_audio_data, su8_audio_view_data : unsigned(7 downto 0);
    signal s_audio_view : std_logic := '0';
    signal sint_samples, sint_audio_commands : natural := 0;
    signal s_maintenance_access, s_maintenance_valid, s_maintenance_write : std_logic := '0';
    signal s_maintenance_ready, s_maintenance_response : std_logic;
    signal su8_maintenance_response : unsigned(7 downto 0);
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
            if (s_audio_request = '1' and s_audio_write = '1' and su16_audio_address = 16#F400#) then
                assert (su8_audio_data(7 downto 1) = "1000000" and su8_audio_data(0) = su16_expected(0))
                    report "Sound handler selected the wrong sample bank/reset control" severity failure;
            end if;
            if (s_audio_request = '1' and s_audio_write = '1' and su16_audio_address = 16#F600#) then
                sint_audio_commands <= sint_audio_commands + 1;
            end if;
        end if;
    end process;
    system : entity work.rabbitpunch_system
        generic map (GINT_IMAGE_BYTES => 32)
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            i_game_reset => s_game_reset,
            i_pause => s_pause,
            o_paused => s_paused,
            i_maintenance_access => s_maintenance_access,
            i_maintenance_valid => s_maintenance_valid,
            i_maintenance_write => s_maintenance_write,
            iu14_maintenance_byte_address => to_unsigned(16#200#, 14),
            iu8_maintenance_data => x"5A",
            o_maintenance_ready => s_maintenance_ready,
            o_maintenance_response_valid => s_maintenance_response,
            ou8_maintenance_response_data => su8_maintenance_response,
            o_maintenance_pause => open,
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
            iu5_view_target => CU5_TARGET_WORKRAM,
            iu15_view_word_address => (others => '0'),
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => (others => '0'),
            i_sound_cpu_enable => s_enable,
            i_ym_enable => s_enable,
            i_ym_half_enable => s_half_enable,
            i_adpcm_enable => s_adpcm_enable,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            ou9_adpcm_pcm => su9_adpcm_pcm,
            ou16_mono_pcm => su16_mono_pcm,
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

    pcm_defined : process(s_clk)
    begin
        if (rising_edge(s_clk) and now > 1 us) then
            for vint_bit in su16_mono_pcm'range loop
                assert (su16_mono_pcm(vint_bit) = '0' or su16_mono_pcm(vint_bit) = '1')
                    report "Mixed PCM is undefined during startup/reset/playback" severity failure;
            end loop;
        end if;
    end process;
    monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_word_valid = '1' and s_word_ready = '1') then
                sint_stream_words <= sint_stream_words + 1;
            end if;
            if (s_loading = '1') then
                assert (s_cpu_request /= '1') report "CPU requested during image loading" severity failure;
            end if;
            if (s_cpu_request = '1' and s_cpu_write = '1') then
                assert (su24_cpu_address = 16#0C000E# and su2_cpu_bytes = "11" and su16_cpu_data = su16_expected)
                    report "Downloaded 68000 program wrote the wrong value/address" severity failure;
                sint_cpu_writes <= sint_cpu_writes + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_before : natural;
        procedure cycles(vint_count : positive; v_abort : boolean := false) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure load_program(vu16_value : unsigned(15 downto 0)) is
            variable vu16_word : unsigned(15 downto 0);
        begin
            s_download <= '1';
            for vint_word in 0 to 15 loop
                if (s_word_ready /= '1') then
                    wait until s_word_ready = '1' for 200 us;
                end if;
                assert (s_word_ready = '1') report "System image stream stalled" severity failure;
                wait until falling_edge(s_clk);
                -- SP=$000ffffc, PC=$8, MOVE.W #command,$000c000e, STOP #$2700.
                case vint_word is
                    when 0 => vu16_word := x"000F";
                    when 1 => vu16_word := x"FFFC";
                    when 2 => vu16_word := x"0000";
                    when 3 => vu16_word := x"0008";
                    when 4 => vu16_word := x"33FC";
                    when 5 => vu16_word := vu16_value;
                    when 6 => vu16_word := x"000C";
                    when 7 => vu16_word := x"000E";
                    when 8 => vu16_word := x"4E72";
                    when 9 => vu16_word := x"2700";
                    when others => vu16_word := x"4E71";
                end case;
                su27_address <= to_unsigned(vint_word * 2, 27);
                su16_data <= vu16_word(7 downto 0) & vu16_word(15 downto 8);
                s_word_valid <= '1';
                cycles(1);
                s_word_valid <= '0';
                su27_address <= (others => '1');
                su16_data <= (others => '1');
            end loop;
            assert (s_adpcm_busy = '0' and su9_adpcm_pcm = 0 and su16_mono_pcm = 0)
                report "Image download did not abort/mute sample playback" severity failure;
            s_download <= '0';
            wait until s_ready = '1' for 10 us;
            assert (s_ready = '1' and s_image_valid = '1' and s_error = '0' and su27_loaded = 32)
                report "System did not start complete program image" severity failure;
            su16_expected <= vu16_value;
            cycles(1);
        end procedure;
        procedure playback(vu16_command : unsigned(15 downto 0); vint_count : positive; v_abort : boolean := false) is
            variable vint_samples_before : natural;
        begin
            load_program(vu16_command);
            if (sint_audio_commands < vint_count) then
                wait until sint_audio_commands = vint_count for 200 us;
            end if;
            assert (sint_cpu_writes = vint_count and sint_audio_commands = vint_count and s_sound_pending = '0')
                report "Main CPU command did not reach/clear sound latch and trigger sample" severity failure;
            if (s_adpcm_busy /= '1') then
                wait until s_adpcm_busy = '1' for 100 us;
            end if;
            wait until su9_adpcm_pcm /= 0 for 3 ms;
            assert (s_adpcm_busy = '1' and su9_adpcm_pcm /= 0)
                report "CPU-commanded sample did not produce PCM" severity failure;
            if (v_abort) then
                return;
            end if;
            if (vint_count = 2) then
                s_maintenance_access <= '1';
            else
                s_pause <= '1';
            end if;
            if (s_paused /= '1') then
                wait until s_paused = '1' for 20 us;
            end if;
            assert (s_paused = '1') report "Both CPUs did not pause/drain" severity failure;
            if (vint_count = 2) then
                if (s_maintenance_ready /= '1') then
                    wait until s_maintenance_ready = '1' for 20 us;
                end if;
                assert (s_maintenance_ready = '1' and s_adpcm_busy = '1')
                    report "Maintenance did not acquire both CPUs during active sample playback" severity failure;
                for vint_access in 0 to 1 loop
                    cycles(1);
                    if (vint_access = 0) then
                        s_maintenance_write <= '1';
                    else
                        s_maintenance_write <= '0';
                    end if;
                    s_maintenance_valid <= '1';
                    cycles(1);
                    s_maintenance_valid <= '0';
                    wait until s_maintenance_response = '1' for 20 us;
                    assert (s_maintenance_response = '1') report "Maintenance stalled audio playback" severity failure;
                    if (vint_access = 1) then
                        assert (su8_maintenance_response = x"5A") report "Maintenance RAM round-trip failed during sound playback" severity failure;
                    end if;
                    cycles(2);
                end loop;
            end if;
            cycles(3);
            s_audio_view <= '1';
            cycles(3);
            assert (su8_audio_view_data = vu16_command(7 downto 0))
                report "Sound command not stored in native sound RAM" severity failure;
            s_audio_view <= '0';
            vint_samples_before := sint_samples;
            wait until s_adpcm_busy = '0' for 3 ms;
            assert (s_adpcm_busy = '0') report "Sample stalled while CPUs paused" severity failure;
            cycles(1600);
            assert (sint_samples >= vint_samples_before + 2 and sint_audio_commands = vint_count)
                report "Pause stopped YM cadence or allowed extra commands" severity failure;
            s_pause <= '0';
            s_maintenance_access <= '0';
            cycles(2);
        end procedure;
    begin
        cycles(4);
        playback(x"0042", 1);
        playback(x"0043", 2);
        -- Replace an image while real PCM is playing, then prove recovery.
        playback(x"0042", 3, true);
        playback(x"0043", 4);
        assert (sint_stream_words = 64 and s_error = '0')
            report "Audio system replacement downloads failed" severity failure;
        report "SYSTEM_AUDIO_PASS images=4 main_commands=4 sound_commands=4 download_aborts_active_sample=checked native_sound_ram=checked paused_playback=checked maintenance_pause=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 8 ms;
        assert false report "System audio diagnostic timeout" severity failure;
    end process;
end architecture;
