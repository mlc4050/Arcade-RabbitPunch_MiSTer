-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_config.all;
use work.rabbitpunch_state_config.all;

entity state_controls_joystick_tb is
end entity;

architecture test of state_controls_joystick_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal su128_status, su128_feedback : unsigned(127 downto 0) := (others => '0');
    signal su32_joystick0, su32_joystick1 : unsigned(31 downto 0) := (others => '0');
    signal s_ready : std_logic := '1';
    signal s_finished, s_success, s_incomplete : std_logic := '0';
    signal s_save, s_restore, s_set, s_unavailable : std_logic;
    signal su2_slot : unsigned(1 downto 0);
    signal s_disabled_save, s_disabled_restore : std_logic;
begin
    s_clk <= not s_clk after 5 ns;
    disabled : entity work.rabbitpunch_state_controls
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            iu128_status => su128_status,
            iu32_joystick0 => su32_joystick0,
            iu32_joystick1 => su32_joystick1,
            i_service_ready => s_ready,
            i_service_busy => '0',
            i_service_finished => s_finished,
            i_service_success => s_success,
            o_save => s_disabled_save,
            o_restore => s_disabled_restore,
            ou2_slot => open,
            o_unavailable => open,
            o_save_unavailable => open,
            o_status_set => open,
            ou128_status_data => open
        );
    controls : entity work.rabbitpunch_state_controls
        generic map (
            GBOOL_ENABLE => true
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            iu128_status => su128_status,
            iu32_joystick0 => su32_joystick0,
            iu32_joystick1 => su32_joystick1,
            i_service_ready => s_ready,
            i_service_busy => '0',
            i_service_finished => s_finished,
            i_service_success => s_success,
            i_service_incomplete => s_incomplete,
            o_save => s_save,
            o_restore => s_restore,
            ou2_slot => su2_slot,
            o_unavailable => s_unavailable,
            o_save_unavailable => open,
            o_status_set => s_set,
            ou128_status_data => su128_feedback
        );
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (s_disabled_save = '0' and s_disabled_restore = '0')
                report "Disabled controller path issued a state command" severity failure;
        end procedure;
        procedure complete(vbool_success : boolean) is
        begin
            s_finished <= '1';
            if (vbool_success) then
                s_success <= '1';
            else
                s_success <= '0';
            end if;
            tick;
            s_finished <= '0';
        end procedure;
    begin
        assert (F_STATE_CONFIG(false) = CSTR_DEFAULT_CONFIG_STRING) severity failure;
        assert (F_STATE_GAME_ACTIONS(x"00008014", true) = 0) severity failure;
        assert (F_STATE_GAME_ACTIONS(x"00008014", false) = x"00008014") severity failure;
        assert (F_STATE_GAME_ACTIONS(x"00000014", true) = x"00000014") severity failure;
        assert (F_STATE_GAME_ACTIONS(x"ffffffff", true) = 0) severity failure;
        tick;
        s_initialize <= '0';
        su128_status(7) <= '1';
        su128_status(6 downto 5) <= "11";
        -- Neither an ordinary Down nor cross-controller SS/Down is a command.
        su32_joystick1(2) <= '1';
        tick;
        su32_joystick0(15) <= '1';
        tick;
        assert (s_save = '0' and s_restore = '0') severity failure;
        su32_joystick0(2) <= '1';
        tick;
        assert (s_save = '1' and su2_slot = 3) severity failure;
        tick;
        assert (s_save = '0') report "Held SS/Down repeated SAVE" severity failure;
        complete(true);
        assert (s_set = '1' and su128_feedback(6 downto 5) = 0)
            report "Controller SAVE did not use OSD autoincrement/wrap" severity failure;
        tick;
        assert (s_unavailable = '1') report "Controller bypassed host feedback ticket" severity failure;
        su128_status <= su128_feedback;
        tick;
        tick;
        assert (s_save = '0' and s_unavailable = '0') severity failure;
        su32_joystick0 <= (others => '0');
        su32_joystick1 <= (others => '0');
        tick;
        -- Player 2 restore uses the same selected slot and never increments.
        su32_joystick1 <= x"00008008";
        tick;
        assert (s_restore = '1' and su2_slot = 0) severity failure;
        complete(true);
        assert (s_set = '0') severity failure;
        tick;
        assert (s_restore = '0') severity failure;
        su32_joystick1 <= (others => '0');
        s_ready <= '0';
        tick;
        su32_joystick0 <= x"00008004";
        tick;
        s_ready <= '1';
        tick;
        assert (s_save = '0') report "Unavailable controller edge was deferred" severity failure;
        su32_joystick0 <= (others => '0');
        s_incomplete <= '1';
        tick;
        su32_joystick0 <= x"00008004";
        tick;
        assert (s_save = '0' and s_unavailable = '0') severity failure;
        su32_joystick0 <= x"0000800c";
        tick;
        assert (s_restore = '1' and s_save = '0')
            report "Invalid controller SAVE blocked partial-restore retry" severity failure;
        complete(false);
        tick;
        assert (s_restore = '0' and s_set = '0') severity failure;
        report "STATE_CONTROLS_JOYSTICK_PASS";
        finish;
    end process;
end architecture;
