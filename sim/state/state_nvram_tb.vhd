-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity state_nvram_tb is
end entity;

architecture test of state_nvram_tb is
    type t_bytes is array(natural range <>) of unsigned(7 downto 0);
    impure function F_FIXTURE return t_bytes is
        file v_file : text open read_mode is "scores.hex";
        variable v_line : line;
        variable vu8_value : unsigned(7 downto 0);
        variable vu8_data : t_bytes(0 to 233);
    begin
        for vint_byte in vu8_data'range loop
            readline(v_file, v_line);
            hread(v_line, vu8_value);
            vu8_data(vint_byte) := vu8_value;
        end loop;
        assert (endfile(v_file)) report "Unexpected state NVRAM fixture length" severity failure;
        return vu8_data;
    end function;
    constant CU8_FIXTURE : t_bytes(0 to 233) := F_FIXTURE;
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_game_reset : std_logic := '0';
    signal s_profile, s_us, s_download, s_dump_write, s_upload, s_manual : std_logic := '0';
    signal s_quiesce, s_quiesced, s_restored : std_logic := '0';
    signal s_scores_ready : std_logic := '0';
    signal s_wait, s_upload_request, s_initialized, s_saved, s_dirty : std_logic;
    signal s_access, s_valid, s_write, s_response : std_logic := '0';
    signal s_ready : std_logic;
    signal su27_dump_address : unsigned(26 downto 0) := (others => '0');
    signal su8_dump_data, su8_dump_read : unsigned(7 downto 0) := (others => '0');
    signal su14_memory_address : unsigned(13 downto 0);
    signal su8_memory_data, su8_memory_read : unsigned(7 downto 0) := (others => '0');
    signal su8_ram : t_bytes(0 to 118) := (others => (others => '0'));
    signal s_pending, s_fixture_load, s_bad_guard : std_logic := '0';
    signal sint_epoch : natural range 0 to 5 := 0;
    signal sint_requests, sint_writes, sint_uploads : natural := 0;
    function F_LENGTH(v_us : std_logic) return natural is
    begin
        if (v_us = '1') then
            return 115;
        end if;
        return 119;
    end function;
    function F_BYTE(v_us : std_logic; vint_index, vint_epoch : natural) return unsigned is
        variable vint_base : natural := 0;
        variable vu8_value : unsigned(7 downto 0);
    begin
        if (v_us = '1') then
            vint_base := 119;
        end if;
        vu8_value := CU8_FIXTURE(vint_base + vint_index);
        if (vint_epoch = 4 and vint_index = 0) then
            return x"5A";
        elsif (vint_epoch = 4 and vint_index = F_LENGTH(v_us) - 1) then
            return x"A5";
        end if;
        if (vint_index /= 0 and vint_index /= F_LENGTH(v_us) - 1) then
            vu8_value := vu8_value xor to_unsigned((vint_epoch * 37 + vint_index * 11) mod 256, 8);
        end if;
        return vu8_value;
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_ready <= not s_pending;
    scores : entity work.rabbitpunch_hiscore
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_reset => s_game_reset,
            i_profile_valid => s_profile,
            i_us_set => s_us,
            iu32_start_wait => to_unsigned(5, 32),
            iu16_check_wait => to_unsigned(7, 16),
            i_osd_open => '0',
            i_autosave => '0',
            i_manual_save => s_manual,
            i_dump_download => s_download,
            i_dump_write => s_dump_write,
            i_dump_upload => s_upload,
            iu27_dump_address => su27_dump_address,
            iu8_dump_data => su8_dump_data,
            ou8_dump_data => su8_dump_read,
            o_dump_wait => s_wait,
            o_upload_request => s_upload_request,
            o_initialized => s_initialized,
            o_saved_valid => s_saved,
            o_dirty => s_dirty,
            o_memory_access => s_access,
            o_memory_valid => s_valid,
            o_memory_write => s_write,
            ou14_memory_address => su14_memory_address,
            ou8_memory_data => su8_memory_data,
            i_memory_ready => s_ready,
            i_memory_response => s_response,
            iu8_memory_data => su8_memory_read,
            i_state_quiesce => s_quiesce,
            o_state_quiesced => s_quiesced,
            i_state_reconcile => s_restored,
            i_state_scores_ready => s_scores_ready
        );
    backend : process(s_clk)
        variable vint_delay : natural := 0;
        variable vu8_reply : unsigned(7 downto 0);
        variable vint_index : natural;
    begin
        if (rising_edge(s_clk)) then
            s_response <= '0';
            if (s_fixture_load = '1') then
                assert (s_quiesced = '1' or s_initialize = '1') report "Fixture changed live score RAM" severity failure;
                assert (s_pending = '0') report "Fixture changed score RAM with pending debt" severity failure;
                for vint_byte in 0 to F_LENGTH(s_us) - 1 loop
                    su8_ram(vint_byte) <= F_BYTE(s_us, vint_byte, sint_epoch);
                end loop;
                if (s_bad_guard = '1') then
                    su8_ram(F_LENGTH(s_us) - 1) <= x"55";
                end if;
            end if;
            if (s_pending = '1') then
                if (vint_delay = 0) then
                    s_pending <= '0';
                    s_response <= '1';
                    su8_memory_read <= vu8_reply;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (s_valid = '1' and s_ready = '1') then
                assert (s_access = '1' and s_quiesced = '0') report "NVRAM issued RAM work during state lease" severity failure;
                vint_index := to_integer(su14_memory_address) - 16#3E01#;
                assert (vint_index < F_LENGTH(s_us)) report "NVRAM escaped MAME score block" severity failure;
                s_pending <= '1';
                vint_delay := 5;
                vu8_reply := su8_ram(vint_index);
                sint_requests <= sint_requests + 1;
                if (s_write = '1') then
                    su8_ram(vint_index) <= su8_memory_data;
                    sint_writes <= sint_writes + 1;
                end if;
            end if;
            if (s_upload_request = '1') then
                assert (s_quiesced = '0') report "State lease admitted an upload notification" severity failure;
                sint_uploads <= sint_uploads + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_length, vint_before, vint_prior_uploads : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure wait_lease is
        begin
            for vint_wait in 0 to 6000 loop
                exit when (s_quiesced = '1');
                cycles;
            end loop;
            assert (s_quiesced = '1' and s_pending = '0' and s_access = '0') report "NVRAM did not finish its whole operation" severity failure;
        end procedure;
        procedure wait_initialized is
        begin
            for vint_wait in 0 to 6000 loop
                exit when (s_initialized = '1' and s_access = '0' and s_pending = '0');
                cycles;
            end loop;
            assert (s_initialized = '1') report "Restored NVRAM guards never qualified" severity failure;
        end procedure;
        procedure check_ram(vint_value_epoch : natural) is
        begin
            for vint_byte in 0 to vint_length - 1 loop
                assert (su8_ram(vint_byte) = F_BYTE(s_us, vint_byte, vint_value_epoch))
                    report "NVRAM overwrote restored game RAM" severity failure;
            end loop;
        end procedure;
        procedure restore_ram(vint_value_epoch : natural; v_bad : std_logic := '0';
            v_ready : std_logic := '0') is
        begin
            s_quiesce <= '1';
            wait_lease;
            sint_epoch <= vint_value_epoch;
            s_bad_guard <= v_bad;
            s_fixture_load <= '1';
            s_scores_ready <= v_ready;
            s_restored <= '1';
            cycles;
            s_fixture_load <= '0';
            s_restored <= '0';
            cycles(50);
            assert (s_initialized = v_ready and s_wait = '1') report "State restore lost NVRAM readiness" severity failure;
            s_quiesce <= '0';
            cycles(3);
        end procedure;
        procedure check_upload(vint_value_epoch : natural) is
        begin
            s_upload <= '1';
            cycles(3);
            for vint_byte in 0 to vint_length - 1 loop
                su27_dump_address <= to_unsigned(vint_byte, 27);
                cycles(2);
                assert (su8_dump_read = F_BYTE(s_us, vint_byte, vint_value_epoch))
                    report "NVRAM rescan did not publish restored bytes" severity failure;
            end loop;
            s_upload <= '0';
            cycles(3);
        end procedure;
        procedure download_table(vint_value_epoch : natural) is
        begin
            for vint_byte in 0 to vint_length - 1 loop
                assert (s_wait = '0') report "Host data admitted before state lease release" severity failure;
                su27_dump_address <= to_unsigned(vint_byte, 27);
                su8_dump_data <= F_BYTE(s_us, vint_byte, vint_value_epoch);
                s_dump_write <= '1';
                cycles;
                s_dump_write <= '0';
                cycles;
            end loop;
            s_download <= '0';
            cycles(3);
        end procedure;
    begin
        for vint_set in 0 to 1 loop
            s_initialize <= '1';
            s_profile <= '0';
            s_quiesce <= '0';
            s_download <= '0';
            s_us <= '0';
            if (vint_set = 1) then
                s_us <= '1';
            end if;
            sint_epoch <= 0;
            s_bad_guard <= '0';
            s_fixture_load <= '1';
            cycles(3);
            s_fixture_load <= '0';
            s_initialize <= '0';
            s_profile <= '1';
            s_download <= '1';
            cycles(3);
            vint_length := F_LENGTH(s_us);
            vint_before := sint_writes;
            download_table(1);
            wait until sint_writes > vint_before for 100 us;
            assert (sint_writes > vint_before) report "Initial saved score table did not restore" severity failure;
            s_quiesce <= '1';
            wait_lease;
            assert (s_initialized = '1' and sint_writes = vint_before + vint_length)
                report "Quiesce interrupted a score restore between bytes" severity failure;
            check_ram(1);
            vint_before := sint_requests;
            cycles(50);
            assert (sint_requests = vint_before) report "Quiesced NVRAM started fresh work" severity failure;
            vint_before := sint_writes;
            restore_ram(2);
            wait_initialized;
            check_ram(2);
            assert (sint_writes = vint_before) report "Rescan wrote a stale cached table" severity failure;
            check_upload(2);
            restore_ram(3, '1');
            cycles(500);
            assert (s_initialized = '0' and sint_writes = vint_before) report "Invalid restored guard was accepted" severity failure;
            vint_prior_uploads := sint_uploads;
            s_quiesce <= '1';
            wait_lease;
            s_manual <= '1';
            cycles;
            s_manual <= '0';
            -- Valid initialized score tables can have changed guard bytes.
            restore_ram(4, '0', '1');
            wait_initialized;
            cycles(10);
            check_ram(4);
            assert (sint_writes = vint_before and sint_uploads = vint_prior_uploads + 1)
                report "Manual save during lease did not wait for a valid restored table" severity failure;
            check_upload(4);
            -- A host announcement while wait is asserted must retain byte zero.
            s_quiesce <= '1';
            wait_lease;
            -- A fresh game initializes the guards before its ordinary file
            -- restore. Gameplay reset preserves the previous download count.
            sint_epoch <= 0;
            s_fixture_load <= '1';
            s_game_reset <= '1';
            cycles;
            s_fixture_load <= '0';
            s_game_reset <= '0';
            wait_lease;
            s_download <= '1';
            cycles(4);
            assert (s_wait = '1') report "Held state did not block host download bytes" severity failure;
            s_quiesce <= '0';
            cycles(3);
            download_table(5);
            wait_initialized;
            check_ram(5);
            assert (sint_writes = vint_before + vint_length) report "Announced host download lost its first byte" severity failure;
        end loop;
        report "STATE_NVRAM_PASS: both MAME geometries, full-operation quiesce, restored RAM authority, readiness with changed guards, guard retry and host announcement";
        finish;
    end process;
end architecture;
