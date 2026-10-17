-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity maintenance_clients_tb is
end entity;
architecture test of maintenance_clients_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_score_initialize : std_logic := '0';
    signal s_external_access, s_external_valid : std_logic := '0';
    signal s_score_access, s_score_valid : std_logic := '0';
    signal s_external_ready, s_external_response, s_score_ready, s_score_response : std_logic;
    signal su8_external_data, su8_score_data : unsigned(7 downto 0);
    signal s_memory_initialize, s_memory_access, s_memory_valid, s_memory_write : std_logic;
    signal su14_memory_address : unsigned(13 downto 0);
    signal su8_memory_data : unsigned(7 downto 0);
    signal s_memory_ready : std_logic := '0';
    signal s_memory_response : std_logic := '0';
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_maintenance_clients
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_score_initialize => s_score_initialize,
            i_external_access => s_external_access,
            i_external_valid => s_external_valid,
            i_external_write => '1',
            iu14_external_address => to_unsigned(16#1234#, 14),
            iu8_external_data => x"A5",
            o_external_ready => s_external_ready,
            o_external_response => s_external_response,
            ou8_external_data => su8_external_data,
            i_score_access => s_score_access,
            i_score_valid => s_score_valid,
            i_score_write => '0',
            iu14_score_address => to_unsigned(16#3E01#, 14),
            iu8_score_data => x"5A",
            o_score_ready => s_score_ready,
            o_score_response => s_score_response,
            ou8_score_data => su8_score_data,
            o_memory_initialize => s_memory_initialize,
            o_memory_access => s_memory_access,
            o_memory_valid => s_memory_valid,
            o_memory_write => s_memory_write,
            ou14_memory_address => su14_memory_address,
            ou8_memory_data => su8_memory_data,
            i_memory_ready => s_memory_ready,
            i_memory_response => s_memory_response,
            iu8_memory_data => x"C3"
        );
    process
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
    begin
        cycles(3);
        s_initialize <= '0';
        s_external_access <= '1';
        s_external_valid <= '1';
        s_score_access <= '1';
        s_score_valid <= '1';
        s_memory_ready <= '1';
        wait for 1 ns;
        assert (s_external_ready = '1' and s_score_ready = '0' and s_memory_valid = '1' and
            s_memory_write = '1' and su14_memory_address = 16#1234# and su8_memory_data = x"A5")
            report "Idle maintenance priority/direct handshake mismatch" severity failure;
        cycles(1);
        s_external_valid <= '0';
        s_external_access <= '0';
        cycles(30);
        assert (s_memory_access = '1' and s_score_ready = '0' and s_memory_valid = '0')
            report "Ended external session lost its accepted byte debt" severity failure;
        -- Score reconfiguration must not cancel somebody else's transaction.
        s_score_initialize <= '1';
        cycles(3);
        assert (s_memory_initialize = '0' and s_memory_access = '1')
            report "Score reset canceled external maintenance" severity failure;
        s_score_initialize <= '0';
        s_memory_response <= '1';
        wait for 1 ns;
        assert (s_external_response = '1' and s_score_response = '0' and su8_external_data = x"C3")
            report "External maintenance response routed to wrong client" severity failure;
        cycles(1);
        s_memory_response <= '0';
        s_memory_ready <= '0';
        cycles(3);
        assert (s_memory_valid = '1' and s_memory_write = '0' and su14_memory_address = 16#3E01#)
            report "Queued score session did not acquire the port" severity failure;
        s_memory_ready <= '1';
        cycles(1);
        s_score_valid <= '0';
        s_external_access <= '1';
        s_external_valid <= '1';
        cycles(30);
        assert (s_external_ready = '0') report "External request stole an active score session" severity failure;
        s_memory_response <= '1';
        wait for 1 ns;
        assert (s_score_response = '1' and s_external_response = '0' and su8_score_data = x"C3")
            report "Score maintenance response routed to wrong client" severity failure;
        cycles(1);
        s_memory_response <= '0';
        s_score_access <= '0';
        s_memory_ready <= '0';
        cycles(3);
        assert (s_memory_valid = '1' and s_external_ready = '0')
            report "External session failed to wait for backend readiness" severity failure;
        s_memory_ready <= '1';
        cycles(1);
        s_external_valid <= '0';
        s_memory_response <= '1';
        cycles(1);
        s_memory_response <= '0';
        s_external_access <= '0';
        cycles(3);
        s_score_access <= '1';
        s_score_valid <= '1';
        cycles(1);
        s_score_valid <= '0';
        s_score_initialize <= '1';
        wait for 1 ns;
        assert (s_memory_initialize = '1' and s_score_response = '0')
            report "Score cancellation did not reset its maintenance client" severity failure;
        cycles(1);
        s_score_access <= '0';
        s_score_initialize <= '0';
        cycles(3);
        assert (s_memory_access = '0') report "Canceled score client retained session ownership" severity failure;
        report "MAINTENANCE_CLIENTS_PASS external_priority=checked direct_idle_handshake=checked ended_session_debt=checked response_ownership=checked no_preemption=checked selective_score_cancel=checked";
        finish;
        wait;
    end process;
end architecture;
