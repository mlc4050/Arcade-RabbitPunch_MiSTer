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
    signal s_busy : std_logic := '0';
    signal s_finished, s_success, s_incomplete : std_logic := '0';
    signal s_save, s_restore, s_set, s_unavailable : std_logic;
    signal su2_slot : unsigned(1 downto 0);
    signal s_disabled_save, s_disabled_restore : std_logic;
    signal s_info_request, s_disabled_info : std_logic;
    signal su8_info_message : unsigned(7 downto 0);
    signal sint_info_count : natural := 0;
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
            i_service_busy => s_busy,
            i_service_finished => s_finished,
            i_service_success => s_success,
            o_info_request => s_disabled_info,
            ou8_info_message => open,
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
            i_service_busy => s_busy,
            i_service_finished => s_finished,
            i_service_success => s_success,
            i_service_incomplete => s_incomplete,
            o_info_request => s_info_request,
            ou8_info_message => su8_info_message,
            o_save => s_save,
            o_restore => s_restore,
            ou2_slot => su2_slot,
            o_unavailable => s_unavailable,
            o_save_unavailable => open,
            o_status_set => s_set,
            ou128_status_data => su128_feedback
        );
    popup_monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_info_request = '1') then
                assert (s_set = '1' and s_save = '0' and s_restore = '0')
                    report "Slot popup without an accepted slot-selection request" severity failure;
                assert (su8_info_message = CINT_SLOT_INFO_BASE + to_integer(su128_feedback(6 downto 5)))
                    report "Popup message does not match the requested slot" severity failure;
                sint_info_count <= sint_info_count + 1;
            end if;
        end if;
    end process;
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (s_disabled_save = '0' and s_disabled_restore = '0' and s_disabled_info = '0')
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
        procedure change_slot(vint_player, vint_direction, vint_expected : natural) is
            variable vu128_expected : unsigned(127 downto 0);
            variable vint_previous_count : natural;
        begin
            su32_joystick0 <= (others => '0');
            su32_joystick1 <= (others => '0');
            tick;
            vint_previous_count := sint_info_count;
            vu128_expected := su128_status;
            vu128_expected(6 downto 5) := to_unsigned(vint_expected, 2);
            if (vint_player = 0) then
                su32_joystick0 <= to_unsigned(16#8000# + 2 ** vint_direction, 32);
            else
                su32_joystick1 <= to_unsigned(16#8000# + 2 ** vint_direction, 32);
            end if;
            tick;
            assert (s_set = '1' and su128_feedback = vu128_expected and
                s_save = '0' and s_restore = '0' and s_unavailable = '1' and
                s_info_request = '1' and su8_info_message = CINT_SLOT_INFO_BASE + vint_expected)
                report "Controller slot selection lost status, direction, wrap or feedback guard" severity failure;
            for vint_cycle in 0 to 3 loop
                tick;
                assert (s_set = '0' and s_save = '0' and s_restore = '0' and s_info_request = '0')
                    report "Held slot-selection chord repeated or issued a command" severity failure;
            end loop;
            assert (sint_info_count = vint_previous_count + 1)
                report "Held slot chord did not produce exactly one popup" severity failure;
            su128_status <= su128_feedback;
            tick;
            tick;
            assert (s_unavailable = '0' and su2_slot = vint_expected and s_set = '0')
                report "Selected controller slot did not synchronize with OSD" severity failure;
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
        -- Controller slot selection shares the host's OSD slot, independently
        -- of autoincrement. Both directions wrap and both players can use it.
        su32_joystick0 <= (others => '0');
        su32_joystick1 <= (others => '0');
        s_incomplete <= '0';
        su128_status(7) <= '0';
        su128_status(100) <= '1';
        tick;
        change_slot(0, 1, 3);
        change_slot(0, 0, 0);
        change_slot(1, 0, 1);
        change_slot(1, 1, 0);
        change_slot(0, 0, 1);
        change_slot(0, 0, 2);
        change_slot(0, 0, 3);
        change_slot(0, 0, 0);

        -- SS and direction must belong to the same controller. Opposing
        -- directions do not pick an arbitrary winner.
        su32_joystick0 <= x"00008000";
        su32_joystick1 <= x"00000001";
        tick;
        assert (s_set = '0') report "Cross-controller SS/Right changed slot" severity failure;
        su32_joystick0 <= x"00008003";
        tick;
        assert (s_set = '0') report "Opposing directions changed slot" severity failure;
        su32_joystick0 <= (others => '0');
        su32_joystick1 <= (others => '0');
        tick;

        -- Busy/unavailable edges are discarded, not replayed on becoming ready.
        s_busy <= '1';
        su32_joystick0 <= x"00008001";
        tick;
        s_busy <= '0';
        tick;
        assert (s_set = '0') report "Busy selection edge was deferred" severity failure;
        su32_joystick0 <= (others => '0');
        tick;
        s_ready <= '0';
        su32_joystick1 <= x"00008002";
        tick;
        s_ready <= '1';
        tick;
        assert (s_set = '0') report "Unavailable selection edge was deferred" severity failure;
        change_slot(1, 0, 1);

        -- SAVE cannot use the previous slot while feedback is unacknowledged.
        su32_joystick1 <= (others => '0');
        tick;
        su32_joystick0 <= x"00008001";
        tick;
        assert (s_set = '1' and su128_feedback(6 downto 5) = 2) severity failure;
        su32_joystick1 <= x"00008004";
        tick;
        assert (s_save = '0') report "SAVE bypassed pending slot feedback" severity failure;
        su128_status <= su128_feedback;
        tick;
        tick;
        assert (s_save = '0') report "Held SAVE was replayed after slot feedback" severity failure;
        su32_joystick0 <= (others => '0');
        su32_joystick1 <= (others => '0');
        tick;
        su32_joystick1 <= x"00008004";
        tick;
        assert (s_save = '1' and su2_slot = 2)
            report "SAVE did not use controller-selected slot" severity failure;
        su32_joystick1 <= (others => '0');
        su32_joystick0 <= x"00008002";
        tick;
        assert (s_set = '0' and su2_slot = 2)
            report "Slot changed during an active state transfer" severity failure;
        complete(true);
        tick;
        assert (s_set = '0' and su2_slot = 2)
            report "Pending selection was deferred until transfer completion" severity failure;
        su32_joystick0 <= (others => '0');
        tick;
        su32_joystick0 <= x"00008008";
        tick;
        assert (s_restore = '1' and su2_slot = 2)
            report "RESTORE did not use controller-selected slot" severity failure;
        complete(true);
        tick;
        su32_joystick0 <= (others => '0');
        tick;
        change_slot(0, 1, 1);
        assert (sint_info_count = 11)
            report "Unexpected popup on reset, auto increment, operation or rejected chord" severity failure;
        report "STATE_CONTROLS_JOYSTICK_PASS";
        finish;
    end process;
end architecture;
