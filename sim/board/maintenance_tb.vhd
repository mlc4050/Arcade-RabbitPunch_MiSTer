-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity maintenance_tb is
end entity;

architecture test of maintenance_tb is
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
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_maintenance
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_access_requested => s_access,
            o_pause => s_pause,
            i_cpu_paused => s_paused,
            i_bus_idle => s_bus_idle,
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
    su13_ram_address <= su13_prefill_address when s_prefill = '1' else su24_bus_address(13 downto 1);
    su2_ram_bytes <= "11" when s_prefill = '1' else su2_bus_bytes;
    su16_ram_write_data <= x"A55A" when s_prefill = '1' else su16_bus_data;
    ram : entity work.rabbitpunch_ram16
        generic map (GINT_ADDRESS_BITS => 13)
        port map (
            i_clk => s_clk,
            i_cpu_enable => s_prefill or s_bus_request,
            i_cpu_write => s_prefill or s_bus_write,
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
            s_bus_response <= '0';
            if (s_bus_request = '1') then
                assert (not v_pending and s_paused = '1' and s_pause = '1' and s_bus_idle = '1')
                    report "Maintenance borrowed RAM before confirmed pause/drain" severity failure;
                assert (su24_bus_address >= 16#FC000# and su24_bus_address <= 16#FFFFE# and su24_bus_address(0) = '0' and
                    (su2_bus_bytes = "10" or su2_bus_bytes = "01") and su16_bus_data(15 downto 8) = su16_bus_data(7 downto 0))
                    report "Maintenance address/lane/data contract mismatch" severity failure;
                v_pending := true;
                vint_delay := sint_delay;
                sint_requests <= sint_requests + 1;
                s_inflight <= '1';
            elsif (v_pending) then
                assert (s_pause = '1') report "Maintenance released pause before memory acknowledgment" severity failure;
                if (vint_delay = 0) then
                    s_bus_response <= '1';
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
        report "MAINTENANCE_PASS score_bytes=234 native_masked_write_read=checked pause_and_debt=checked neighbors=preserved delayed_response_reset_drain=checked";
        finish;
        wait;
    end process;
end architecture;
