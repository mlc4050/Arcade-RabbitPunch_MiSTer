-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pll_tb is
end entity;

architecture test of pll_tb is
    signal s_reference_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_system_clk, s_sdram_clk, s_locked, s_core_reset : std_logic;
begin
    s_reference_clk <= not s_reference_clk after 10 ns;
    dut : entity work.rabbitpunch_pll
        port map (
            i_reference_clk => s_reference_clk,
            i_reset => s_reset,
            o_system_clk => s_system_clk,
            o_sdram_clk => s_sdram_clk,
            o_locked => s_locked
        );
    initialization : entity work.rabbitpunch_reset_release
        port map (
            i_clk => s_system_clk,
            i_asynchronous_reset => s_reset or not s_locked,
            o_reset => s_core_reset
        );
    stimulus : process
        variable vtime_previous, vtime_edge, vtime_phase, vtime_epoch_start : time;
    begin
        wait for 100 ns;
        s_reset <= '0';
        for vint_epoch in 0 to 1 loop
            wait until s_locked = '1' for 100 us;
            assert (s_locked = '1') report "Vendor PLL model did not lock" severity failure;
            wait until s_core_reset = '0' for 1 us;
            assert (s_core_reset = '0') report "Core initialization did not release after PLL lock" severity failure;
            wait until rising_edge(s_system_clk);
            vtime_previous := now;
            vtime_epoch_start := now;
            -- The installed generic PLL model resynchronizes with a documented
            -- 10 ps drift budget. Check tight average frequency across 16 exact
            -- 14-output/15-reference periods, allowing that individual jitter.
            for vint_edge in 1 to 224 loop
                wait until rising_edge(s_system_clk);
                vtime_edge := now;
                assert (vtime_edge - vtime_previous >= 21416 ps and vtime_edge - vtime_previous <= 21442 ps)
                    report "Vendor PLL system period mismatch: " & time'image(vtime_edge - vtime_previous) severity failure;
                wait until rising_edge(s_sdram_clk);
                vtime_phase := now - vtime_edge;
                assert (vtime_phase >= 10702 ps and vtime_phase <= 10726 ps)
                    report "Vendor PLL shifted SDRAM phase mismatch: " & time'image(vtime_phase) severity failure;
                vtime_previous := vtime_edge;
            end loop;
            assert (vtime_edge - vtime_epoch_start >= 4799980 ps and vtime_edge - vtime_epoch_start <= 4800020 ps)
                report "PLL average frequency differs from 14/15 of the 50 MHz reference: " &
                    time'image(vtime_edge - vtime_epoch_start) severity failure;
            if (vint_epoch = 0) then
                s_reset <= '1';
                wait for 1 ns;
                assert (s_core_reset = '1') report "PLL reset did not immediately initialize the core" severity failure;
                wait for 100 ns;
                assert (s_locked = '0') report "PLL lock survived reset" severity failure;
                s_reset <= '0';
            end if;
        end loop;
        report "PLL_PASS: vendor-model lock/relock, 46 2/3 MHz periods and provisional half-period SDRAM output";
        std.env.finish;
        wait;
    end process;
end architecture;
