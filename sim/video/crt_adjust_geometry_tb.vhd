-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity crt_adjust_geometry_tb is
    generic (
        GU5_HORIZONTAL_SIZE : unsigned(4 downto 0) := "00000";
        GU7_HORIZONTAL_POSITION : unsigned(6 downto 0) := "0000000";
        GU6_VERTICAL_SHIFT : unsigned(5 downto 0) := "000000";
        GINT_TEST_FRAME_LINES : positive := 12;
        GINT_VISIBLE_LINES : positive := 6
    );
end entity;

architecture test of crt_adjust_geometry_tb is
    constant CINT_FRAME_CLOCKS : positive := 432 * 7 * GINT_TEST_FRAME_LINES;
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_adjust, s_size_enable : std_logic := '1';
    signal s_pixel_enable, s_output_enable : std_logic;
    signal su5_size : unsigned(4 downto 0) := GU5_HORIZONTAL_SIZE;
    signal su7_position : unsigned(6 downto 0) := GU7_HORIZONTAL_POSITION;
    signal su6_shift : unsigned(5 downto 0) := GU6_VERTICAL_SHIFT;
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0);
    signal s_hsync, s_vsync, s_hblank, s_vblank : std_logic;
    signal s_output_hsync, s_output_vsync, s_output_hblank, s_output_vblank : std_logic;
    signal sint_phase : natural range 0 to 6 := 0;
    signal sint_x : natural range 0 to 431 := 0;
    signal sint_y : natural range 0 to GINT_TEST_FRAME_LINES - 1 := 0;
    signal sint_frames : natural := 0;
    signal s_score : std_logic := '0';
    signal sint_hsync_period, sint_hsync_width : natural := 0;
    signal sint_vsync_period, sint_vsync_width, sint_vsync_phase : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_pixel_enable <= '1' when sint_phase = 0 else '0';
    su8_red <= to_unsigned(sint_x mod 256, 8);
    su8_green <= to_unsigned(sint_x / 256, 8);
    su8_blue <= to_unsigned(sint_y, 8);
    s_hblank <= '0' when sint_x < 288 else '1';
    s_vblank <= '0' when sint_y < GINT_VISIBLE_LINES else '1';
    s_hsync <= '0' when sint_x >= 352 and sint_x < 392 else '1';
    s_vsync <= '0' when sint_y >= GINT_TEST_FRAME_LINES - 4 and sint_y < GINT_TEST_FRAME_LINES - 2 else '1';
    raster : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_initialize = '1') then
                sint_phase <= 0;
                sint_x <= 0;
                sint_y <= 0;
                sint_frames <= 0;
            else
                if (sint_phase = 6) then
                    sint_phase <= 0;
                else
                    sint_phase <= sint_phase + 1;
                end if;
                if (s_pixel_enable = '1') then
                    if (sint_x = 431) then
                        sint_x <= 0;
                        if (sint_y = GINT_TEST_FRAME_LINES - 1) then
                            sint_y <= 0;
                            sint_frames <= sint_frames + 1;
                        else
                            sint_y <= sint_y + 1;
                        end if;
                    else
                        sint_x <= sint_x + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    dut : entity work.rabbitpunch_crt_adjust
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_pixel_enable => s_pixel_enable,
            i_adjust => s_adjust,
            i_size_enable => s_size_enable,
            iu5_horizontal_size => su5_size,
            iu7_horizontal_position => su7_position,
            iu6_vertical_shift => su6_shift,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            i_horizontal_sync => s_hsync,
            i_vertical_sync => s_vsync,
            i_horizontal_blank => s_hblank,
            i_vertical_blank => s_vblank,
            o_pixel_enable => s_output_enable,
            ou8_red => su8_output_red,
            ou8_green => su8_output_green,
            ou8_blue => su8_output_blue,
            o_horizontal_sync => s_output_hsync,
            o_vertical_sync => s_output_vsync,
            o_horizontal_blank => s_output_hblank,
            o_vertical_blank => s_output_vblank
        );
    stimulus : process
    begin
        wait for 30 ns;
        wait until falling_edge(s_clk);
        s_initialize <= '0';
        wait until rising_edge(s_clk) and sint_frames = 2 and sint_y = GINT_TEST_FRAME_LINES - 2;
        s_score <= '1';
        wait;
    end process;
    sync_monitor : process(s_clk)
        variable vint_cycle, vint_last_horizontal_start, vint_last_vertical_start : natural := 0;
        variable v_previous_horizontal_sync, v_previous_vertical_sync : std_logic := '1';
    begin
        if (rising_edge(s_clk)) then
            vint_cycle := vint_cycle + 1;
            if (sint_frames >= 1) then
                if (s_output_hsync = '0' and v_previous_horizontal_sync = '1') then
                    sint_hsync_period <= vint_cycle - vint_last_horizontal_start;
                    vint_last_horizontal_start := vint_cycle;
                elsif (s_output_hsync = '1' and v_previous_horizontal_sync = '0') then
                    sint_hsync_width <= vint_cycle - vint_last_horizontal_start;
                end if;
                if (s_output_vsync = '0' and v_previous_vertical_sync = '1') then
                    sint_vsync_period <= vint_cycle - vint_last_vertical_start;
                    vint_last_vertical_start := vint_cycle;
                    sint_vsync_phase <= vint_cycle mod CINT_FRAME_CLOCKS;
                elsif (s_output_vsync = '1' and v_previous_vertical_sync = '0') then
                    sint_vsync_width <= vint_cycle - vint_last_vertical_start;
                end if;
            end if;
            v_previous_horizontal_sync := s_output_hsync;
            v_previous_vertical_sync := s_output_vsync;
        end if;
    end process;
    scoreboard : process(s_clk)
        variable vint_column, vint_row : natural := 0;
        variable v_previous_active : boolean := false;
        variable v_active : boolean;
    begin
        if (rising_edge(s_clk)) then
            if (s_score = '1' and s_output_enable = '1') then
                v_active := s_output_hblank = '0' and s_output_vblank = '0';
                if (v_active) then
                    assert (su8_output_red = vint_column mod 256 and su8_output_green = vint_column / 256 and
                        su8_output_blue = vint_row)
                        report "CRT active image mismatch row=" & integer'image(vint_row) &
                            " column=" & integer'image(vint_column) & " actual=" &
                            to_hstring(su8_output_red & su8_output_green & su8_output_blue)
                        severity failure;
                    vint_column := vint_column + 1;
                elsif (v_previous_active) then
                    assert (vint_column = 288) report "CRT output row width mismatch" severity failure;
                    vint_column := 0;
                    vint_row := vint_row + 1;
                    if (vint_row = GINT_VISIBLE_LINES) then
                        assert (sint_hsync_period = 3024 and sint_vsync_period = CINT_FRAME_CLOCKS)
                            report "CRT sync frequency changed" severity failure;
                        assert (sint_hsync_width >= 269 and sint_hsync_width <= 291 and
                            sint_vsync_width >= 6037 and sint_vsync_width <= 6059)
                            report "CRT sync width outside one read-pixel tolerance" severity failure;
                        report "CRT_ADJUST_GEOMETRY_PASS rows=" & integer'image(GINT_VISIBLE_LINES) &
                            " pixels=" & integer'image(288 * GINT_VISIBLE_LINES) & " width=288 hperiod=" &
                            integer'image(sint_hsync_period) & " hwidth=" & integer'image(sint_hsync_width) &
                            " vperiod=" & integer'image(sint_vsync_period) & " vwidth=" & integer'image(sint_vsync_width) &
                            " vphase=" & integer'image(sint_vsync_phase);
                        std.env.finish;
                    end if;
                end if;
                v_previous_active := v_active;
            end if;
        end if;
    end process;
    progress : process
        file v_progress : text open write_mode is "progress.txt";
        variable v_line : line;
    begin
        loop
            wait for 1 ms;
            write(v_line, time'image(now) & "; frame=" & integer'image(sint_frames) &
                "; row=" & integer'image(sint_y) & "; column=" & integer'image(sint_x));
            writeline(v_progress, v_line);
            flush(v_progress);
        end loop;
    end process;
    watchdog : process
    begin
        wait for 100 ms;
        assert (false) report "CRT geometry test did not complete" severity failure;
        wait;
    end process;
end architecture;
