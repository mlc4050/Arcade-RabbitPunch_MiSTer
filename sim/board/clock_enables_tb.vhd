-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clock_enables_tb is
end entity;

architecture test of clock_enables_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_pixel, s_main, s_sound, s_ym, s_ym_half, s_adpcm : std_logic;
    function logic(v_condition : boolean) return std_logic is
    begin
        if (v_condition) then
            return '1';
        end if;
        return '0';
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            o_pixel_enable => s_pixel,
            o_main_phase_enable => s_main,
            o_sound_cpu_enable => s_sound,
            o_ym_enable => s_ym,
            o_ym_half_enable => s_ym_half,
            o_adpcm_enable => s_adpcm
        );
    stimulus : process
        variable vint_limit, vint_checks : natural := 0;
    begin
        for vint_epoch in 0 to 1 loop
            s_reset <= '1';
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (s_pixel = '0' and s_main = '0' and s_sound = '0' and
                s_ym = '0' and s_ym_half = '0' and s_adpcm = '0')
                report "Clock enables escaped reset" severity failure;
            wait until falling_edge(s_clk);
            s_reset <= '0';
            vint_limit := 17500;
            if (vint_epoch = 0) then
                vint_limit := 17513;
            end if;
            for vint_cycle in 1 to vint_limit loop
                wait until rising_edge(s_clk);
                assert (s_pixel = logic(vint_cycle mod 7 = 0))
                    report "Pixel enable is not a steady divide by seven" severity failure;
                assert (s_main = logic((vint_cycle * 12) / 35 /= ((vint_cycle - 1) * 12) / 35))
                    report "Main CPU phase cadence mismatch" severity failure;
                assert (s_sound = logic((vint_cycle * 3) / 35 /= ((vint_cycle - 1) * 3) / 35) and s_ym = s_sound)
                    report "Sound CPU/YM cadence mismatch" severity failure;
                assert (s_ym_half = logic((vint_cycle * 3) / 70 /= ((vint_cycle - 1) * 3) / 70))
                    report "YM half-rate enable lost alignment" severity failure;
                assert (s_adpcm = logic((vint_cycle * 12) / 875 /= ((vint_cycle - 1) * 12) / 875))
                    report "ADPCM cadence mismatch" severity failure;
                vint_checks := vint_checks + 5;
            end loop;
            wait until falling_edge(s_clk);
        end loop;
        report "CLOCK_ENABLES_PASS: exact rational pulse schedules and reset restart; checks=" & integer'image(vint_checks);
        std.env.finish;
        wait;
    end process;
end architecture;
