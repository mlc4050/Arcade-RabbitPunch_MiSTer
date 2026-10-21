-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_main_bus_tb is
end entity;

architecture test of state_main_bus_tb is
    type t_owners is array(0 to 8) of natural;
    constant CINT_OWNERS : t_owners := (0, 0, 1, 2, 2, 2, 1, 0, 1);
    signal s_clk : std_logic := '0';
    signal s_reset, s_cpu_request, s_maintenance_request, s_state_request, s_state_access : std_logic := '0';
    signal s_cpu_reset, s_cpu_idle, s_idle, s_cpu_response, s_maintenance_response : std_logic;
    signal s_maintenance_block, s_state_response, s_state_busy : std_logic;
    signal s_maintenance_allowed, s_state_write : std_logic := '0';
    signal su24_state_address : unsigned(23 downto 0) := x"040200";
    signal su16_state_data : unsigned(15 downto 0) := x"A55A";
    signal su2_state_bytes : unsigned(1 downto 0) := "01";
    signal su16_cpu_data, su16_maintenance_data, su16_state_reply : unsigned(15 downto 0);
    signal s_backend_request, s_backend_write, s_backend_response : std_logic := '0';
    signal su24_backend_address : unsigned(23 downto 0);
    signal su16_backend_write_data, su16_backend_read_data : unsigned(15 downto 0) := (others => '0');
    signal su2_backend_bytes : unsigned(1 downto 0);
    signal sint_packets, sint_replies : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_state_main_bus
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            o_cpu_reset => s_cpu_reset,
            i_cpu_request => s_cpu_request,
            i_cpu_write => '0',
            iu24_cpu_address => x"000100",
            iu16_cpu_data => x"1122",
            iu2_cpu_bytes => "11",
            o_cpu_idle => s_cpu_idle,
            o_idle => s_idle,
            o_cpu_response => s_cpu_response,
            ou16_cpu_data => su16_cpu_data,
            i_maintenance_allowed => s_maintenance_allowed,
            i_maintenance_request => s_maintenance_request,
            i_maintenance_write => '0',
            iu24_maintenance_address => x"0FC100",
            iu16_maintenance_data => x"3344",
            iu2_maintenance_bytes => "10",
            o_maintenance_response => s_maintenance_response,
            ou16_maintenance_data => su16_maintenance_data,
            o_maintenance_block => s_maintenance_block,
            i_state_access => s_state_access,
            i_state_request => s_state_request,
            i_state_write => s_state_write,
            iu24_state_address => su24_state_address,
            iu16_state_data => su16_state_data,
            iu2_state_bytes => su2_state_bytes,
            o_state_response => s_state_response,
            ou16_state_data => su16_state_reply,
            o_state_busy => s_state_busy,
            o_backend_request => s_backend_request,
            o_backend_write => s_backend_write,
            ou24_backend_address => su24_backend_address,
            ou16_backend_data => su16_backend_write_data,
            ou2_backend_bytes => su2_backend_bytes,
            i_backend_response => s_backend_response,
            iu16_backend_data => su16_backend_read_data
        );
    oracle : process(s_clk)
        variable s_credit : boolean := false;
        variable vint_packet, vint_owner : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_backend_request = '1') then
                assert (not s_credit and vint_packet < 9) report "Repeated/unexpected main-bus request" severity failure;
                vint_owner := CINT_OWNERS(vint_packet);
                case vint_owner is
                    when 0 =>
                        assert (su24_backend_address = x"000100" and su16_backend_write_data = x"1122" and
                            su2_backend_bytes = "11") severity failure;
                    when 1 =>
                        assert (su24_backend_address = x"0FC100" and su16_backend_write_data = x"3344" and
                            su2_backend_bytes = "10") severity failure;
                    when others =>
                        assert (su24_backend_address = x"040200" and su16_backend_write_data = x"A55A" and
                            su2_backend_bytes = "01") report "Canceled state packet changed" severity failure;
                end case;
                assert ((s_backend_write = '1') = (vint_packet = 4)) severity failure;
                s_credit := true;
                vint_packet := vint_packet + 1;
                sint_packets <= vint_packet;
            end if;
            if (s_backend_response = '1') then
                assert (s_credit) severity failure;
                assert ((s_cpu_response = '1') = (vint_owner = 0)) severity failure;
                assert ((s_maintenance_response = '1') = (vint_owner = 1)) severity failure;
                assert ((s_state_response = '1') = (vint_owner = 2))
                    report "State reply crossed mode/reset ownership" severity failure;
                assert (su16_cpu_data = su16_backend_read_data and su16_maintenance_data = su16_backend_read_data and
                    su16_state_reply = su16_backend_read_data) severity failure;
                s_credit := false;
                sint_replies <= sint_replies + 1;
            else
                assert (s_cpu_response = '0' and s_maintenance_response = '0' and s_state_response = '0') severity failure;
            end if;
        end if;
    end process;
    stimulus : process
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure wait_packets(vint_count : positive) is
        begin
            for vint_timeout in 0 to 31 loop
                exit when sint_packets = vint_count;
                cycles;
                assert (vint_timeout < 31) severity failure;
            end loop;
        end procedure;
        procedure reply_owned is
        begin
            cycles(13);
            su16_backend_read_data <= to_unsigned(16#9000# + sint_packets, 16);
            s_backend_response <= '1';
            cycles;
            s_backend_response <= '0';
            cycles(2);
        end procedure;
        procedure issue_cpu is
        begin
            s_cpu_request <= '1';
            wait for 1 ns;
            assert (s_backend_request = '1' and su24_backend_address = x"000100")
                report "State adapter added a normal CPU request cycle" severity failure;
            cycles;
            s_cpu_request <= '0';
        end procedure;
        procedure issue_state(s_write, s_access, s_reset_now : std_logic) is
        begin
            su24_state_address <= x"040200";
            su16_state_data <= x"A55A";
            su2_state_bytes <= "01";
            s_state_write <= s_write;
            s_state_access <= s_access;
            s_reset <= s_reset_now;
            s_state_request <= '1';
            cycles;
            s_state_request <= '0';
            s_reset <= '0';
            -- These live fields are deliberately hostile after acceptance.
            su24_state_address <= x"0A0000";
            su16_state_data <= x"DEAD";
            su2_state_bytes <= "10";
            s_state_write <= not s_write;
        end procedure;
    begin
        s_reset <= '1';
        cycles(2);
        s_reset <= '0';
        cycles;
        issue_cpu;
        wait_packets(1);
        reply_owned;
        -- Admission can close on the edge an already accepted NVRAM pulse
        -- arrives. Preserve that credit and the original direct CPU priority.
        s_state_access <= '1';
        s_maintenance_request <= '1';
        cycles;
        s_maintenance_request <= '0';
        cycles(3);
        assert (sint_packets = 1 and s_idle = '0') severity failure;
        issue_cpu;
        wait_packets(2);
        reply_owned;
        s_maintenance_allowed <= '1';
        wait_packets(3);
        reply_owned;
        s_state_access <= '0';
        cycles;
        issue_state('0', '1', '0');
        s_state_access <= '0';
        wait_packets(4);
        assert (s_state_busy = '1' and s_maintenance_block = '1') severity failure;
        reply_owned;
        -- A registered accepted state pulse may arrive on the reset/cancel
        -- edge even though live access is already low. It still owns a reply.
        issue_state('1', '0', '1');
        wait_packets(5);
        assert (s_cpu_reset = '1') severity failure;
        reply_owned;
        assert (s_cpu_reset = '0' and s_state_busy = '0') severity failure;
        issue_state('0', '1', '0');
        wait_packets(6);
        s_reset <= '1';
        cycles;
        s_reset <= '0';
        reply_owned;
        assert (s_cpu_reset = '1' and s_maintenance_block = '1')
            report "Reset released CPU before state session retired" severity failure;
        s_state_access <= '0';
        cycles(2);
        assert (s_cpu_reset = '0') severity failure;
        s_maintenance_request <= '1';
        cycles;
        s_maintenance_request <= '0';
        wait_packets(7);
        reply_owned;
        s_maintenance_request <= '1';
        issue_cpu;
        s_maintenance_request <= '0';
        wait_packets(8);
        s_reset <= '1';
        cycles;
        s_reset <= '0';
        cycles;
        assert (s_cpu_reset = '0') report "Normal reset acquired a state debt lease" severity failure;
        reply_owned;
        wait_packets(9);
        reply_owned;
        assert (sint_packets = 9 and sint_replies = 9 and s_idle = '1' and s_state_busy = '0') severity failure;
        report "STATE_MAIN_BUS_PASS directCPU,NVRAMpriority,latched state packets,late owner,cancel/reset debt,reset edge request" severity note;
        stop;
        wait;
    end process;
end architecture;
