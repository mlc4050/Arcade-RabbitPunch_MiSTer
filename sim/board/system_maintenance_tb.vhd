-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity system_maintenance_tb is
end entity;

architecture test of system_maintenance_tb is
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
    signal su16_mono_pcm : unsigned(15 downto 0);
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
    signal s_maintenance_access, s_maintenance_valid, s_maintenance_write : std_logic := '0';
    signal s_maintenance_ready, s_maintenance_response, s_maintenance_pause : std_logic;
    signal su14_maintenance_address : unsigned(13 downto 0) := (others => '0');
    signal su8_maintenance_data, su8_maintenance_response : unsigned(7 downto 0) := (others => '0');
    signal su15_view_address : unsigned(14 downto 0) := (others => '0');
    signal su16_score_expected : unsigned(15 downto 0) := x"A55A";
    signal sint_score_matches : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    system : entity work.rabbitpunch_system
        generic map (sint_IMAGE_BYTES => 64)
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            i_game_reset => s_game_reset,
            i_pause => s_pause,
            o_paused => s_paused,
            i_maintenance_access => s_maintenance_access,
            i_maintenance_valid => s_maintenance_valid,
            i_maintenance_write => s_maintenance_write,
            iu14_maintenance_byte_address => su14_maintenance_address,
            iu8_maintenance_data => su8_maintenance_data,
            o_maintenance_ready => s_maintenance_ready,
            o_maintenance_response_valid => s_maintenance_response,
            ou8_maintenance_response_data => su8_maintenance_response,
            o_maintenance_pause => s_maintenance_pause,
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
            iu15_view_word_address => su15_view_address,
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => (others => '0'),
            i_sound_cpu_enable => '0',
            i_ym_enable => '0',
            i_ym_half_enable => '0',
            i_adpcm_enable => '0',
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            ou9_adpcm_pcm => open,
            ou16_mono_pcm => su16_mono_pcm,
            o_audio_sample_marker => open,
            o_adpcm_busy => open,
            i_audio_view_enable => '0',
            iu11_audio_view_address => (others => '0'),
            ou8_audio_view_data => open,
            o_audio_debug_request => open,
            o_audio_debug_write => open,
            ou16_audio_debug_address => open,
            ou8_audio_debug_data => open,
            i_sound_command_read => '0',
            o_sound_command_write => open,
            ou8_sound_command => open,
            o_sound_pending => open,
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
            assert (su16_mono_pcm = 0) report "Disabled audio clocks must keep mixed PCM silent" severity failure;
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
                assert (su2_cpu_bytes = "11") report "Maintenance CPU probe used unexpected byte mask" severity failure;
                case to_integer(su24_cpu_address) is
                    when 16#FFE00# =>
                        assert (su16_cpu_data = x"A55A") report "Score initialization mismatch" severity failure;
                    when 16#FC000# | 16#C0004# =>
                        assert (su16_cpu_data = su16_expected) report "CPU image marker mismatch" severity failure;
                    when 16#FC002# =>
                        assert (su16_cpu_data = x"A55A" or su16_cpu_data = x"A511" or su16_cpu_data = x"3311")
                            report "CPU read a corrupted maintained score word" severity failure;
                        if (su16_cpu_data = su16_score_expected) then
                            sint_score_matches <= sint_score_matches + 1;
                        end if;
                    when others =>
                        assert false report "Maintenance CPU probe wrote outside its RAM/IO cells" severity failure;
                end case;
                sint_cpu_writes <= sint_cpu_writes + 1;
            end if;
        end if;
    end process;
    stimulus : process
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure load_program(vu16_value : unsigned(15 downto 0); v_io : boolean := false) is
            variable vu16_word : unsigned(15 downto 0);
        begin
            s_download <= '1';
            for vint_word in 0 to 31 loop
                if (s_word_ready /= '1') then
                    wait until s_word_ready = '1' for 200 us;
                end if;
                assert (s_word_ready = '1') report "System image stream stalled" severity failure;
                wait until falling_edge(s_clk);
                -- Diagnostics either read the score word or exercise queued I/O reset.
                if (v_io) then
                    case vint_word is
                        when 0 => vu16_word := x"000F";
                        when 1 => vu16_word := x"FFFC";
                        when 2 => vu16_word := x"0000";
                        when 3 => vu16_word := x"0008";
                        when 4 | 8 => vu16_word := x"33FC";
                        when 5 | 9 => vu16_word := vu16_value;
                        when 6 => vu16_word := x"000C";
                        when 7 => vu16_word := x"0004";
                        when 10 => vu16_word := x"000F";
                        when 11 => vu16_word := x"C000";
                        when 12 => vu16_word := x"60EE";
                        when others => vu16_word := x"4E71";
                    end case;
                else
                    case vint_word is
                        when 0 => vu16_word := x"000F";
                        when 1 => vu16_word := x"FFFC";
                        when 2 => vu16_word := x"0000";
                        when 3 => vu16_word := x"0008";
                        when 4 | 8 => vu16_word := x"33FC";
                        when 5 => vu16_word := x"A55A";
                        when 6 | 10 | 13 | 15 => vu16_word := x"000F";
                        when 7 | 14 => vu16_word := x"FE00";
                        when 9 => vu16_word := vu16_value;
                        when 11 => vu16_word := x"C000";
                        when 12 => vu16_word := x"33F9";
                        when 16 => vu16_word := x"C002";
                        when 17 => vu16_word := x"60EC";
                        when others => vu16_word := x"4E71";
                    end case;
                end if;
                su27_address <= to_unsigned(vint_word * 2, 27);
                su16_data <= vu16_word(7 downto 0) & vu16_word(15 downto 8);
                s_word_valid <= '1';
                cycles(1);
                s_word_valid <= '0';
                su27_address <= (others => '1');
                su16_data <= (others => '1');
            end loop;
            s_download <= '0';
            wait until s_ready = '1' for 10 us;
            assert (s_ready = '1' and s_image_valid = '1' and s_error = '0' and su27_loaded = 64)
                report "System did not start complete program image" severity failure;
            su16_expected <= vu16_value;
            cycles(1);
        end procedure;
        procedure wait_writes(vint_target : natural) is
        begin
            if (sint_cpu_writes < vint_target) then
                wait until sint_cpu_writes >= vint_target for 100 us;
            end if;
            assert (sint_cpu_writes >= vint_target) report "Downloaded CPU program did not execute" severity failure;
            cycles(1);
        end procedure;
        procedure inspect(vint_word : natural; vu16_value : unsigned(15 downto 0)) is
        begin
            assert (s_paused = '1') report "Native state inspection before both CPU adapters drained" severity failure;
            s_view_enable <= '1';
            su15_view_address <= to_unsigned(vint_word, 15);
            cycles(4);
            assert (s_view_valid = '1' and su16_view_data = vu16_value) report "Maintained native RAM word mismatch" severity failure;
            s_view_enable <= '0';
            cycles(1);
        end procedure;
        procedure maintenance_byte(vint_address, vint_data : natural; v_write : std_logic) is
        begin
            if (s_maintenance_ready /= '1') then
                wait until s_maintenance_ready = '1' for 20 us;
            end if;
            assert (s_maintenance_ready = '1' and s_paused = '1') report "Maintenance did not await both paused CPUs" severity failure;
            cycles(1);
            su14_maintenance_address <= to_unsigned(vint_address, 14);
            su8_maintenance_data <= to_unsigned(vint_data, 8);
            s_maintenance_write <= v_write;
            s_maintenance_valid <= '1';
            cycles(1);
            s_maintenance_valid <= '0';
            wait until s_maintenance_response = '1' for 20 us;
            assert (s_maintenance_response = '1') report "Integrated maintenance response timeout" severity failure;
            if (v_write = '0') then
                assert (su8_maintenance_response = vint_data) report "Integrated maintenance byte read mismatch" severity failure;
            end if;
            cycles(1);
        end procedure;
        procedure wait_score(vu16_value : unsigned(15 downto 0)) is
            variable vint_before : natural;
        begin
            su16_score_expected <= vu16_value;
            vint_before := sint_score_matches;
            s_maintenance_access <= '0';
            wait until sint_score_matches > vint_before for 100 us;
            assert (sint_score_matches > vint_before) report "Running CPU did not consume restored score bytes" severity failure;
            s_maintenance_access <= '1';
            if (s_maintenance_ready /= '1') then
                wait until s_maintenance_ready = '1' for 20 us;
            end if;
            assert (s_paused = '1' and s_maintenance_ready = '1') report "Maintenance failed to reacquire paused work RAM" severity failure;
        end procedure;
    begin
        cycles(4);
        load_program(x"CAFE");
        wait_writes(5);
        s_maintenance_access <= '1';
        maintenance_byte(16#3E01#, 16#5A#, '0');
        maintenance_byte(16#3E01#, 16#11#, '1');
        maintenance_byte(16#3E00#, 16#A5#, '0');
        inspect(16#1F00#, x"A511");
        wait_score(x"A511");
        inspect(1, x"A511");
        maintenance_byte(16#3E00#, 16#33#, '1');
        maintenance_byte(16#3E01#, 16#11#, '0');
        wait_score(x"3311");
        inspect(1, x"3311");
        maintenance_byte(16#3FFE#, 16#44#, '1');
        maintenance_byte(16#3FFF#, 16#55#, '1');
        maintenance_byte(16#3FFF#, 16#55#, '0');
        inspect(16#1FFF#, x"4455");
        -- Ending maintenance must not release an independent user pause.
        s_pause <= '1';
        s_maintenance_access <= '0';
        cycles(20);
        assert (s_paused = '1' and s_maintenance_pause = '0') report "Maintenance release canceled user pause" severity failure;
        s_maintenance_access <= '1';
        s_pause <= '0';
        cycles(3);
        -- Reset after client acceptance but before its queued backend access.
        su14_maintenance_address <= to_unsigned(16#3E01#, 14);
        s_maintenance_write <= '0';
        s_maintenance_valid <= '1';
        cycles(1);
        s_maintenance_valid <= '0';
        s_game_reset <= '1';
        s_maintenance_access <= '0';
        for vint_cycle in 1 to 30 loop
            cycles(1);
            assert (s_maintenance_response = '0') report "Reset leaked a stale maintenance client response" severity failure;
        end loop;
        assert (s_maintenance_pause = '0') report "Reset stranded queued maintenance bus ownership" severity failure;
        su16_score_expected <= x"A55A";
        s_game_reset <= '0';
        wait_writes(sint_cpu_writes + 5);
        s_maintenance_access <= '1';
        maintenance_byte(16#3E01#, 16#5A#, '0');
        s_maintenance_access <= '0';
        -- Image replacement on an offered IO write must still drain its ack.
        load_program(x"BEEF", true);
        wait until s_cpu_request = '1' and s_cpu_write = '1' and su24_cpu_address = 16#C0004# for 100 us;
        assert (s_cpu_request = '1' and su24_cpu_address = 16#C0004#) report "IO reset-boundary probe did not execute" severity failure;
        load_program(x"CAFE");
        wait_writes(sint_cpu_writes + 5);
        s_maintenance_access <= '1';
        maintenance_byte(16#3E01#, 16#5A#, '0');
        inspect(16#1F00#, x"A55A");
        -- A queued ROM fetch also belongs to the previous image generation.
        s_maintenance_access <= '0';
        wait until s_cpu_request = '1' and s_cpu_write = '0' and su24_cpu_address < 16#40000# for 100 us;
        assert (s_cpu_request = '1' and s_cpu_write = '0') report "ROM ownership-boundary probe did not execute" severity failure;
        load_program(x"BEEF");
        wait_writes(sint_cpu_writes + 5);
        s_maintenance_access <= '1';
        maintenance_byte(16#3E01#, 16#5A#, '0');
        inspect(16#1F00#, x"A55A");
        assert (sint_stream_words = 128 and s_error = '0') report "Maintenance/IO boundary broke ROM generation handoff" severity failure;
        report "SYSTEM_MAINTENANCE_PASS cpu_consumes_restored_bytes=checked both_cpu_pause=checked byte_lanes=checked queued_reset_drain=checked io_reset_download=checked rom_queue_download=checked user_pause=preserved images=4";
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "System downloaded-program timeout" severity failure;
    end process;
end architecture;
