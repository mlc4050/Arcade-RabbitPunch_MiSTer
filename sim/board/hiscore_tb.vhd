-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity hiscore_tb is
    generic (GBOOL_SERVICE_MODE : boolean := false);
end entity;

architecture test of hiscore_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_reset : std_logic := '1';
    signal s_profile, s_us, s_osd, s_autosave : std_logic := '0';
    signal s_download, s_dump_write, s_upload : std_logic := '0';
    signal s_manual_save : std_logic := '0';
    signal s_manual_expected : std_logic := '0';
    signal su27_dump_address : unsigned(26 downto 0) := (others => '0');
    signal su8_dump_in, su8_dump_out : unsigned(7 downto 0) := (others => '0');
    signal s_wait, s_request, s_initialized, s_saved, s_dirty : std_logic;
    signal s_access, s_valid, s_write, s_ready, s_response : std_logic;
    signal su14_address : unsigned(13 downto 0);
    signal su8_data, su8_response : unsigned(7 downto 0);
    signal s_pause, s_paused : std_logic := '0';
    signal s_prefill : std_logic := '0';
    signal su13_prefill_address : unsigned(12 downto 0) := (others => '0');
    signal su16_prefill_data : unsigned(15 downto 0) := x"A55A";
    signal s_bus_request, s_bus_write, s_bus_response : std_logic := '0';
    signal su24_bus_address : unsigned(23 downto 0);
    signal su16_bus_data, su16_ram_data, su16_ram_write, su16_view_data : unsigned(15 downto 0);
    signal su2_bus_bytes, su2_ram_bytes : unsigned(1 downto 0);
    signal su13_ram_address, su13_view_address : unsigned(12 downto 0) := (others => '0');
    signal sint_requests, sint_writes, sint_upload_requests : natural := 0;
    signal sint_delay : natural := 0;
    signal s_inflight : std_logic := '0';
    signal su16_file_index : unsigned(15 downto 0) := to_unsigned(4, 16);
    signal s_memory_initialize, s_enabled, s_config_error : std_logic;
