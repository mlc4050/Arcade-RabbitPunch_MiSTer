-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_state_layout.all;

entity state_machine_backend_tb is
    generic (
        GINT_ROUNDS : positive := 2
    );
end entity;

architecture test of state_machine_backend_tb is
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
            when 23 => vu16_word := x"60D8";
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
    signal s_pixel_enable, s_hsync, s_vsync, s_active, s_underflow : std_logic;
    signal sint_pixels, sint_sync_edges : natural := 0;
    signal sint_cpu_writes : natural := 0;
    signal s_state_acquire, s_state_cancel, s_state_release : std_logic := '0';
    signal s_state_ready, s_state_busy, s_state_held, s_state_finished, s_state_canceled : std_logic;
    signal s_state_reset_drained, s_state_banks_idle, s_state_stopped : std_logic;
    signal s_state_request : std_logic := '0';
    signal s_state_byte_ready, s_state_response, s_state_byte_error : std_logic;
    signal s_state_committed, s_state_commit_error : std_logic;
    signal su4_state_error : unsigned(3 downto 0);
    signal su18_state_address : unsigned(17 downto 0) := (others => '0');
    signal su8_state_read : unsigned(7 downto 0);
    signal su52_state_cpu_bus : unsigned(51 downto 0);
    signal s_state_rom_valid, s_state_rom_error : std_logic;
    signal su32_state_rom : unsigned(31 downto 0);
