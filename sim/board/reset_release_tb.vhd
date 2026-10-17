-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reset_release_tb is
end entity;

architecture test of reset_release_tb is
    signal s_clk : std_logic := '0';
    signal s_running : std_logic := '1';
    signal s_async_reset : std_logic := '1';
    signal s_reset : std_logic;
begin
    clock_driver : process
    begin
        wait for 5 ns;
        if (s_running = '1') then
            s_clk <= not s_clk;
        else
            s_clk <= '0';
        end if;
    end process;
    dut : entity work.rabbitpunch_reset_release
        port map (
            i_clk => s_clk,
            i_asynchronous_reset => s_async_reset,
            o_reset => s_reset
        );
    stimulus : process
    begin
        wait for 2 ns;
        assert (s_reset = '1') report "Initialization was not asserted" severity failure;
        for vint_epoch in 0 to 2 loop
            wait until falling_edge(s_clk);
            wait for 1 ns;
            s_async_reset <= '1';
            wait for 1 ns;
            assert (s_reset = '1') report "Asynchronous initialization required a clock" severity failure;
            wait for 1 ns;
            s_async_reset <= '0';
            for vint_edge in 1 to 3 loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
                if (vint_edge < 3) then
                    assert (s_reset = '1') report "Initialization released early" severity failure;
                else
                    assert (s_reset = '0') report "Initialization release did not use three edges" severity failure;
                end if;
            end loop;
        end loop;
        wait until falling_edge(s_clk);
        s_running <= '0';
        wait for 20 ns;
        s_async_reset <= '1';
        wait for 1 ns;
        assert (s_reset = '1') report "Lost-clock reset failed to assert" severity failure;
        s_async_reset <= '0';
        wait for 40 ns;
        assert (s_reset = '1') report "Reset released while clock was stopped" severity failure;
        s_running <= '1';
        for vint_edge in 1 to 3 loop
            wait until rising_edge(s_clk);
            wait for 1 ns;
            if (vint_edge < 3) then
                assert (s_reset = '1') report "Stopped-clock recovery released early" severity failure;
            else
                assert (s_reset = '0') report "Stopped-clock recovery failed" severity failure;
            end if;
        end loop;
        report "RESET_RELEASE_PASS: asynchronous assertion, three-edge release and stopped-clock recovery";
        std.env.finish;
        wait;
    end process;
end architecture;
