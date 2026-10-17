-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity pause_tb is
end entity;

architecture test of pause_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_button, s_osd_open, s_pause_on_osd, s_debug, s_state : std_logic := '0';
    signal s_request, s_user : std_logic;
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_pause
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pause_pressed => s_button,
            i_osd_open => s_osd_open,
            i_pause_on_osd => s_pause_on_osd,
            i_debug_pause => s_debug,
            i_state_pause => s_state,
            o_pause_request => s_request,
            o_user_paused => s_user
        );
    process
        procedure tick(vint_count : positive := 1) is
        begin
            for vint_clock in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        tick;
        assert (s_request = '0' and s_user = '0') report "Pause reset default mismatch" severity failure;
        s_reset <= '0';
        s_button <= '1';
        tick;
        assert (s_request = '1' and s_user = '1') report "Pause press did not latch" severity failure;
        tick(20);
        assert (s_user = '1') report "Held pause button toggled more than once" severity failure;
        s_button <= '0';
        tick;
        assert (s_user = '1') report "Pause release cleared the latch" severity failure;
        s_button <= '1';
        tick(20);
        assert (s_request = '0' and s_user = '0') report "Second pause press did not resume exactly once" severity failure;
        s_button <= '0';
        s_osd_open <= '1';
        tick;
        assert (s_request = '0') report "Disabled OSD pause affected CPUs" severity failure;
        s_pause_on_osd <= '1';
        tick;
        assert (s_request = '1' and s_user = '0') report "OSD pause did not remain independent of user latch" severity failure;
        s_button <= '1';
        tick;
        s_osd_open <= '0';
        tick;
        assert (s_request = '1' and s_user = '1') report "Closing OSD cleared a manual pause" severity failure;
        s_button <= '0';
        s_debug <= '1';
        s_state <= '1';
        tick;
        s_button <= '1';
        tick;
        assert (s_user = '0' and s_request = '1') report "User resume bypassed an independent pause owner" severity failure;
        s_debug <= '0';
        tick;
        assert (s_request = '1') report "Debug release bypassed state/inspection pause" severity failure;
        s_state <= '0';
        tick;
        assert (s_request = '0') report "Independent pause owners did not release" severity failure;
        s_reset <= '1';
        tick;
        s_reset <= '0';
        tick(10);
        assert (s_user = '0') report "Held key retriggered on reset release" severity failure;
        s_button <= '0';
        tick;
        s_button <= '1';
        tick;
        assert (s_user = '1') report "Fresh post-reset press was lost" severity failure;
        s_state <= '1';
        s_reset <= '1';
        tick;
        assert (s_user = '0' and s_request = '1') report "Reset bypassed state/inspection pause owner" severity failure;
        report "PAUSE_PASS rising_edge_toggle=checked held_key=checked osd_debug_state_union=checked reset_held_key=checked";
        finish;
        wait;
    end process;
end architecture;
