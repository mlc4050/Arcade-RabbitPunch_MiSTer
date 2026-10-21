-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_config.all;
use work.rabbitpunch_state_config.all;

entity state_controls_tb is
end entity;

architecture test of state_controls_tb is
    constant CSTR_STATE_CONFIG : string := F_STATE_CONFIG(true);
    constant CSTR_STATE_HEADER : string := "RabbitPunch;SS3E000000:40000;";
    function F_COUNT(vstr_text, vstr_match : string) return natural is
        variable vint_count : natural := 0;
    begin
        for vint_index in vstr_text'low to vstr_text'high - vstr_match'length + 1 loop
            if (vstr_text(vint_index to vint_index + vstr_match'length - 1) = vstr_match) then
                vint_count := vint_count + 1;
            end if;
        end loop;
        return vint_count;
    end function;
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal su128_status, su128_feedback : unsigned(127 downto 0) := (others => '0');
    signal s_ready : std_logic := '1';
    signal s_busy, s_finished, s_success : std_logic := '0';
    signal s_save, s_restore, s_unavailable, s_set : std_logic;
    signal su2_slot : unsigned(1 downto 0);
    signal s_info_request : std_logic;
    signal su8_info_message : unsigned(7 downto 0);
    signal s_disabled_save, s_disabled_restore, s_disabled_unavailable, s_disabled_set : std_logic;
    signal s_disabled_save_unavailable : std_logic;
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
            i_service_ready => s_ready,
            i_service_busy => s_busy,
            i_service_finished => s_finished,
            i_service_success => s_success,
            i_service_incomplete => '0',
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
    disabled : entity work.rabbitpunch_state_controls
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            iu128_status => su128_status,
            i_service_ready => s_ready,
            i_service_busy => s_busy,
            i_service_finished => s_finished,
            i_service_success => s_success,
            i_service_incomplete => '0',
            o_save => s_disabled_save,
            o_restore => s_disabled_restore,
            ou2_slot => open,
            o_unavailable => s_disabled_unavailable,
            o_save_unavailable => s_disabled_save_unavailable,
            o_status_set => s_disabled_set,
            ou128_status_data => open
        );
    stimulus : process
        variable vu128_expected : unsigned(127 downto 0);
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (s_disabled_save = '0' and s_disabled_restore = '0' and
                s_disabled_set = '0' and s_disabled_unavailable = '1' and s_disabled_save_unavailable = '1')
                report "Default-disabled controls emitted a command" severity failure;
        end procedure;
        procedure start(constant vbool_save : boolean;
                        constant vint_slot : natural;
                        constant v_increment : std_logic) is
        begin
            su128_status(9 downto 8) <= "00";
            su128_status(7) <= v_increment;
            su128_status(6 downto 5) <= to_unsigned(vint_slot, 2);
            tick;
            assert (s_unavailable = '0') report "Idle controls unavailable" severity failure;
            if (vbool_save) then
                su128_status(8) <= '1';
            else
                su128_status(9) <= '1';
            end if;
            tick;
            assert (su2_slot = vint_slot and s_unavailable = '1')
                report "Control admission/slot failed" severity failure;
            if (vbool_save) then
                assert (s_save = '1' and s_restore = '0' and s_info_request = '0') severity failure;
            else
                assert (s_save = '0' and s_restore = '1' and s_info_request = '1' and
                    su8_info_message = CINT_RESTORE_INFO_BASE + vint_slot)
                    report "Restore popup must identify the admitted slot" severity failure;
            end if;
            for vint_delay in 1 to 4 loop
                tick;
                assert (s_save = '0' and s_restore = '0' and s_set = '0' and s_info_request = '0' and
                    s_unavailable = '1' and su2_slot = vint_slot)
                    report "Held button retriggered or early increment occurred" severity failure;
            end loop;
        end procedure;
        procedure complete(constant v_success : std_logic;
                           constant vbool_increment : boolean;
                           constant vbool_acknowledge : boolean := true) is
        begin
            vu128_expected := su128_status;
            vu128_expected(6 downto 5) := su128_status(6 downto 5) + 1;
            s_finished <= '1';
            s_success <= v_success;
            tick;
            if (vbool_increment) then
                assert (s_set = '1' and su128_feedback = vu128_expected)
                    report "Successful save did not increment exactly the selected slot bits" severity failure;
                if (vbool_acknowledge) then
                    su128_status <= su128_feedback;
                end if;
            else
                assert (s_set = '0') report "Unexpected status feedback" severity failure;
            end if;
            s_finished <= '0';
            s_success <= '0';
            tick;
            assert (s_set = '0' and s_save = '0' and s_restore = '0')
                report "Completion/held trigger emitted another command" severity failure;
        end procedure;
    begin
        assert (F_STATE_CONFIG(false) = CSTR_DEFAULT_CONFIG_STRING)
            report "Disabled state configuration changed the normal OSD" severity failure;
        assert (CSTR_STATE_CONFIG(1 to CSTR_STATE_HEADER'length) = CSTR_STATE_HEADER)
            report "State host storage metadata is not in its header field" severity failure;
        assert (F_COUNT(CSTR_STATE_CONFIG,
            "H3T4,Save NVRAM;-;O[6:5],Savestate slot,1,2,3,4;" &
            "O7,Autoincrement slot,Off,On;H9T8,Save state;H8T9,Restore state;-;R0,Reset;") = 1)
            report "State controls are not together after NVRAM with separators and Reset last" severity failure;
        assert (F_COUNT(CSTR_STATE_CONFIG, "O[6:5],Savestate slot,") = 1 and
            F_COUNT(CSTR_STATE_CONFIG, "Autoincrement slot") = 1 and
            F_COUNT(CSTR_STATE_CONFIG, "Save state") = 1 and
            F_COUNT(CSTR_STATE_CONFIG, "Restore state") = 1 and
            F_COUNT(CSTR_STATE_CONFIG, "R0,Reset;") = 1) severity failure;
        assert (F_COUNT(CSTR_STATE_CONFIG,
            "J1,Fire/Punch,Missile,-,-,-,-,Start,Coin,Pause,Service,Test,Savestate (SS);") = 1)
            report "State controller mapping changed existing action positions" severity failure;
        assert (F_COUNT(CSTR_STATE_CONFIG, "I,") = 1 and CINT_SLOT_INFO_BASE = 2 and CINT_RESTORE_INFO_BASE = 6)
            report "Native info table must use the expected one-based message IDs" severity failure;
        assert (CSTR_STATE_CONFIG(CSTR_STATE_CONFIG'length - 161 + 1 to CSTR_STATE_CONFIG'length) =
            "I,Slot=SS+LR|Save/Load=SS+DU,Savestate slot 1,Savestate slot 2,Savestate slot 3,Savestate slot 4,Loading state 1,Loading state 2,Loading state 3,Loading state 4;")
            report "Native info messages must follow all OSD items in slot order" severity failure;
        su128_status <= x"FEDCBA98765432100123456789ABC01A";
        tick;
        s_initialize <= '0';
        tick;
        for vint_slot in 0 to 3 loop
            start(true, vint_slot, '1');
            complete('1', true);
        end loop;
        start(true, 1, '1');
        complete('1', true, false);
        for vint_delay in 1 to 8 loop
            tick;
            assert (s_unavailable = '1' and su2_slot = 1 and s_set = '0')
                report "Delayed host acknowledgment reopened the old slot" severity failure;
        end loop;
        su128_status(8) <= '0';
        tick;
        su128_status(8) <= '1';
        tick;
        assert (s_save = '0') report "Second SAVE admitted before slot acknowledgment" severity failure;
        su128_status <= su128_feedback;
        tick;
        assert (s_save = '0' and s_unavailable = '0' and su2_slot = 2)
            report "Host acknowledgment failed to resolve the slot ticket" severity failure;
        start(true, 2, '1');
        complete('0', false);
        for vint_slot in 0 to 3 loop
            start(false, vint_slot, '1');
            complete('1', false);
        end loop;
        start(false, 2, '1');
        complete('0', false);
        start(true, 2, '0');
        complete('1', false);
        start(true, 2, '1');
        su128_status(6 downto 5) <= "01";
        tick;
        assert (su2_slot = 2) report "Host edit changed the in-flight slot" severity failure;
        complete('1', false);
        start(true, 3, '1');
        su128_status(7) <= '0';
        tick;
        complete('1', false);
        -- Reject unavailable edges without deferring them into a later save.
        su128_status(9 downto 8) <= "00";
        s_ready <= '0';
        tick;
        su128_status(9 downto 8) <= "11";
        tick;
        assert (s_save = '0' and s_restore = '0' and s_unavailable = '1') severity failure;
        s_ready <= '1';
        tick;
        assert (s_save = '0' and s_restore = '0') severity failure;
        su128_status(9 downto 8) <= "00";
        s_busy <= '1';
        tick;
        su128_status(8) <= '1';
        tick;
        assert (s_save = '0' and s_unavailable = '1') severity failure;
        s_busy <= '0';
        tick;
        assert (s_save = '0') severity failure;
        -- SAVE has deterministic priority if both host actions rise together.
        su128_status(9 downto 8) <= "00";
        tick;
        su128_status(9 downto 8) <= "11";
        tick;
        assert (s_save = '1' and s_restore = '0' and s_info_request = '0') severity failure;
        complete('0', false);
        -- Reset abandons the UI ticket, and a high trigger stays consumed.
        start(true, 1, '1');
        s_initialize <= '1';
        tick;
        s_initialize <= '0';
        tick;
        assert (s_save = '0' and s_restore = '0' and s_unavailable = '0') severity failure;
        s_finished <= '1';
        s_success <= '1';
        tick;
        assert (s_set = '0') report "Stray completion incremented a reset operation" severity failure;
        report "STATE_CONTROLS_PASS four slots/wrap,final-save-only increment,delayed host acknowledgment,failed save/restore,no-auto,host edits,unavailable edges,priority,reset,default-disabled";
        finish;
    end process;
end architecture;
