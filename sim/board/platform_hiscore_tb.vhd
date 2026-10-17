-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.rabbitpunch_layout.all;

entity platform_hiscore_tb is
end entity;

architecture test of platform_hiscore_tb is
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
    signal su128_status : unsigned(127 downto 0) := (others => '0');
    signal su32_joystick0 : unsigned(31 downto 0) := x"00000019";
    signal su32_joystick1 : unsigned(31 downto 0) := x"00000026";
    signal su11_key_event : unsigned(10 downto 0) := (others => '0');
    signal su15_view_address : unsigned(14 downto 0) := (others => '0');
    signal su8_player1, su8_player2, su8_service : unsigned(7 downto 0);
    signal su16_dips : unsigned(15 downto 0);
    signal s_osd_open : std_logic := '0';
    signal s_user_paused, s_ddr_owner : std_logic;
    signal su4_seen_writes : unsigned(3 downto 0) := (others => '0');
    signal su16_mono_pcm : unsigned(15 downto 0);
    signal s_copy_initialize : std_logic := '1';
    signal s_framework_reset : std_logic := '1';
    signal s_host_download, s_host_write : std_logic := '0';
    signal s_ddr_mode, s_host_wait : std_logic;
    signal su16_host_index : unsigned(15 downto 0) := (others => '0');
    signal su27_host_address : unsigned(26 downto 0) := (others => '0');
    signal su8_host_data : unsigned(7 downto 0) := (others => '0');
    signal s_ddr_busy, s_ddr_read, s_ddr_write : std_logic;
    signal s_ddr_valid : std_logic := '0';
    signal su8_ddr_burst, su8_ddr_bytes : unsigned(7 downto 0);
    signal su29_ddr_address : unsigned(28 downto 0);
    signal su64_ddr_data, su64_ddr_write_data : unsigned(63 downto 0) := (others => '0');
    signal sint_cycles, sint_ddr_reads : natural := 0;
    signal sint_epoch : natural range 0 to 1 := 0;
    function image_word(vint_index, vint_epoch : natural) return unsigned is
        variable vu16_word : unsigned(15 downto 0);
    begin
        case vint_index is
            when 0 => vu16_word := x"000F";
            when 1 => vu16_word := x"FFFC";
            when 2 => vu16_word := x"0000";
            when 3 => vu16_word := x"0008";
            when 4 => vu16_word := x"33FC";
            when 5 =>
                if (vint_epoch = 0) then
                    vu16_word := x"CAFE";
                else
                    vu16_word := x"BEEF";
                end if;
            when 6 => vu16_word := x"000F";
            when 7 => vu16_word := x"C000";
            when 8 | 13 | 18 => vu16_word := x"33F9";
            when 9 | 14 | 19 => vu16_word := x"000C";
            when 10 => vu16_word := x"0018";
            when 15 => vu16_word := x"001A";
            when 20 => vu16_word := x"001C";
            when 11 | 16 | 21 => vu16_word := x"000F";
            when 12 => vu16_word := x"C002";
            when 17 => vu16_word := x"C004";
            when 22 => vu16_word := x"C006";
            when 23 => vu16_word := x"33F9";
            when 24 | 26 => vu16_word := x"000F";
            when 25 => vu16_word := x"FE00";
            when 27 => vu16_word := x"C008";
            when 28 => vu16_word := x"60D6";
            when others => vu16_word := x"4E71";
        end case;
        return vu16_word(7 downto 0) & vu16_word(15 downto 8);
    end function;
    signal s_clk : std_logic := '0';
    signal s_download, s_pause, s_view_enable : std_logic := '0';
    signal s_ready, s_loading, s_image_valid, s_error, s_done, s_paused, s_view_valid : std_logic;
    signal s_cpu_request, s_cpu_write : std_logic;
    signal su27_loaded : unsigned(26 downto 0);
    signal su16_cpu_data, su16_view_data : unsigned(15 downto 0) := (others => '0');
    signal su16_expected : unsigned(15 downto 0) := x"CAFE";
    signal su24_cpu_address : unsigned(23 downto 0);
    signal su2_cpu_bytes : unsigned(1 downto 0);
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_cpu_writes : natural := 0;
    signal s_host_upload, s_upload_request, s_score_enabled, s_score_error : std_logic := '0';
    signal s_score_initialized, s_score_saved, s_score_dirty : std_logic;
    signal su8_upload_data : unsigned(7 downto 0);
    signal s_maintenance_access, s_maintenance_valid, s_maintenance_write : std_logic := '0';
    signal s_maintenance_ready, s_maintenance_response, s_maintenance_pause : std_logic;
    signal su14_maintenance_address : unsigned(13 downto 0) := (others => '0');
    signal su8_maintenance_data, su8_maintenance_response : unsigned(7 downto 0) := (others => '0');
    signal su16_score_echo : unsigned(15 downto 0) := (others => '0');
    signal sint_upload_requests : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_ddr_busy <= '1' when sint_cycles mod 23 < 7 else '0';
    ddr_backend : process(s_clk)
        variable v_pending : boolean := false;
        variable vint_delay, vint_granule, vint_epoch : natural := 0;
        variable vu64_reply : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            sint_cycles <= sint_cycles + 1;
            s_ddr_valid <= '0';
            su64_ddr_data <= x"BAD0BAD1BAD2BAD3";
            assert (s_ddr_write = '0') report "Image copy wrote DDR staging memory" severity failure;
            if (s_ddr_read = '1') then
                assert (s_ddr_busy = '0' and not v_pending and su8_ddr_burst = 1 and su8_ddr_bytes = x"FF" and
                    su29_ddr_address = to_unsigned(16#6000000# + sint_ddr_reads mod 8, 29))
                    report "System DDR read contract/address violation" severity failure;
                vint_granule := sint_ddr_reads mod 8;
                vint_epoch := sint_epoch;
                vint_delay := 3 + (sint_ddr_reads mod 5) * 7;
                v_pending := true;
                sint_ddr_reads <= sint_ddr_reads + 1;
            elsif (v_pending) then
                if (vint_delay = 0) then
                    for vint_word in 0 to 3 loop
                        vu64_reply(vint_word * 16 + 15 downto vint_word * 16) := image_word(vint_granule * 4 + vint_word, vint_epoch);
                    end loop;
                    su64_ddr_data <= vu64_reply;
                    s_ddr_valid <= '1';
                    v_pending := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
        end if;
    end process;
    system : entity work.rabbitpunch_platform
        generic map (sint_IMAGE_BYTES => 64)
        port map (
            i_clk => s_clk,
            i_initialize => s_copy_initialize,
            i_framework_reset => s_framework_reset,
            iu128_status => su128_status,
            iu2_host_buttons => "00",
            iu32_joystick0 => su32_joystick0,
            iu32_joystick1 => su32_joystick1,
            iu11_key_event => su11_key_event,
            i_osd_open => s_osd_open,
            i_host_download => s_host_download,
            i_host_upload => s_host_upload,
            o_host_upload_request => s_upload_request,
            ou8_host_upload_data => su8_upload_data,
            o_hiscore_enabled => s_score_enabled,
            o_hiscore_config_error => s_score_error,
            o_hiscore_initialized => s_score_initialized,
            o_hiscore_saved_valid => s_score_saved,
            o_hiscore_dirty => s_score_dirty,
            i_maintenance_access => s_maintenance_access,
            i_maintenance_valid => s_maintenance_valid,
            i_maintenance_write => s_maintenance_write,
            iu14_maintenance_byte_address => su14_maintenance_address,
            iu8_maintenance_data => su8_maintenance_data,
            o_maintenance_ready => s_maintenance_ready,
            o_maintenance_response_valid => s_maintenance_response,
            ou8_maintenance_response_data => su8_maintenance_response,
            o_maintenance_pause => s_maintenance_pause,
            iu16_host_index => su16_host_index,
            i_host_write => s_host_write,
            iu27_host_byte_address => su27_host_address,
            iu8_host_data => su8_host_data,
            o_host_wait => s_host_wait,
            o_downloading => s_download,
            o_ddr_owner => s_ddr_owner,
            o_pause_request => s_pause,
            o_user_paused => s_user_paused,
            ou8_player1 => su8_player1,
            ou8_player2 => su8_player2,
            ou8_service => su8_service,
            ou16_dips => su16_dips,
            o_ddr_mode => s_ddr_mode,
            i_ddr_busy => s_ddr_busy,
            ou8_ddr_burst_count => su8_ddr_burst,
            ou29_ddr_word_address => su29_ddr_address,
            iu64_ddr_read_data => su64_ddr_data,
            i_ddr_read_valid => s_ddr_valid,
            o_ddr_read => s_ddr_read,
            ou64_ddr_write_data => su64_ddr_write_data,
            ou8_ddr_byte_enables => su8_ddr_bytes,
            o_ddr_write => s_ddr_write,
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
            iu15_view_word_address => su15_view_address,
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
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
            if (s_upload_request = '1') then
                sint_upload_requests <= sint_upload_requests + 1;
            end if;
            if (s_loading = '1') then
                assert (s_cpu_request /= '1') report "CPU requested during image loading" severity failure;
            end if;
            if (s_cpu_request = '1' and s_cpu_write = '1' and s_ready = '1') then
                assert (su2_cpu_bytes = "11") report "CPU input probe used wrong byte mask" severity failure;
                case to_integer(su24_cpu_address) is
                    when 16#FC000# =>
                        assert (su16_cpu_data = su16_expected) report "CPU marker mismatch" severity failure;
                        su4_seen_writes <= "0001";
                    when 16#FC002# =>
                        assert (su16_cpu_data = x"1219") report "CPU player1/service read mismatch" severity failure;
                        su4_seen_writes(1) <= '1';
                    when 16#FC004# =>
                        assert (su16_cpu_data = x"1226") report "CPU player2/service read mismatch" severity failure;
                        su4_seen_writes(2) <= '1';
                    when 16#FC006# =>
                        assert (su16_cpu_data = x"A55A") report "CPU DIP read mismatch" severity failure;
                        su4_seen_writes(3) <= '1';
                    when 16#FC008# =>
                        su16_score_echo <= su16_cpu_data;
                    when others =>
                        assert false report "CPU probe wrote unexpected address" severity failure;
                end case;
                sint_cpu_writes <= sint_cpu_writes + 1;
            end if;
        end if;
    end process;
    stimulus : process
        type t_bytes is array (0 to 467) of unsigned(7 downto 0);
        variable v_bytes : t_bytes;
        type t_metadata is array (0 to 47) of unsigned(7 downto 0);
        variable v_metadata : t_metadata;
        file v_metadata_file : text open read_mode is "metadata.hex";
        file v_file : text open read_mode is "scores.hex";
        variable v_line : line;
        variable vint_base, vint_length, vint_notices : natural;
        variable vint_before : natural;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure host_byte(vint_byte, vint_epoch : natural) is
            variable vu16_word : unsigned(15 downto 0);
        begin
            if (s_host_wait /= '0') then
                wait until s_host_wait = '0' for 200 us;
            end if;
            assert (s_host_wait = '0') report "System host stream remained blocked" severity failure;
            cycles(1);
            su27_host_address <= to_unsigned(vint_byte, 27);
            vu16_word := image_word(vint_byte / 2, vint_epoch);
            if (vint_byte mod 2 = 0) then
                su8_host_data <= vu16_word(7 downto 0);
            else
                su8_host_data <= vu16_word(15 downto 8);
            end if;
            s_host_write <= '1';
            cycles(1);
            s_host_write <= '0';
            su27_host_address <= (others => '1');
            su8_host_data <= (others => '1');
        end procedure;
        procedure load_program(vu16_value : unsigned(15 downto 0); v_ddr : boolean := true) is
            variable vint_epoch, vint_reads_before : natural;
        begin
            report "Starting image " & to_hstring(vu16_value) & " DDR=" & boolean'image(v_ddr);
            cycles(1);
            if (vu16_value = x"CAFE") then
                vint_epoch := 0;
            else
                vint_epoch := 1;
            end if;
            sint_epoch <= vint_epoch;
            vint_reads_before := sint_ddr_reads;
            su16_expected <= vu16_value;
            s_copy_initialize <= '0';
            s_framework_reset <= '1';
            su16_host_index <= (others => '0');
            cycles(1);
            if (s_host_wait /= '0') then
                wait until s_host_wait = '0' for 200 us;
            end if;
            assert (s_host_wait = '0') report "Previous image did not drain before next host transaction" severity failure;
            s_host_download <= '1';
            cycles(3);
            if (not v_ddr) then
                for vint_byte in 0 to 63 loop
                    host_byte(vint_byte, vint_epoch);
                end loop;
            end if;
            if (s_host_wait /= '0') then
                wait until s_host_wait = '0' for 200 us;
            end if;
            assert (s_host_wait = '0') report "New image start did not wait for old loader drain" severity failure;
            cycles(1);
            s_host_download <= '0';
            if (v_ddr) then
                cycles(10);
                assert (sint_ddr_reads = vint_reads_before and s_ready = '0')
                    report "System copied DDR or ran before framework reset release" severity failure;
            end if;
            s_framework_reset <= '0';
            wait until s_ready = '1' for 300 us;
            assert (s_ready = '1' and s_image_valid = '1' and s_error = '0' and
                su27_loaded = 64 and s_download = '0')
                report "Frontend reset release: ready=" & std_logic'image(s_ready) & " valid=" & std_logic'image(s_image_valid) & " error=" & std_logic'image(s_error) & " downloading=" & std_logic'image(s_download) & " loaded=" & integer'image(to_integer(su27_loaded)) severity failure;
            if (v_ddr) then
                assert (sint_ddr_reads = vint_reads_before + 8 and s_ddr_mode = '1')
                    report "System DDR mode copied an incorrect granule count" severity failure;
            else
                assert (sint_ddr_reads = vint_reads_before and s_ddr_mode = '0')
                    report "Direct-stream image was overwritten from DDR" severity failure;
            end if;
            cycles(2);
        end procedure;
        procedure wait_writes(vint_target : natural) is
        begin
            if (sint_cpu_writes < vint_target) then
                wait until sint_cpu_writes >= vint_target for 100 us;
            end if;
            assert (sint_cpu_writes >= vint_target) report "Downloaded CPU program did not execute" severity failure;
            cycles(1);
        end procedure;
        procedure key_event(vint_code : natural; v_pressed : boolean) is
        begin
            su11_key_event(10) <= not su11_key_event(10);
            if (v_pressed) then
                su11_key_event(9) <= '1';
            else
                su11_key_event(9) <= '0';
            end if;
            su11_key_event(8 downto 0) <= to_unsigned(vint_code, 9);
            cycles(4);
        end procedure;
        procedure wait_probe is
        begin
            wait until su4_seen_writes = "1111" for 150 us;
            assert (su4_seen_writes = "1111") report "CPU failed to read all mapped input ports" severity failure;
            cycles(2);
        end procedure;
        procedure inspect_words is
            variable vu16_expected : unsigned(15 downto 0);
        begin
            if (s_paused /= '1') then
                wait until s_paused = '1' for 20 us;
            end if;
            assert (s_paused = '1') report "Both CPU adapters did not drain for pause" severity failure;
            cycles(3);
            s_view_enable <= '1';
            for vint_word in 0 to 3 loop
                su15_view_address <= to_unsigned(vint_word, 15);
                cycles(4);
                case vint_word is
                    when 0 => vu16_expected := su16_expected;
                    when 1 => vu16_expected := x"1219";
                    when 2 => vu16_expected := x"1226";
                    when others => vu16_expected := x"A55A";
                end case;
                assert (s_view_valid = '1' and su16_view_data = vu16_expected)
                    report "CPU control/DIP result did not reach native work RAM" severity failure;
            end loop;
            s_view_enable <= '0';
            cycles(1);
        end procedure;
        procedure metadata_byte(vint_address, vint_data : natural) is
        begin
            su16_host_index <= to_unsigned(254, 16);
            su27_host_address <= to_unsigned(vint_address, 27);
            su8_host_data <= to_unsigned(vint_data, 8);
            s_host_write <= '1';
            cycles(1);
            s_host_write <= '0';
            cycles(2);
        end procedure;
        procedure file_byte(vint_address : natural; vu8_data : unsigned(7 downto 0)) is
        begin
            if (s_host_wait = '1') then
                wait until s_host_wait = '0' for 200 us;
            end if;
            assert (s_host_wait = '0') report "Score host transfer remained blocked" severity failure;
            su27_host_address <= to_unsigned(vint_address, 27);
            su8_host_data <= vu8_data;
            s_host_write <= '1';
            cycles(1);
            s_host_write <= '0';
            cycles(1);
        end procedure;
        procedure configure(v_us : boolean) is
            variable vint_offset : natural := 0;
        begin
            if (v_us) then
                vint_offset := 24;
            end if;
            su16_host_index <= to_unsigned(3, 16);
            s_host_download <= '1';
            cycles(3);
            for vint_byte in 0 to 23 loop
                file_byte(vint_byte, v_metadata(vint_offset + vint_byte));
            end loop;
            s_host_download <= '0';
            cycles(3);
            assert (s_score_enabled = '1' and s_score_error = '0')
                report "Platform rejected valid score metadata" severity failure;
        end procedure;
        procedure memory_byte(vint_address : natural; vu8_data : unsigned(7 downto 0)) is
        begin
            su14_maintenance_address <= to_unsigned(vint_address, 14);
            su8_maintenance_data <= vu8_data;
            s_maintenance_write <= '1';
            s_maintenance_valid <= '1';
            wait until rising_edge(s_clk) and s_maintenance_ready = '1' for 100 us;
            assert (s_maintenance_ready = '1') report "External score prefill never acquired drained CPUs" severity failure;
            wait until falling_edge(s_clk);
            s_maintenance_valid <= '0';
            if (s_maintenance_response /= '1') then
                wait until s_maintenance_response = '1' for 100 us;
            end if;
            assert (s_maintenance_response = '1') report "External score prefill lost its byte reply" severity failure;
            cycles(3);
        end procedure;
        procedure table_bytes(v_modified : boolean) is
            variable vu8_data : unsigned(7 downto 0);
        begin
            s_maintenance_access <= '1';
            memory_byte(16#3E00#, x"A5");
            for vint_byte in 0 to vint_length - 1 loop
                vu8_data := v_bytes(vint_base + vint_byte);
                if (v_modified) then
                    vu8_data := v_bytes(vint_base + vint_length + vint_byte) xor x"5A";
                end if;
                memory_byte(16#3E01# + vint_byte, vu8_data);
            end loop;
            s_maintenance_access <= '0';
            cycles(3);
        end procedure;
        procedure wait_scores is
        begin
            if (s_score_initialized /= '1') then
                wait until s_score_initialized = '1' for 200 us;
            end if;
            assert (s_score_initialized = '1' and s_score_saved = '1' and s_score_error = '0')
                report "Full platform score initialization/restore failed" severity failure;
            cycles(3);
        end procedure;
        procedure check_echo(v_modified : boolean) is
            variable vu16_expected : unsigned(15 downto 0);
        begin
            vu16_expected := x"A500";
            vu16_expected(7 downto 0) := v_bytes(vint_base + vint_length);
            if (v_modified) then
                vu16_expected(7 downto 0) := vu16_expected(7 downto 0) xor x"5A";
            end if;
            if (su16_score_echo /= vu16_expected) then
                wait until su16_score_echo = vu16_expected for 100 us;
            end if;
            assert (su16_score_echo = vu16_expected)
                report "Executing 68000 did not consume restored score bytes" severity failure;
        end procedure;
        procedure upload(v_modified : boolean) is
            variable vu8_expected : unsigned(7 downto 0);
        begin
            su16_host_index <= to_unsigned(4, 16);
            if (s_host_wait = '1') then
                wait until s_host_wait = '0' for 200 us;
            end if;
            assert (s_host_wait = '0') report "Full platform score snapshot never completed" severity failure;
            s_host_upload <= '1';
            for vint_byte in 0 to vint_length - 1 loop
                su27_host_address <= to_unsigned(vint_byte, 27);
                cycles(3);
                vu8_expected := v_bytes(vint_base + vint_length + vint_byte);
                if (v_modified) then
                    vu8_expected := vu8_expected xor x"5A";
                end if;
                assert (su8_upload_data = vu8_expected)
                    report "Full platform score upload byte mismatch" severity failure;
            end loop;
            s_host_upload <= '0';
            cycles(3);
        end procedure;
    begin
        for vint_byte in v_bytes'range loop
            readline(v_file, v_line);
            hread(v_line, v_bytes(vint_byte));
        end loop;
        for vint_byte in v_metadata'range loop
            readline(v_metadata_file, v_line);
            hread(v_line, v_metadata(vint_byte));
        end loop;
        cycles(100);
        s_copy_initialize <= '0';
        cycles(4);
        metadata_byte(0, 16#5A#);
        metadata_byte(1, 16#A5#);
        key_event(16#06#, true);
        key_event(16#2E#, true);
        for vint_game in 0 to 1 loop
            vint_base := 0;
            vint_length := 119;
            if (vint_game = 1) then
                vint_base := 238;
                vint_length := 115;
            end if;
            s_osd_open <= '0';
            load_program(x"CAFE", false);
            wait_probe;
            assert (s_score_enabled = '0' and s_score_saved = '0')
                report "Full platform retained previous ROM's score profile/image" severity failure;
            table_bytes(false);
            configure(vint_game = 1);
            su16_host_index <= to_unsigned(4, 16);
            s_host_download <= '1';
            cycles(3);
            for vint_byte in 0 to vint_length - 1 loop
                file_byte(vint_byte, v_bytes(vint_base + vint_length + vint_byte));
            end loop;
            s_host_download <= '0';
            cycles(3);
            wait_scores;
            check_echo(false);
            upload(false);
            table_bytes(true);
            check_echo(true);
            vint_notices := sint_upload_requests;
            su128_status(3) <= '1';
            s_osd_open <= '1';
            cycles(5);
            if (sint_upload_requests = vint_notices) then
                wait until sint_upload_requests = vint_notices + 1 for 200 us;
            end if;
            assert (sint_upload_requests = vint_notices + 1 and s_score_dirty = '1' and s_user_paused = '0')
                report "Platform autosave/pause wiring mismatch" severity failure;
            upload(true);
            assert (s_score_dirty = '0') report "Platform upload did not finish dirty transaction" severity failure;
            s_osd_open <= '0';
            -- Reset the game, restore initialization RAM under an external
            -- maintenance session, then let persistence restore the last save.
            su128_status(0) <= '1';
            cycles(10);
            s_maintenance_access <= '1';
            su128_status(0) <= '0';
            cycles(2);
            table_bytes(false);
            wait_scores;
            check_echo(true);
            upload(true);
        end loop;
        assert (s_error = '0' and su16_dips = x"A55A")
            report "Score persistence disturbed image or DIP state" severity failure;
        report "PLATFORM_HISCORE_PASS sets=2 executing_cpu=checked shared_sdram=checked config3_dump4=checked restore_echo=checked external_client_arbitration=checked osd_autosave=checked upload_bytes=234 soft_reset_restore=checked rom_generation_isolation=checked dips_preserved=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 3 ms;
        assert false report "Full platform high-score timeout" severity failure;
    end process;
end architecture;
