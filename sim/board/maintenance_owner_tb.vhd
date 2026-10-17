-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity maintenance_owner_tb is
end entity;

architecture test of maintenance_owner_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_access, s_paused, s_bus_idle, s_byte_valid, s_byte_write : std_logic := '0';
    signal s_pause, s_ready, s_response, s_idle : std_logic;
    signal su14_address : unsigned(13 downto 0) := (others => '0');
    signal su8_data, su8_response : unsigned(7 downto 0) := (others => '0');
    signal s_bus_request, s_bus_write, s_bus_response : std_logic := '0';
    signal su24_bus_address : unsigned(23 downto 0);
    signal su16_bus_data, su16_ram_data : unsigned(15 downto 0);
    signal su2_bus_bytes : unsigned(1 downto 0);
    signal s_prefill : std_logic := '1';
    signal su13_prefill_address, su13_view_address : unsigned(12 downto 0) := (others => '0');
    signal su16_view_data : unsigned(15 downto 0);
    signal su13_ram_address : unsigned(12 downto 0);
    signal su2_ram_bytes : unsigned(1 downto 0);
    signal su16_ram_write_data : unsigned(15 downto 0);
    signal sint_requests : natural := 0;
    signal s_inflight : std_logic := '0';
    signal sint_delay : natural range 0 to 300 := 0;
    signal s_backend_request, s_backend_write, s_backend_response, s_cpu_response, s_cpu_idle : std_logic;
    signal su24_backend_address : unsigned(23 downto 0);
    signal su16_backend_data : unsigned(15 downto 0);
    signal su2_backend_bytes : unsigned(1 downto 0);
    signal s_cpu_request : std_logic := '0';
    signal s_allow_maintenance : std_logic := '1';
    signal su24_cpu_address : unsigned(23 downto 0) := x"0FC000";
    signal su16_cpu_data : unsigned(15 downto 0) := x"A1B2";
    signal su2_cpu_bytes : unsigned(1 downto 0) := "11";
    signal s_race : std_logic := '0';
    signal su2_race_seen : unsigned(1 downto 0) := "00";
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_maintenance
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_access_requested => s_access,
            o_pause => s_pause,
            i_cpu_paused => s_paused,
            i_bus_idle => s_bus_idle and s_cpu_idle,
            i_byte_valid => s_byte_valid,
            o_byte_ready => s_ready,
            i_byte_write => s_byte_write,
            iu14_byte_address => su14_address,
            iu8_byte_data => su8_data,
            o_byte_response_valid => s_response,
            ou8_byte_response_data => su8_response,
            o_idle => s_idle,
            o_bus_request => s_bus_request,
            o_bus_write => s_bus_write,
            ou24_bus_address => su24_bus_address,
            ou16_bus_data => su16_bus_data,
            ou2_bus_bytes => su2_bus_bytes,
            i_bus_response_valid => s_bus_response,
            iu16_bus_response_data => su16_ram_data
        );
    owner : entity work.rabbitpunch_bus_owner
        port map (
            i_clk => s_clk,
            i_cpu_request => s_cpu_request,
            i_cpu_write => '1',
            iu24_cpu_address => su24_cpu_address,
            iu16_cpu_data => su16_cpu_data,
            iu2_cpu_bytes => su2_cpu_bytes,
            o_cpu_idle => s_cpu_idle,
            o_idle => open,
            o_cpu_response_valid => s_cpu_response,
            ou16_cpu_response_data => open,
            i_maintenance_allowed => s_paused and s_allow_maintenance,
            i_maintenance_request => s_bus_request,
            i_maintenance_write => s_bus_write,
            iu24_maintenance_address => su24_bus_address,
            iu16_maintenance_data => su16_bus_data,
            iu2_maintenance_bytes => su2_bus_bytes,
            o_maintenance_response_valid => s_bus_response,
            ou16_maintenance_response_data => open,
            o_backend_request => s_backend_request,
            o_backend_write => s_backend_write,
            ou24_backend_address => su24_backend_address,
            ou16_backend_data => su16_backend_data,
            ou2_backend_bytes => su2_backend_bytes,
            i_backend_response_valid => s_backend_response,
            iu16_backend_response_data => su16_ram_data
        );
    race_monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_cpu_response = '1') then
                assert (s_race = '1' and su2_race_seen = "00") report "CPU response leaked from maintenance or lost priority" severity failure;
                su2_race_seen(0) <= '1';
            end if;
            if (s_race = '1' and s_response = '1') then
                assert (su2_race_seen = "01" and su8_response = x"5A") report "Queued maintenance reply lost its data/owner" severity failure;
                su2_race_seen(1) <= '1';
            end if;
        end if;
    end process;
    su13_ram_address <= su13_prefill_address when s_prefill = '1' else su24_backend_address(13 downto 1);
    su2_ram_bytes <= "11" when s_prefill = '1' else su2_backend_bytes;
    su16_ram_write_data <= x"A55A" when s_prefill = '1' else su16_backend_data;
    ram : entity work.rabbitpunch_ram16
        generic map (sint_ADDRESS_BITS => 13)
        port map (
            i_clk => s_clk,
            i_cpu_enable => s_prefill or s_backend_request,
            i_cpu_write => s_prefill or s_backend_write,
            iux_cpu_address => su13_ram_address,
            iu2_cpu_bytes => su2_ram_bytes,
            iu16_cpu_data => su16_ram_write_data,
            ou16_cpu_data => su16_ram_data,
            i_view_enable => '1',
            iux_view_address => su13_view_address,
            ou16_view_data => su16_view_data
        );
    backend : process(s_clk)
        variable v_pending : boolean := false;
        variable vint_delay : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            s_backend_response <= '0';
            if (s_backend_request = '1') then
                assert (not v_pending and s_paused = '1' and s_pause = '1' and s_bus_idle = '1')
                    report "Maintenance borrowed RAM before confirmed pause/drain" severity failure;
                assert (su24_backend_address >= 16#FC000# and su24_backend_address <= 16#FFFFE# and su24_backend_address(0) = '0' and
                    (su2_backend_bytes = "10" or su2_backend_bytes = "01" or (su24_backend_address = 16#FC000# and su2_backend_bytes = "11")))
                    report "Maintenance address/lane/data contract mismatch" severity failure;
                v_pending := true;
                vint_delay := sint_delay;
                sint_requests <= sint_requests + 1;
                s_inflight <= '1';
            elsif (v_pending) then
                assert (s_pause = '1') report "Maintenance released pause before memory acknowledgment" severity failure;
                if (vint_delay = 0) then
                    s_backend_response <= '1';
                    v_pending := false;
                    s_inflight <= '0';
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        file vectors : text open read_mode is "scores.hex";
        variable v_line : line;
        variable vu8_byte : unsigned(7 downto 0);
        variable vint_length, vint_before : natural;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure byte_access(vint_address : natural; v_write : std_logic; vu8_data : unsigned(7 downto 0)) is
        begin
            if (s_ready /= '1') then
                wait until s_ready = '1' for 10 us;
            end if;
            assert (s_ready = '1') report "Maintenance client blocked" severity failure;
            cycles(1);
            su14_address <= to_unsigned(vint_address, 14);
            s_byte_write <= v_write;
            su8_data <= vu8_data;
            s_byte_valid <= '1';
            cycles(1);
            s_byte_valid <= '0';
            su14_address <= (others => '1');
            su8_data <= (others => '1');
            wait until s_response = '1' for 10 us;
            assert (s_response = '1') report "Maintenance response timeout" severity failure;
            if (v_write = '0') then
                assert (su8_response = vu8_data) report "Native RAM byte readback mismatch" severity failure;
            end if;
            cycles(1);
        end procedure;
    begin
        for vint_set in 0 to 1 loop
            s_prefill <= '1';
            for vint_word in 16#1F00# to 16#1F3C# loop
                su13_prefill_address <= to_unsigned(vint_word, 13);
                cycles(1);
            end loop;
            s_prefill <= '0';
            s_initialize <= '0';
            s_access <= '1';
            s_paused <= '0';
            s_bus_idle <= '0';
            s_byte_valid <= '1';
            cycles(20);
            assert (s_ready = '0' and s_pause = '1' and s_bus_request = '0')
                report "Maintenance failed to wait for actual pause" severity failure;
            s_paused <= '1';
            cycles(20);
            assert (s_ready = '0' and s_bus_request = '0') report "Maintenance ignored old CPU bus debt" severity failure;
            s_byte_valid <= '0';
            s_bus_idle <= '1';
            cycles(2);
            if (vint_set = 0) then
                vint_length := 119;
            else
                vint_length := 115;
            end if;
            if (vint_set = 0) then
                -- A last CPU pulse arrives with an already-accepted maintenance
                -- request. Both single pulses must survive; CPU drains first.
                s_race <= '1';
                s_allow_maintenance <= '0';
                su14_address <= to_unsigned(16#3E01#, 14);
                s_byte_write <= '0';
                s_byte_valid <= '1';
                cycles(1);
                s_byte_valid <= '0';
                s_cpu_request <= '1';
                cycles(1);
                s_cpu_request <= '0';
                su24_cpu_address <= (others => '1');
                su16_cpu_data <= (others => '1');
                su2_cpu_bytes <= "00";
                wait until su2_race_seen(0) = '1' for 10 us;
                assert (su2_race_seen = "01") report "Queued maintenance blocked the last CPU transaction" severity failure;
                for vint_cycle in 1 to 20 loop
                    cycles(1);
                    assert (su2_race_seen = "01" and s_response = '0' and s_pause = '1')
                        report "Maintenance issued before owner permission" severity failure;
                end loop;
                s_allow_maintenance <= '1';
                wait until su2_race_seen = "11" for 10 us;
                assert (su2_race_seen = "11") report "Simultaneous CPU/maintenance requests did not both complete" severity failure;
                cycles(2);
                s_race <= '0';
                su13_view_address <= (others => '0');
                cycles(3);
                assert (su16_view_data = x"A1B2") report "Late CPU write was not preserved in native RAM" severity failure;
            end if;
            -- Real MAME block bytes with deterministic interior changes stand in
            -- for a saved score file; sentinel bytes retain their captured values.
            for vint_byte in 0 to vint_length - 1 loop
                readline(vectors, v_line);
                hread(v_line, vu8_byte);
                sint_delay <= (vint_byte mod 4) * 17;
                byte_access(16#3E01# + vint_byte, '1', vu8_byte);
            end loop;
            su13_view_address <= to_unsigned(16#1F00#, 13);
            cycles(3);
            assert (su16_view_data(15 downto 8) = x"A5") report "Odd score start clobbered preceding byte" severity failure;
            su13_view_address <= to_unsigned(16#1F00# + (vint_length + 1) / 2, 13);
            cycles(3);
            assert (su16_view_data = x"A55A") report "Score restore wrote beyond selected set length" severity failure;
            for vint_byte in 0 to vint_length - 1 loop
                readline(vectors, v_line);
                hread(v_line, vu8_byte);
                byte_access(16#3E01# + vint_byte, '0', vu8_byte);
            end loop;
        end loop;
        -- End a session and reset the client while a 300-clock reply is owed.
        sint_delay <= 300;
        vint_before := sint_requests;
        su14_address <= to_unsigned(16#3E01#, 14);
        s_byte_write <= '0';
        s_byte_valid <= '1';
        cycles(1);
        s_byte_valid <= '0';
        wait until s_inflight = '1' for 1 us;
        assert (s_inflight = '1') report "Reset-drain test did not issue memory work" severity failure;
        cycles(1);
        s_access <= '0';
        s_initialize <= '1';
        cycles(4);
        s_initialize <= '0';
        for vint_cycle in 1 to 20 loop
            cycles(1);
            assert (s_pause = '1' and s_ready = '0' and s_response = '0')
                report "Reset canceled debt or leaked a stale maintenance reply" severity failure;
        end loop;
        wait until s_idle = '1' for 10 us;
        cycles(2);
        assert (s_idle = '1' and s_pause = '0' and s_response = '0' and sint_requests = vint_before + 1)
            report "Maintenance did not finish one owned request after reset" severity failure;
        report "MAINTENANCE_OWNER_PASS score_bytes=234 native_masked_write_read=checked pause_and_debt=checked neighbors=preserved delayed_response_reset_drain=checked";
        finish;
        wait;
    end process;
end architecture;
