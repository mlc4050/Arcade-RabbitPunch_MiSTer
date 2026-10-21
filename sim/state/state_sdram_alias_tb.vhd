-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity state_sdram_alias_tb is
end entity;

architecture test of state_sdram_alias_tb is
    signal s_clk, s_chip_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_initialized, s_complete : std_logic;
    signal su32_clock : unsigned(31 downto 0);
    signal su3_requests, su3_ready, su3_valid, su3_reads : unsigned(2 downto 0);
    signal su64_data0, su64_data1, su64_data2 : unsigned(63 downto 0);
    signal su22_command : unsigned(21 downto 0);
begin
    s_clk <= not s_clk after 10714 ps;
    s_chip_clk <= transport s_clk after 5357 ps;
    dut : entity work.state_sdram_alias_eval
        port map (
            i_clk => s_clk,
            i_chip_clk => s_chip_clk,
            i_initialize => s_initialize,
            o_initialized => s_initialized,
            o_complete => s_complete,
            ou32_clock => su32_clock,
            ou3_requests => su3_requests,
            ou3_ready => su3_ready,
            ou3_valid => su3_valid,
            ou3_reads => su3_reads,
            ou64_data0 => su64_data0,
            ou64_data1 => su64_data1,
            ou64_data2 => su64_data2,
            ou22_command => su22_command
        );
    reset_fixture : process
    begin
        for vint_cycle in 1 to 32 loop
            wait until falling_edge(s_clk);
        end loop;
        s_initialize <= '0';
        wait;
    end process;
    observe : process
        file f_trace : text open write_mode is "alias_trace.txt";
        variable vtyp_line : line;
        variable vu64_data : unsigned(63 downto 0);
        variable vint_reads : natural := 0;
    begin
        wait until rising_edge(s_clk);
        wait for 1 ns;
        if (s_initialized = '1') then
            assert (not is_x(su3_requests & su3_ready & su3_valid & su3_reads & su22_command))
                report "Undefined native command observation req=" & to_hstring(su3_requests) &
                    " ready=" & to_hstring(su3_ready) & " valid=" & to_hstring(su3_valid) &
                    " reads=" & to_hstring(su3_reads) & " command=" & to_hstring(su22_command)
                severity failure;
            write(vtyp_line, string'("C "));
            write(vtyp_line, to_integer(su32_clock));
            write(vtyp_line, string'(" ") & to_hstring(su3_requests) & " " &
                to_hstring(su3_ready) & " " & to_hstring(su3_valid) & " " &
                to_hstring(su3_reads) & " " & to_hstring(su22_command));
            writeline(f_trace, vtyp_line);
            for vint_port in 0 to 2 loop
                if (su3_reads(vint_port) = '1') then
                    case vint_port is
                        when 0 => vu64_data := su64_data0;
                        when 1 => vu64_data := su64_data1;
                        when others => vu64_data := su64_data2;
                    end case;
                    assert (not is_x(vu64_data)) report "Undefined native read observation" severity failure;
                    write(vtyp_line, string'("R "));
                    write(vtyp_line, to_integer(su32_clock));
                    write(vtyp_line, string'(" "));
                    write(vtyp_line, vint_port);
                    write(vtyp_line, string'(" ") & to_hstring(vu64_data));
                    writeline(f_trace, vtyp_line);
                    vint_reads := vint_reads + 1;
                end if;
            end loop;
            if (s_complete = '1') then
                assert (vint_reads = 192) report "Native read coverage differs" severity failure;
                report "STATE_SDRAM_ALIAS_PASS seven_inout_stages writes=256 reads=192 all_three_ports";
                finish;
            end if;
        end if;
    end process;
    timeout : process
    begin
        wait for 1 ms;
        assert (false) report "Seven-stage SDRAM test timeout" severity failure;
    end process;
end architecture;
