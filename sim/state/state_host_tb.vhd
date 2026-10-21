-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_config.all;

entity state_host_tb is
end entity;

architecture test of state_host_tb is
    component state_host_check is
        port (
            i_clk : in std_logic;
            i_initialize : in std_logic;
            iu16_host_data : in unsigned(15 downto 0);
            i_host_strobe : in std_logic;
            i_uio_select : in std_logic;
            i_file_select : in std_logic;
            ou16_host_response : out unsigned(15 downto 0);
            o_host_wait : out std_logic;
            o_wide_mode : out std_logic;
            iu16_menu_mask : in unsigned(15 downto 0);
            ou128_status : out unsigned(127 downto 0);
            i_service_ready : in std_logic;
            i_service_busy : in std_logic;
            i_service_finished : in std_logic;
            i_service_success : in std_logic;
            o_save : out std_logic;
            o_restore : out std_logic;
            ou2_slot : out unsigned(1 downto 0)
        );
    end component;
    constant CSTR_CONFIG : string := F_STATE_CONFIG(true);
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal su16_host_data : unsigned(15 downto 0) := (others => '0');
    signal su16_response : unsigned(15 downto 0);
    signal s_strobe, s_select : std_logic := '0';
    signal s_ready, s_busy, s_finished, s_success : std_logic := '0';
    signal s_save, s_restore, s_wait, s_wide : std_logic;
    signal su128_status : unsigned(127 downto 0);
    signal su2_slot : unsigned(1 downto 0);
    signal sint_saves, sint_restores : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    dut : state_host_check
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            iu16_host_data => su16_host_data,
            i_host_strobe => s_strobe,
            i_uio_select => s_select,
            i_file_select => '0',
            ou16_host_response => su16_response,
            o_host_wait => s_wait,
            o_wide_mode => s_wide,
            iu16_menu_mask => x"00A5",
            ou128_status => su128_status,
            i_service_ready => s_ready,
            i_service_busy => s_busy,
            i_service_finished => s_finished,
            i_service_success => s_success,
            o_save => s_save,
            o_restore => s_restore,
            ou2_slot => su2_slot
        );
    commands : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            assert (s_save /= '1' or s_restore /= '1') severity failure;
            if (s_save = '1') then
                sint_saves <= sint_saves + 1;
            end if;
            if (s_restore = '1') then
                sint_restores <= sint_restores + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu128_status, vu128_expected : unsigned(127 downto 0);
        variable vint_updates : natural := 0;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure word(vint_data : natural) is
        begin
            su16_host_data <= to_unsigned(vint_data, 16);
            s_strobe <= '1';
            cycles(1);
            s_strobe <= '0';
            cycles(3);
        end procedure;
        procedure uio_begin(vint_command : natural) is
        begin
            cycles(1);
            s_select <= '1';
            word(vint_command);
        end procedure;
        procedure uio_end is
        begin
            s_select <= '0';
            cycles(4);
        end procedure;
        procedure set_status(vu128_value : unsigned(127 downto 0)) is
        begin
            uio_begin(16#1E#);
            for vint_word in 0 to 7 loop
                word(to_integer(vu128_value(vint_word * 16 + 15 downto vint_word * 16)));
            end loop;
            uio_end;
            assert (su128_status = vu128_value) report "Native host status write differs" severity failure;
        end procedure;
        procedure feedback(vbool_payload : boolean) is
        begin
            uio_begin(16#29#);
            assert (su16_response = 16#A0# + vint_updates)
                report "Native host status-request generation differs" severity failure;
            if (vbool_payload) then
                for vint_word in 0 to 7 loop
                    word(0);
                    assert (su16_response = vu128_expected(vint_word * 16 + 15 downto vint_word * 16))
                        report "Native host status-request slot or unrelated payload differs" severity failure;
                end loop;
            end if;
            uio_end;
        end procedure;
        procedure complete(v_success : std_logic) is
        begin
            s_success <= v_success;
            s_finished <= '1';
            cycles(3);
            s_finished <= '0';
            s_success <= '0';
            s_busy <= '0';
            cycles(3);
        end procedure;
    begin
        cycles(5);
        s_initialize <= '0';
        cycles(3);
        assert (s_wide = '0') severity failure;
        uio_begin(16#14#);
        for vint_char in CSTR_CONFIG'range loop
            word(0);
            assert (su16_response(7 downto 0) = character'pos(CSTR_CONFIG(vint_char)))
                report "Native host state configuration string differs" severity failure;
        end loop;
        uio_end;
        uio_begin(16#2E#);
        word(0);
        assert (su16_response = x"01A5") report "Unavailable mask lost existing menu bits" severity failure;
        uio_end;
        s_ready <= '1';
        cycles(3);
        uio_begin(16#2E#);
        word(0);
        assert (su16_response = x"00A5") severity failure;
        uio_end;
        feedback(false);
        for vint_slot in 0 to 3 loop
            vu128_status := x"D234CAFE987654320123456789AB001A";
            vu128_status(7) := '1';
            vu128_status(6 downto 5) := to_unsigned(vint_slot, 2);
            set_status(vu128_status);
            vu128_status(8) := '1';
            set_status(vu128_status);
            assert (sint_saves = vint_slot + 1 and su2_slot = vint_slot and sint_restores = 0)
                report "Native host SAVE admission differs" severity failure;
            s_busy <= '1';
            -- A successful private CPU return is not final DDR completion.
            s_success <= '1';
            cycles(5);
            feedback(false);
            vu128_expected := vu128_status;
            vu128_expected(6 downto 5) := vu128_expected(6 downto 5) + 1;
            complete('1');
            vint_updates := vint_updates + 1;
            feedback(true);
            assert (su128_status = vu128_status)
                report "Status request bypassed the host acknowledgment protocol" severity failure;
            cycles(8);
            uio_begin(16#2E#);
            word(0);
            assert (su16_response = x"01A5") report "Old slot available before host acknowledgment" severity failure;
            uio_end;
            set_status(vu128_expected);
            assert (sint_saves = vint_slot + 1) report "Host slot acknowledgment retriggered SAVE" severity failure;
            uio_begin(16#2E#);
            word(0);
            assert (su16_response = x"00A5") report "Acknowledged slot stayed unavailable" severity failure;
            uio_end;
        end loop;
        vu128_status := vu128_expected;
        vu128_status(9 downto 8) := "00";
        set_status(vu128_status);
        vu128_status(8) := '1';
        set_status(vu128_status);
        complete('0');
        feedback(false);
        for vint_result in 0 to 1 loop
            vu128_status(9 downto 8) := "00";
            set_status(vu128_status);
            vu128_status(9) := '1';
            set_status(vu128_status);
            assert (sint_restores = vint_result + 1) severity failure;
            if (vint_result = 0) then
                complete('0');
            else
                complete('1');
            end if;
            feedback(false);
        end loop;
        assert (sint_saves = 5 and sint_restores = 2 and vint_updates = 4) severity failure;
        report "STATE_HOST_PASS actual_hps_config status128 slot_feedback4 wrap final_save_only failures_restore_no_increment host_ack_no_retrigger masks";
        finish;
    end process;
end architecture;
