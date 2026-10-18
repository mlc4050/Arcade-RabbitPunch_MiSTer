-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity video_options_tb is
    generic (
        GINT_MODE : natural := 0;
        GINT_VISIBLE_HEIGHT : positive := 8;
        GINT_TOTAL_HEIGHT : positive := 16;
        GINT_VERTICAL_SYNC_START : natural := 12;
        GINT_VERTICAL_SYNC_END : positive := 14
    );
end entity;

architecture test of video_options_tb is
    component rabbitpunch_video_options is
        port (
            i_clk : in std_logic;
            i_pixel_enable : in std_logic;
            iu8_red : in unsigned(7 downto 0);
            iu8_green : in unsigned(7 downto 0);
            iu8_blue : in unsigned(7 downto 0);
            i_horizontal_sync : in std_logic;
            i_vertical_sync : in std_logic;
            i_horizontal_blank : in std_logic;
            i_vertical_blank : in std_logic;
            i_forced_scandoubler : in std_logic;
            i_direct_video : in std_logic;
            iu3_effect : in unsigned(2 downto 0);
            o_pixel_enable : out std_logic;
            ou8_red : out unsigned(7 downto 0);
            ou8_green : out unsigned(7 downto 0);
            ou8_blue : out unsigned(7 downto 0);
            o_horizontal_sync : out std_logic;
            o_vertical_sync : out std_logic;
            o_data_enable : out std_logic;
            ou2_scanlines : out unsigned(1 downto 0)
        );
    end component;
    signal s_clk : std_logic := '0';
    signal s_ce : std_logic := '0';
    signal sint_phase : natural range 0 to 6 := 0;
    signal sint_x : natural range 0 to 431 := 0;
    signal sint_y : natural range 0 to GINT_TOTAL_HEIGHT - 1 := 0;
    signal sint_frames : natural := 0;
    signal s_hs, s_vs, s_hb, s_vb, s_forced, s_direct : std_logic;
    signal su3_effect : unsigned(2 downto 0);
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal s_output_ce, s_output_hs, s_output_vs, s_output_de : std_logic;
    signal su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0);
    signal su2_scanlines : unsigned(1 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    s_ce <= '1' when sint_phase = 6 else '0';
    s_hs <= '0' when sint_x >= 352 and sint_x < 392 else '1';
    s_vs <= '0' when sint_y >= GINT_VERTICAL_SYNC_START and sint_y < GINT_VERTICAL_SYNC_END else '1';
    s_hb <= '0' when sint_x < 288 else '1';
    s_vb <= '0' when sint_y < GINT_VISIBLE_HEIGHT else '1';
    -- Three distinct colour lanes catch swaps; flat fields also permit exact
    -- comparison through HQ2x without an independent smoothing algorithm.
    su8_red <= x"31";
    su8_green <= x"79";
    su8_blue <= x"C5";
    s_forced <= '1' when GINT_MODE = 1 or GINT_MODE = 6 else '0';
    s_direct <= '1' when GINT_MODE = 6 else '0';
    su3_effect <= to_unsigned(GINT_MODE - 1, 3) when GINT_MODE >= 2 and GINT_MODE <= 5 else
        to_unsigned(4, 3) when GINT_MODE = 6 else (others => '0');
    dut : rabbitpunch_video_options
        port map (
            i_clk => s_clk,
            i_pixel_enable => s_ce,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            i_horizontal_sync => s_hs,
            i_vertical_sync => s_vs,
            i_horizontal_blank => s_hb,
            i_vertical_blank => s_vb,
            i_forced_scandoubler => s_forced,
            i_direct_video => s_direct,
            iu3_effect => su3_effect,
            o_pixel_enable => s_output_ce,
            ou8_red => su8_output_red,
            ou8_green => su8_output_green,
            ou8_blue => su8_output_blue,
            o_horizontal_sync => s_output_hs,
            o_vertical_sync => s_output_vs,
            o_data_enable => s_output_de,
            ou2_scanlines => su2_scanlines
        );
    stimulus : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_phase = 6) then
                sint_phase <= 0;
                if (sint_x = 431) then
                    sint_x <= 0;
                    if (sint_y = GINT_TOTAL_HEIGHT - 1) then
                        sint_y <= 0;
                        sint_frames <= sint_frames + 1;
                    else
                        sint_y <= sint_y + 1;
                    end if;
                else
                    sint_x <= sint_x + 1;
                end if;
            else
                sint_phase <= sint_phase + 1;
            end if;
        end if;
    end process;
    monitor : process
        variable vint_pixels : natural := 0;
        variable vint_lines : natural := 0;
        variable vint_line_pixels : natural := 0;
        variable vint_expected_width : natural := 288;
        variable vint_expected_pixels : natural := 288 * GINT_VISIBLE_HEIGHT;
        variable vint_expected_lines : natural := GINT_VISIBLE_HEIGHT;
        variable v_previous_de : std_logic := '0';
    begin
        wait until falling_edge(s_clk);
        if (GINT_MODE = 0 or GINT_MODE = 6) then
            assert (s_output_ce = s_ce and s_output_de = not (s_hb or s_vb) and
                s_output_hs = not s_hs and s_output_vs = not s_vs and
                su8_output_red = su8_red and su8_output_green = su8_green and su8_output_blue = su8_blue)
                report "Native/direct video bypass changed input" severity failure;
            assert (su2_scanlines = 0) report "Native/direct video retained scanline effect" severity failure;
        end if;
        if (GINT_MODE >= 3 and GINT_MODE <= 5) then
            assert (su2_scanlines = GINT_MODE - 2)
                report "Incorrect scanline strength" severity failure;
        elsif (GINT_MODE /= 6) then
            assert (su2_scanlines = 0)
                report "Unexpected scanline strength" severity failure;
        end if;
        if (sint_frames >= 2 and sint_frames < 3 and s_output_ce = '1') then
            if (s_output_de = '1') then
                assert (su8_output_red = x"31" and su8_output_green = x"79" and su8_output_blue = x"C5")
                    report "Video mixer changed flat-field colour or emitted unknown pixels" severity failure;
                vint_pixels := vint_pixels + 1;
                vint_line_pixels := vint_line_pixels + 1;
            elsif (v_previous_de = '1') then
                if (GINT_MODE = 2) then
                    vint_expected_width := 576;
                end if;
                assert (vint_line_pixels = vint_expected_width)
                    report "Incorrect output line width " & integer'image(vint_line_pixels) severity failure;
                vint_lines := vint_lines + 1;
                vint_line_pixels := 0;
            end if;
            v_previous_de := s_output_de;
        end if;
        if (sint_frames = 3) then
            if (GINT_MODE = 2) then
                vint_expected_pixels := 1152 * GINT_VISIBLE_HEIGHT;
                vint_expected_lines := 2 * GINT_VISIBLE_HEIGHT;
            elsif (GINT_MODE >= 1 and GINT_MODE <= 5) then
                vint_expected_pixels := 576 * GINT_VISIBLE_HEIGHT;
                vint_expected_lines := 2 * GINT_VISIBLE_HEIGHT;
            end if;
            assert (vint_pixels = vint_expected_pixels and vint_lines = vint_expected_lines)
                report "Insufficient visible video output" severity failure;
            report "VIDEO_OPTIONS_PASS mode=" & integer'image(GINT_MODE) &
                " pixels=" & integer'image(vint_pixels) & " lines=" & integer'image(vint_lines);
            finish;
        end if;
    end process;
end architecture;