begin
    s_clk <= not s_clk after 5 ns;
    direct_store : if (not GBOOL_SERVICE_MODE) generate
        s_memory_initialize <= s_initialize or s_reset;
        dut : entity work.rabbitpunch_hiscore
            port map (
                i_clk => s_clk,
                i_initialize => s_initialize,
                i_game_reset => s_reset,
                i_profile_valid => s_profile,
                i_us_set => s_us,
                iu32_start_wait => to_unsigned(30, 32),
                iu16_check_wait => to_unsigned(19, 16),
                i_osd_open => s_osd,
                i_autosave => s_autosave,
                i_manual_save => s_manual_save,
                i_dump_download => s_download,
                i_dump_write => s_dump_write,
                i_dump_upload => s_upload,
                iu27_dump_address => su27_dump_address,
                iu8_dump_data => su8_dump_in,
                ou8_dump_data => su8_dump_out,
                o_dump_wait => s_wait,
                o_upload_request => s_request,
                o_initialized => s_initialized,
                o_saved_valid => s_saved,
                o_dirty => s_dirty,
                o_memory_access => s_access,
                o_memory_valid => s_valid,
                o_memory_write => s_write,
                ou14_memory_address => su14_address,
                ou8_memory_data => su8_data,
                i_memory_ready => s_ready,
                i_memory_response => s_response,
                iu8_memory_data => su8_response
            );
    end generate;
    file_service : if (GBOOL_SERVICE_MODE) generate
        dut : entity work.rabbitpunch_hiscore_service
            port map (
                i_clk => s_clk,
                i_initialize => s_initialize,
                i_game_reset => s_reset,
                i_osd_open => s_osd,
                i_autosave => s_autosave,
                i_manual_save => s_manual_save,
                i_download => s_download,
                i_upload => s_upload,
                iu16_file_index => su16_file_index,
                i_write => s_dump_write,
                iu27_byte_address => su27_dump_address,
                iu8_data => su8_dump_in,
                ou8_data => su8_dump_out,
                o_wait => s_wait,
                o_upload_request => s_request,
                o_enabled => s_enabled,
                o_config_error => s_config_error,
                o_initialized => s_initialized,
                o_saved_valid => s_saved,
                o_dirty => s_dirty,
                o_memory_initialize => s_memory_initialize,
                o_memory_access => s_access,
                o_memory_valid => s_valid,
                o_memory_write => s_write,
                ou14_memory_address => su14_address,
                ou8_memory_data => su8_data,
                i_memory_ready => s_ready,
                i_memory_response => s_response,
                iu8_memory_data => su8_response
            );
    end generate;
    maintenance : entity work.rabbitpunch_maintenance
        port map (
            i_clk => s_clk,
            i_initialize => s_memory_initialize,
            i_access_requested => s_access,
            o_pause => s_pause,
            i_cpu_paused => s_paused,
            i_bus_idle => not s_prefill,
            i_byte_valid => s_valid,
            o_byte_ready => s_ready,
            i_byte_write => s_write,
            iu14_byte_address => su14_address,
            iu8_byte_data => su8_data,
            o_byte_response_valid => s_response,
            ou8_byte_response_data => su8_response,
            o_idle => open,
            o_bus_request => s_bus_request,
            o_bus_write => s_bus_write,
            ou24_bus_address => su24_bus_address,
            ou16_bus_data => su16_bus_data,
            ou2_bus_bytes => su2_bus_bytes,
            i_bus_response_valid => s_bus_response,
            iu16_bus_response_data => su16_ram_data
        );
    su13_ram_address <= su13_prefill_address when s_prefill = '1' else su24_bus_address(13 downto 1);
    su2_ram_bytes <= "11" when s_prefill = '1' else su2_bus_bytes;
    su16_ram_write <= su16_prefill_data when s_prefill = '1' else su16_bus_data;
    ram : entity work.rabbitpunch_ram16
        generic map (
            GINT_ADDRESS_BITS => 13
        )
        port map (
            i_clk => s_clk,
            i_cpu_enable => s_prefill or s_bus_request,
            i_cpu_write => s_prefill or s_bus_write,
            iux_cpu_address => su13_ram_address,
            iu2_cpu_bytes => su2_ram_bytes,
            iu16_cpu_data => su16_ram_write,
            ou16_cpu_data => su16_ram_data,
            i_view_enable => '1',
            iux_view_address => su13_view_address,
            ou16_view_data => su16_view_data
        );
    process(s_clk)
        variable vint_pause_delay : natural := 0;
        variable vint_remaining : natural := 0;
        variable v_pending : boolean := false;
    begin
        if (rising_edge(s_clk)) then
            s_bus_response <= '0';
            if (s_pause = '0') then
                vint_pause_delay := 0;
                s_paused <= '0';
            elsif (vint_pause_delay = 5) then
                s_paused <= '1';
            else
                vint_pause_delay := vint_pause_delay + 1;
            end if;
            if (s_request = '1') then
                assert (s_saved = '1' and s_wait = '0' and (s_dirty = '1' or s_manual_expected = '1'))
                    report "Upload requested without a complete changed or explicitly saved image" severity failure;
                sint_upload_requests <= sint_upload_requests + 1;
            end if;
            if (s_bus_request = '1') then
                assert (not v_pending and s_pause = '1' and s_paused = '1' and s_prefill = '0')
                    report "Score access bypassed real pause/debt acknowledgment" severity failure;
                assert (su24_bus_address >= 16#FFE00# and su24_bus_address <= 16#FFE76#)
                    report "Score access escaped the reference table words" severity failure;
                v_pending := true;
                vint_remaining := sint_delay + (sint_requests mod 13);
                sint_requests <= sint_requests + 1;
                if (s_bus_write = '1') then
                    sint_writes <= sint_writes + 1;
                end if;
                s_inflight <= '1';
            elsif (v_pending) then
                assert (s_pause = '1') report "Pause dropped before score memory debt drained" severity failure;
                if (vint_remaining = 0) then
                    v_pending := false;
                    s_bus_response <= '1';
                    s_inflight <= '0';
                else
                    vint_remaining := vint_remaining - 1;
                end if;
            end if;
        end if;
    end process;
    process
        type t_bytes is array (0 to 467) of unsigned(7 downto 0);
        variable v_bytes : t_bytes;
        file v_file : text open read_mode is "scores.hex";
        variable v_line : line;
        variable vint_base, vint_length, vint_writes, vint_notices : natural;
        variable vu16_word : unsigned(15 downto 0);
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure load_config is
            variable vu192_packet : unsigned(191 downto 0);
        begin
            if (GBOOL_SERVICE_MODE) then
                vu192_packet := x"0000001E001300020002000100000000000FFE0100770080";
                if (s_us = '1') then
                    vu192_packet(31 downto 16) := to_unsigned(115, 16);
                    vu192_packet(7 downto 0) := x"17";
                end if;
                su16_file_index <= to_unsigned(3, 16);
                s_download <= '1';
                cycles(2);
                for vint_byte in 0 to 23 loop
                    su27_dump_address <= to_unsigned(vint_byte, 27);
                    su8_dump_in <= vu192_packet(191 - vint_byte * 8 downto 184 - vint_byte * 8);
                    s_dump_write <= '1';
                    cycles(1);
                end loop;
                s_dump_write <= '0';
                s_download <= '0';
                cycles(3);
                assert (s_enabled = '1' and s_config_error = '0')
                    report "Score service did not accept the standard configuration transfer" severity failure;
                su16_file_index <= to_unsigned(4, 16);
            end if;
        end procedure;
        procedure wait_idle is
        begin
            for vint_cycle in 0 to 30000 loop
                exit when s_wait = '0' and s_pause = '0';
                cycles(1);
                assert (vint_cycle < 30000) report "Score engine did not become idle" severity failure;
            end loop;
        end procedure;
        procedure wait_initialized is
        begin
            for vint_cycle in 0 to 30000 loop
                exit when s_initialized = '1' and s_wait = '0';
                cycles(1);
                assert (vint_cycle < 30000) report "Score engine did not initialize" severity failure;
            end loop;
            cycles(3);
        end procedure;
        procedure set_table(vint_pattern : natural) is
            variable vint_index : integer;
            variable vu16_value : unsigned(15 downto 0);
        begin
            s_prefill <= '1';
            for vint_word in -1 to 60 loop
                vu16_value := x"A55A";
                for vint_lane in 0 to 1 loop
                    vint_index := 2 * vint_word + vint_lane - 1;
                    if (vint_index >= 0 and vint_index < vint_length) then
                        if (vint_pattern = 0) then
                            vu16_value(15 - vint_lane * 8 downto 8 - vint_lane * 8) := v_bytes(vint_base + vint_index);
                        else
                            vu16_value(15 - vint_lane * 8 downto 8 - vint_lane * 8) := v_bytes(vint_base + vint_length + vint_index) xor x"5A";
                        end if;
                    end if;
                end loop;
                su13_prefill_address <= to_unsigned(16#1F00# + vint_word, 13);
                su16_prefill_data <= vu16_value;
                cycles(1);
            end loop;
            s_prefill <= '0';
            cycles(2);
        end procedure;
        procedure load_dump(vint_count : natural; v_bad_address : boolean := false) is
        begin
            wait_idle;
            s_download <= '1';
            cycles(2);
            for vint_index in 0 to vint_count - 1 loop
                su27_dump_address <= to_unsigned(vint_index, 27);
                if (v_bad_address and vint_index = 3) then
                    su27_dump_address <= to_unsigned(5, 27);
                end if;
                su8_dump_in <= v_bytes(vint_base + vint_length + (vint_index mod vint_length));
                s_dump_write <= '1';
                cycles(1);
            end loop;
            s_dump_write <= '0';
            s_download <= '0';
            cycles(3);
        end procedure;
        procedure check_upload(vint_pattern : natural) is
            variable vu8_expected : unsigned(7 downto 0);
        begin
            wait_idle;
            s_upload <= '1';
            for vint_index in 0 to vint_length - 1 loop
                su27_dump_address <= to_unsigned(vint_index, 27);
                cycles(2);
                vu8_expected := v_bytes(vint_base + vint_length + vint_index);
                if (vint_pattern = 1) then
                    vu8_expected := vu8_expected xor x"5A";
                elsif (vint_pattern = 2) then
                    vu8_expected := v_bytes(vint_base + vint_index);
                end if;
                assert (su8_dump_out = vu8_expected)
                    report "Saved score image differs at byte " & integer'image(vint_index) severity failure;
            end loop;
            su27_dump_address <= to_unsigned(vint_length, 27);
            cycles(2);
            assert (su8_dump_out = 0) report "Score upload exposed padding outside its configured length" severity failure;
            s_upload <= '0';
            cycles(3);
        end procedure;
        procedure capture is
        begin
            s_osd <= '0';
            cycles(3);
            s_osd <= '1';
            cycles(4);
            assert (s_wait = '1') report "OSD did not start a score snapshot" severity failure;
            wait_initialized;
            wait_idle;
        end procedure;
        procedure check_ram(vint_pattern : natural) is
            variable vint_index : integer;
            variable vu16_expected : unsigned(15 downto 0);
        begin
            for vint_word in -1 to 60 loop
                vu16_expected := x"A55A";
                for vint_lane in 0 to 1 loop
                    vint_index := 2 * vint_word + vint_lane - 1;
                    if (vint_index >= 0 and vint_index < vint_length) then
                        vu16_expected(15 - vint_lane * 8 downto 8 - vint_lane * 8) := v_bytes(vint_base + vint_length + vint_index);
                        if (vint_pattern = 1) then
                            vu16_expected(15 - vint_lane * 8 downto 8 - vint_lane * 8) := vu16_expected(15 - vint_lane * 8 downto 8 - vint_lane * 8) xor x"5A";
                        end if;
                    end if;
                end loop;
                su13_view_address <= to_unsigned(16#1F00# + vint_word, 13);
                cycles(2);
                assert (su16_view_data = vu16_expected)
                    report "Restored score word/lane/neighbor differs at word " & integer'image(vint_word) severity failure;
            end loop;
        end procedure;
    begin
        for vint_index in v_bytes'range loop
            readline(v_file, v_line);
            hread(v_line, v_bytes(vint_index));
        end loop;
        for vint_game in 0 to 1 loop
            vint_base := 0;
            vint_length := 119;
            s_us <= '0';
            if (vint_game = 1) then
                vint_base := 238;
                vint_length := 115;
                s_us <= '1';
            end if;
            s_initialize <= '1';
            s_reset <= '1';
            s_profile <= '1';
            s_osd <= '0';
            s_autosave <= '0';
            cycles(3);
            set_table(0);
            -- The CPU has not finished initializing its first sentinel yet.
            s_prefill <= '1';
            su13_prefill_address <= to_unsigned(16#1F00#, 13);
            su16_prefill_data <= x"A5FF";
            cycles(1);
            s_prefill <= '0';
            s_initialize <= '0';
            load_config;
            load_dump(vint_length);
            assert (s_saved = '1' and s_initialized = '0')
                report "Score file loaded under gameplay reset was discarded" severity failure;
            s_reset <= '0';
            vint_writes := sint_writes;
            cycles(300);
            assert (s_saved = '1' and s_initialized = '0' and sint_writes = vint_writes)
                report "Score restore ignored the game's initialization sentinel" severity failure;
            wait_idle;
            set_table(0);
            wait_initialized;
            assert (sint_writes = vint_writes + vint_length)
                report "Score restore did not write exactly the configured byte length" severity failure;
            check_ram(0);
            check_upload(0);
            vint_notices := sint_upload_requests;
            s_autosave <= '1';
            capture;
            cycles(30);
            assert (s_dirty = '0' and sint_upload_requests = vint_notices)
                report "Unchanged score capture requested a save" severity failure;
            s_autosave <= '0';
            set_table(1);
            s_osd <= '0';
            cycles(3);
            sint_delay <= 80;
            s_osd <= '1';
            wait until s_inflight = '1';
            cycles(3);
            -- A native upload flag may precede the HPS's wait polling.
            s_upload <= '1';
            cycles(20000);
            assert (s_wait = '1') report "Capture switched saved banks during an upload" severity failure;
            for vint_byte in 0 to vint_length - 1 loop
                su27_dump_address <= to_unsigned(vint_byte, 27);
                cycles(2);
                assert (su8_dump_out = v_bytes(vint_base + vint_length + vint_byte))
                    report "Concurrent upload observed a partially captured bank" severity failure;
            end loop;
            s_upload <= '0';
            cycles(3);
            sint_delay <= 0;
            wait_initialized;
            cycles(30);
            assert (s_dirty = '1' and sint_upload_requests = vint_notices)
                report "Manual score capture lost changes or ignored autosave off" severity failure;
            s_autosave <= '1';
            cycles(30);
            assert (sint_upload_requests = vint_notices + 1)
                report "Enabling autosave did not request exactly one dirty upload" severity failure;
            cycles(30);
            assert (sint_upload_requests = vint_notices + 1)
                report "Dirty upload request repeated without a new snapshot" severity failure;
            s_reset <= '1';
            cycles(3);
            check_upload(1);
            assert (s_dirty = '0') report "Completed reset-held upload did not clear dirty state" severity failure;
            set_table(0);
            s_reset <= '0';
            wait_initialized;
            check_ram(1);
            load_dump(vint_length - 1);
            check_upload(1);
            load_dump(vint_length, true);
            check_upload(1);
            load_dump(vint_length + 1);
            check_upload(1);
            -- Download announcement must not swallow an outstanding RAM reply.
            s_osd <= '0';
            cycles(3);
            s_osd <= '1';
            wait until s_inflight = '1';
            cycles(3);
            s_download <= '1';
            cycles(6000);
            assert (s_wait = '0') report "Download announcement stranded score memory debt" severity failure;
            su27_dump_address <= (others => '0');
            su8_dump_in <= x"EE";
            s_dump_write <= '1';
            cycles(1);
            s_dump_write <= '0';
            s_download <= '0';
            cycles(3);
            check_upload(1);
            -- Abandon an in-progress capture after a backend request is issued.
            s_osd <= '0';
            cycles(3);
            sint_delay <= 80;
            s_osd <= '1';
            wait until s_inflight = '1';
            cycles(3);
            s_reset <= '1';
            cycles(100);
            assert (s_inflight = '0' and s_initialized = '0')
                report "Reset did not cancel score client and drain backend debt" severity failure;
            set_table(0);
            s_osd <= '0';
            sint_delay <= 0;
            s_reset <= '0';
            wait_initialized;
            check_ram(1);
            check_upload(1);
            -- A fresh ROM generation must discard the old game's dump.
            s_initialize <= '1';
            s_reset <= '1';
            cycles(3);
            assert (s_saved = '0' and s_dirty = '0')
                report "New ROM generation retained the previous saved score image" severity failure;
            set_table(0);
            s_initialize <= '0';
            load_config;
            s_reset <= '0';
            wait_initialized;
            assert (s_saved = '1') report "First run without a file never became saveable" severity failure;
            check_upload(2);
            -- Manual save must capture fresh RAM even with autosave/OSD off.
            s_manual_expected <= '1';
            s_autosave <= '0';
            s_osd <= '0';
            set_table(1);
            cycles(3);
            vint_notices := sint_upload_requests;
            s_manual_save <= '1';
            cycles(50000);
            assert (sint_upload_requests = vint_notices + 1)
                report "Manual NVRAM save did not request one fresh upload" severity failure;
            check_upload(1);
            cycles(300);
            assert (sint_upload_requests = vint_notices + 1)
                report "Held manual NVRAM action repeated its request" severity failure;
            s_manual_save <= '0';
            cycles(3);
            s_manual_save <= '1';
            cycles(1);
            s_manual_save <= '0';
            cycles(50000);
            assert (sint_upload_requests = vint_notices + 2)
                report "Manual save did not save an unchanged snapshot" severity failure;
            check_upload(1);
            s_manual_expected <= '0';
            s_manual_save <= '0';
            cycles(3);
        end loop;
        report "HISCORE_PASS manual_save_fresh_and_unchanged=checked held_manual_no_repeat=checked sets=2 captured_geometry=checked sentinel_gate=checked changed_guard_bytes=checked native_ram_lanes_neighbors=checked delayed_ack=checked atomic_bank_commit=checked incomplete_reordered_oversize_downloads=checked reset_debt=checked first_run_without_file=checked concurrent_upload_bank_stability=checked busy_download_announcement=checked load_while_game_reset=checked";
        finish;
        wait;
    end process;
end architecture;
