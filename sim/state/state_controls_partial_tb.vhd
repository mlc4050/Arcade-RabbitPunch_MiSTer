-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_controls_partial_tb is
end entity;

architecture test of state_controls_partial_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal su128_status : unsigned(127 downto 0) := (others => '0');
    signal s_finished, s_success : std_logic := '0';
    signal s_incomplete : std_logic := '0';
    signal s_save, s_restore, s_unavailable, s_save_unavailable, s_set : std_logic;
begin
    s_clk <= not s_clk after 5 ns;
    controls : entity work.rabbitpunch_state_controls
        generic map (
            GBOOL_ENABLE => true
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            iu128_status => su128_status,
            i_service_ready => '1',
            i_service_busy => '0',
            i_service_finished => s_finished,
            i_service_success => s_success,
            i_service_incomplete => s_incomplete,
            o_save => s_save,
            o_restore => s_restore,
            ou2_slot => open,
            o_unavailable => s_unavailable,
            o_save_unavailable => s_save_unavailable,
            o_status_set => s_set,
            ou128_status_data => open
        );
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
    begin
        tick;
        s_initialize <= '0';
        su128_status(7) <= '1';
        tick;
        su128_status(9) <= '1';
        tick;
        assert (s_restore = '1') severity failure;
        -- The service retains a partially applied machine. It advertises
        -- ready for RESTORE retry, but cannot accept SAVE in this condition.
        s_incomplete <= '1';
        s_finished <= '1';
        tick;
        s_finished <= '0';
        su128_status(9 downto 8) <= "00";
        tick;
        assert (s_unavailable = '0' and s_save_unavailable = '1')
            report "Partial restore did not expose only its retry" severity failure;
        su128_status(8) <= '1';
        tick;
        assert (s_save = '0' and s_unavailable = '0')
            report "Partial hold admitted SAVE and consumed the restore retry ticket" severity failure;
        su128_status(9) <= '1';
        tick;
        assert (s_restore = '1' and s_save = '0')
            report "Held rejected SAVE blocked RESTORE retry" severity failure;
        s_finished <= '1';
        tick;
        assert (s_set = '0') report "Failed RESTORE retry incremented its slot" severity failure;
        s_finished <= '0';
        su128_status(9 downto 8) <= "00";
        tick;
        su128_status(9 downto 8) <= "11";
        tick;
        assert (s_restore = '1' and s_save = '0')
            report "Partial hold did not prioritize valid RESTORE over invalid SAVE" severity failure;
        s_finished <= '1';
        s_success <= '1';
        s_incomplete <= '0';
        tick;
        assert (s_set = '0') report "RESTORE retry incremented its slot" severity failure;
        s_finished <= '0';
        tick;
        assert (s_save = '0' and s_unavailable = '0' and s_save_unavailable = '0')
            report "Rejected held SAVE was deferred after recovery" severity failure;
        su128_status(9 downto 8) <= "00";
        tick;
        su128_status(8) <= '1';
        tick;
        assert (s_save = '1') report "Recovery did not permit a fresh SAVE edge" severity failure;
        report "STATE_CONTROLS_PARTIAL_PASS";
        finish;
    end process;
end architecture;