begin
    s_clk <= not s_clk after 10714 ps;
    s_ddr_busy <= '1' when sint_cycles mod 23 < 7 else '0';
    cadence : process(s_clk)
        variable vint_gap : natural := 0;
        variable v_seen : boolean := false;
        variable v_previous_hsync : std_logic := '1';
    begin
        if (rising_edge(s_clk)) then
            if (s_copy_initialize = '1') then
                vint_gap := 0;
                v_seen := false;
            elsif (s_pixel_enable = '1') then
                if (v_seen) then
                    assert (vint_gap = 6) report "Machine pixel cadence changed during loading/reset/pause" severity failure;
                end if;
                vint_gap := 0;
                v_seen := true;
                sint_pixels <= sint_pixels + 1;
                if (s_hsync /= v_previous_hsync) then
                    sint_sync_edges <= sint_sync_edges + 1;
                end if;
                v_previous_hsync := s_hsync;
            elsif (v_seen) then
                vint_gap := vint_gap + 1;
                assert (vint_gap <= 6) report "Machine raster stopped" severity failure;
            end if;
            assert (s_underflow /= '1') report "Machine startup scanout underflow" severity failure;
        end if;
    end process;
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
    system : entity work.rabbitpunch_state_machine_backend
        generic map (
            GINT_IMAGE_BYTES => 64
        )
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
            o_pixel_enable => s_pixel_enable,
            o_hsync => s_hsync,
            o_vsync => s_vsync,
            o_active => s_active,
            o_scanout_underflow => s_underflow,
            ou8_red => open,
            ou8_green => open,
            ou8_blue => open,
            i_view_enable => s_view_enable,
            iu5_view_target => CU5_TARGET_WORKRAM,
            iu15_view_word_address => su15_view_address,
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
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
            o_loading => s_loading,
            i_state_acquire => s_state_acquire,
            i_state_cancel => s_state_cancel,
            i_state_release => s_state_release,
            i_state_incomplete => '0',
            o_state_ready => s_state_ready,
            o_state_busy => s_state_busy,
            o_state_held => s_state_held,
            o_state_finished => s_state_finished,
            o_state_canceled => s_state_canceled,
            ou4_state_error => su4_state_error,
            o_state_reset_drained => s_state_reset_drained,
            o_state_rom_identity_valid => s_state_rom_valid,
            o_state_rom_identity_error => s_state_rom_error,
            ou32_state_rom_identity => su32_state_rom,
            i_state_apply_begin => '0',
            i_state_byte_request => s_state_request,
            o_state_byte_ready => s_state_byte_ready,
            i_state_byte_write => '0',
            iu18_state_byte_address => su18_state_address,
            iu8_state_byte_data => x"00",
            o_state_byte_response => s_state_response,
            o_state_byte_error => s_state_byte_error,
            ou8_state_byte_data => su8_state_read,
            i_state_commit => '0',
            o_state_committed => s_state_committed,
            o_state_commit_error => s_state_commit_error,
            o_state_banks_idle => s_state_banks_idle,
            o_state_cpu_stopped => s_state_stopped,
            ou52_state_cpu_bus => su52_state_cpu_bus
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
            assert (su16_mono_pcm = 0) report "Synthetic diagnostic unexpectedly produced PCM" severity failure;
            for vint_bit in su16_mono_pcm'range loop
                assert (su16_mono_pcm(vint_bit) = '0' or su16_mono_pcm(vint_bit) = '1')
                    report "Mixed PCM is undefined during startup/reset/playback" severity failure;
            end loop;
        end if;
    end process;
    monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
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
                    when 16#FFFF0# to 16#FFFFE# => null;
                    when others =>
                        assert (false) report "CPU probe wrote unexpected address" severity failure;
                end case;
                sint_cpu_writes <= sint_cpu_writes + 1;
            end if;
        end if;
    end process;
    stimulus : process
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
    begin
        cycles(100);
        s_copy_initialize <= '0';
        cycles(4);
        assert (s_ready = '0' and s_image_valid = '0' and sint_cpu_writes = 0)
            report "Platform ran before an image existed" severity failure;
        metadata_byte(0, 16#5A#);
        metadata_byte(1, 16#A5#);
        key_event(16#06#, true);
        key_event(16#2E#, true);
        assert (su8_player1 = x"19" and su8_player2 = x"26" and su8_service = x"12" and su16_dips = x"A55A")
            report "Platform host controls or DIP wiring mismatch" severity failure;
        load_program(x"CAFE");
        wait_probe;
        -- Independent zlib CRC of the64-byte big-endian68000 diagnostic.
        assert (s_state_rom_valid = '1' and s_state_rom_error = '0' and su32_state_rom = x"D556EC13")
            report "Committed DDR image has no accepted-word identity" severity failure;
        for vint_round in 1 to GINT_ROUNDS loop
            if (s_state_ready /= '1') then
                wait until s_state_ready = '1' for 1 ms;
            end if;
            assert (s_state_ready = '1') report "Actual machine state barrier did not become ready" severity failure;
            s_state_acquire <= '1';
            cycles(1);
            s_state_acquire <= '0';
            if (s_state_held /= '1') then
                wait until s_state_held = '1' or su4_state_error /= 0 for 1 ms;
            end if;
            assert (s_state_held = '1' and su4_state_error = 0)
                report "Actual paired CPU acquisition failed error=" & to_hstring(su4_state_error) severity failure;
            cycles(2);
            -- Real word/byte RAM, architectural main bank, startup/control
            -- packing and both generated-chip scan read paths, without writes.
            for vint_field in 0 to 6 loop
                for vint_byte in 0 to 7 loop
                    case vint_field is
                        when 0 => su18_state_address <= to_unsigned(88064 + vint_byte, 18);
                        when 1 => su18_state_address <= to_unsigned(104448 + vint_byte, 18);
                        when 2 => su18_state_address <= to_unsigned(CINT_M68K_BASE + 72 + vint_byte, 18);
                        when 3 => su18_state_address <= to_unsigned(CINT_T80_BASE + vint_byte, 18);
                        when 4 => su18_state_address <= to_unsigned(CINT_BOARD_BASE + 40 + vint_byte, 18);
                        when 5 => su18_state_address <= to_unsigned(CINT_FM_BASE + vint_byte, 18);
                        when others => su18_state_address <= to_unsigned(CINT_ADPCM_BASE + 16 + vint_byte, 18);
                    end case;
                    cycles(1);
                    if (s_state_byte_ready /= '1') then
                        wait until s_state_byte_ready = '1' for 20 us;
                    end if;
                    assert (s_state_byte_ready = '1') report "Held body request was not admitted" severity failure;
                    s_state_request <= '1';
                    cycles(1);
                    s_state_request <= '0';
                    if (s_state_response /= '1') then
                        wait until s_state_response = '1' for 20 us;
                    end if;
                    assert (s_state_response = '1' and s_state_byte_error = '0')
                        report "Actual held body read failed" severity failure;
                    if (vint_field = 0 and vint_byte = 0) then
                        assert (su8_state_read = x"CA") report "Work RAM high byte changed" severity failure;
                    elsif (vint_field = 0 and vint_byte = 1) then
                        assert (su8_state_read = x"FE") report "Work RAM low byte changed" severity failure;
                    elsif (vint_field = 4 and vint_byte = 4) then
                        assert (not is_x(su8_state_read) and su8_state_read(7 downto 3) = 0 and
                            (su8_state_read(1) = '0' or su8_state_read(0) = '1'))
                            report "Packed FM/score startup field is illegal" severity failure;
                    elsif (vint_field = 6 and vint_byte = 7) then
                        assert (not is_x(su8_state_read) and su8_state_read(7 downto 5) = 0)
                            report "Corrected ADPCM tail padding is not canonical" severity failure;
                    end if;
                    cycles(2);
                end loop;
            end loop;
            assert (s_state_held = '1' and s_state_banks_idle = '1') severity failure;
            vint_before := sint_cpu_writes;
            cycles(50);
            assert (sint_cpu_writes = vint_before) report "Held main CPU kept writing" severity failure;
            s_state_release <= '1';
            cycles(1);
            s_state_release <= '0';
            if (s_state_finished /= '1') then
                wait until s_state_finished = '1' for 40 ms;
            end if;
            assert (s_state_finished = '1' and su4_state_error = 0 and s_state_canceled = '0')
                report "Actual private return/alignment failed error=" & to_hstring(su4_state_error) severity failure;
            cycles(4);
            wait_writes(vint_before + 4);
        end loop;
        assert (sint_pixels > 50000*GINT_ROUNDS and sint_sync_edges > 200*GINT_ROUNDS) report "Physical scanout stopped during state access" severity failure;
        report "STATE_MACHINE_BACKEND_PASS paired actual CPUs, real RAM/chip/board reads, drained private returns=" &
            integer'image(GINT_ROUNDS) & ",physical pixel cadence and sync continuous";
        finish;
        wait;
    end process;
    process
    begin
        wait for 100 ms;
        assert (false) report "System downloaded-program timeout" severity failure;
    end process;
end architecture;
