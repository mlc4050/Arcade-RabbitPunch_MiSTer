-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity fm_waveform_tb is
end entity;

architecture test of fm_waveform_tb is
    signal s_clk : std_logic := '0';
    signal s_sample, s_complete : std_logic;
    signal su16_left, su16_right, su16_full_left, su16_full_right : unsigned(15 downto 0);
begin
    s_clk <= not s_clk after 10714 ps;
    dut : entity work.fm_waveform_fixture
        port map (
            i_clk => s_clk,
            o_sample => s_sample,
            o_complete => s_complete,
            ou16_left => su16_left,
            ou16_right => su16_right,
            ou16_full_left => su16_full_left,
            ou16_full_right => su16_full_right
        );
    capture : process
        file samples : text open write_mode is "pcm.txt";
        variable v_line : line;
        variable vint_count : natural := 0;
    begin
        wait until falling_edge(s_clk);
        if (s_sample = '1') then
            write(v_line, to_hstring(su16_left) & " " & to_hstring(su16_right) &
                " " & to_hstring(su16_full_left) & " " & to_hstring(su16_full_right));
            writeline(samples, v_line);
            vint_count := vint_count + 1;
        end if;
        if (s_complete = '1') then
            assert (vint_count = 256) report "FM waveform sample count mismatch" severity failure;
            report "FM_WAVEFORM_PASS samples=256";
            finish;
        end if;
    end process;
    watchdog : process
    begin
        wait for 30 ms;
        assert false report "FM waveform fixture timeout" severity failure;
    end process;
end architecture;
