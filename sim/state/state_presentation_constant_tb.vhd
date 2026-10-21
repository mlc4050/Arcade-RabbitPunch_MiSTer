-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity state_presentation_constant_tb is
end entity;

architecture test of state_presentation_constant_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_done, s_unblanked : std_logic;
    signal su2_mode : unsigned(1 downto 0);
    signal su32_writes : unsigned(31 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.state_presentation_constant_eval
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            o_done => s_done,
            ou2_mode => su2_mode,
            ou32_writes => su32_writes,
            o_unblanked => s_unblanked
        );
    stimulus : process
        file f_result : text open write_mode is "constant_result.txt";
        variable v_line : line;
    begin
        for vint_cycle in 1 to 4 loop
            wait until falling_edge(s_clk);
        end loop;
        s_initialize <= '0';
        wait until s_done = '1';
        wait until falling_edge(s_clk);
        write(v_line, to_integer(su2_mode));
        write(v_line, string'(" "));
        write(v_line, to_integer(su32_writes));
        write(v_line, string'(" "));
        write(v_line, to_integer(unsigned'(0 => s_unblanked)));
        writeline(f_result, v_line);
        assert (su2_mode = 1 and su32_writes > 0 and s_unblanked = '1')
            report "Constant rotation did not publish" severity failure;
        report "STATE_PRESENTATION_CONSTANT_PASS";
        finish;
    end process;
end architecture;
