-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity timing_state_tb is
end entity;

architecture test of timing_state_tb is
    type t_trace is array(0 to 19999) of unsigned(55 downto 0);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_hold, s_load : std_logic := '0';
    signal s_pixel, s_main, s_sound, s_ym, s_half, s_adpcm : std_logic;
    signal s_line, s_frame, s_vblank, s_midframe, s_hsync, s_vsync : std_logic;
    signal su32_cadence, su32_restore : unsigned(31 downto 0) := (others => '0');
    signal su18_beam, su18_restore : unsigned(17 downto 0) := (others => '0');
    signal su56_observed : unsigned(55 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    su56_observed <= su32_cadence & su18_beam & s_pixel & s_main & s_sound & s_ym & s_half & s_adpcm;
    cadence : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            o_pixel_enable => s_pixel,
            o_main_phase_enable => s_main,
            o_sound_cpu_enable => s_sound,
            o_ym_enable => s_ym,
            o_ym_half_enable => s_half,
            o_adpcm_enable => s_adpcm,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu32_state => su32_restore,
            ou32_state => su32_cadence
        );
    raster : entity work.rabbitpunch_raster
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pixel_enable => s_pixel,
            ou9_horizontal_position => open,
            ou9_vertical_position => open,
            ou9_pixel_x => open,
            ou8_pixel_y => open,
            o_active => open,
            o_hsync => s_hsync,
            o_vsync => s_vsync,
            o_hblank => open,
            o_vblank => open,
            o_line_start => s_line,
            o_visible_line_start => open,
            o_frame_start => s_frame,
            o_vblank_start => s_vblank,
            o_half_frame => s_midframe,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu18_state => su18_restore,
            ou18_state => su18_beam
        );
    stimulus : process
        variable vu32_saved : unsigned(31 downto 0);
        variable vu18_saved : unsigned(17 downto 0);
        variable vu56_trace : t_trace;
        procedure cycle is
        begin
            wait until rising_edge(s_clk);
            wait until falling_edge(s_clk);
        end procedure;
    begin
        cycle;
        cycle;
        s_reset <= '0';
        for vint_round in 0 to 7 loop
            for vint_skip in 0 to 1301 + vint_round loop
                cycle;
            end loop;
            vu32_saved := su32_cadence;
            vu18_saved := su18_beam;
            for vint_cycle in vu56_trace'range loop
                vu56_trace(vint_cycle) := su56_observed;
                cycle;
            end loop;
            s_hold <= '1';
            cycle;
            su32_restore <= vu32_saved;
            su18_restore <= vu18_saved;
            s_load <= '1';
            cycle;
            s_load <= '0';
            for vint_wait in 0 to 19 loop
                cycle;
                assert (su32_cadence = vu32_saved and su18_beam = vu18_saved)
                    report "Held clock or raster state advanced" severity failure;
                assert (s_pixel = '0' and s_main = '0' and s_sound = '0' and s_ym = '0' and s_half = '0' and s_adpcm = '0')
                    report "Chip enable escaped freeze" severity failure;
                assert (s_line = '0' and s_frame = '0' and s_vblank = '0' and s_midframe = '0')
                    report "Raster event escaped freeze" severity failure;
            end loop;
            s_hold <= '0';
            wait for 1 ns;
            for vint_cycle in vu56_trace'range loop
                assert (su56_observed = vu56_trace(vint_cycle))
                    report "Timing continuation differs at cycle " & integer'image(vint_cycle) severity failure;
                cycle;
            end loop;
        end loop;
        report "TIMING_STATE_PASS repeated_roundtrips=8 exact_continuation_cycles=160000 all_chip_enables=checked beam=checked";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 10 ms;
        assert (false) report "Timing state test timed out" severity failure;
        wait;
    end process;
end architecture;
