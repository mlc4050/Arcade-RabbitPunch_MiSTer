-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity raster_check is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        ou9_horizontal_position : out unsigned(8 downto 0);
        ou9_vertical_position : out unsigned(8 downto 0);
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        o_active : out std_logic;
        o_hsync : out std_logic;
        o_vsync : out std_logic;
        o_hblank : out std_logic;
        o_vblank : out std_logic;
        o_line_start : out std_logic;
        o_visible_line_start : out std_logic;
        o_frame_start : out std_logic;
        o_vblank_start : out std_logic;
        o_half_frame : out std_logic;
        o_pixel_enable : out std_logic;
        o_main_phase_enable : out std_logic;
        o_sound_cpu_enable : out std_logic;
        o_ym_enable : out std_logic;
        o_ym_half_enable : out std_logic;
        o_adpcm_enable : out std_logic
    );
end entity;

-- Same-clock evaluation-only launch/capture registers on every client port.
architecture evaluation of raster_check is
    signal s_boundary_i_reset : std_logic := '0';
    signal su9_boundary_ou9_horizontal_position : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_vertical_position : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su8_boundary_ou8_pixel_y : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_active : std_logic := '0';
    signal s_boundary_o_hsync : std_logic := '0';
    signal s_boundary_o_vsync : std_logic := '0';
    signal s_boundary_o_hblank : std_logic := '0';
    signal s_boundary_o_vblank : std_logic := '0';
    signal s_boundary_o_line_start : std_logic := '0';
    signal s_boundary_o_visible_line_start : std_logic := '0';
    signal s_boundary_o_frame_start : std_logic := '0';
    signal s_boundary_o_vblank_start : std_logic := '0';
    signal s_boundary_o_half_frame : std_logic := '0';
    signal s_boundary_o_pixel_enable : std_logic := '0';
    signal s_boundary_o_main_phase_enable : std_logic := '0';
    signal s_boundary_o_sound_cpu_enable : std_logic := '0';
    signal s_boundary_o_ym_enable : std_logic := '0';
    signal s_boundary_o_ym_half_enable : std_logic := '0';
    signal s_boundary_o_adpcm_enable : std_logic := '0';
begin
    boundary : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_reset <= i_reset;
            ou9_horizontal_position <= su9_boundary_ou9_horizontal_position;
            ou9_vertical_position <= su9_boundary_ou9_vertical_position;
            ou9_pixel_x <= su9_boundary_ou9_pixel_x;
            ou8_pixel_y <= su8_boundary_ou8_pixel_y;
            o_active <= s_boundary_o_active;
            o_hsync <= s_boundary_o_hsync;
            o_vsync <= s_boundary_o_vsync;
            o_hblank <= s_boundary_o_hblank;
            o_vblank <= s_boundary_o_vblank;
            o_line_start <= s_boundary_o_line_start;
            o_visible_line_start <= s_boundary_o_visible_line_start;
            o_frame_start <= s_boundary_o_frame_start;
            o_vblank_start <= s_boundary_o_vblank_start;
            o_half_frame <= s_boundary_o_half_frame;
            o_pixel_enable <= s_boundary_o_pixel_enable;
            o_main_phase_enable <= s_boundary_o_main_phase_enable;
            o_sound_cpu_enable <= s_boundary_o_sound_cpu_enable;
            o_ym_enable <= s_boundary_o_ym_enable;
            o_ym_half_enable <= s_boundary_o_ym_half_enable;
            o_adpcm_enable <= s_boundary_o_adpcm_enable;
        end if;
    end process;
    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => i_clk,
            i_reset => s_boundary_i_reset,
            o_pixel_enable => s_boundary_o_pixel_enable,
            o_main_phase_enable => s_boundary_o_main_phase_enable,
            o_sound_cpu_enable => s_boundary_o_sound_cpu_enable,
            o_ym_enable => s_boundary_o_ym_enable,
            o_ym_half_enable => s_boundary_o_ym_half_enable,
            o_adpcm_enable => s_boundary_o_adpcm_enable
        );
    raster : entity work.rabbitpunch_raster
        port map (
            i_pixel_enable => s_boundary_o_pixel_enable,
            i_clk => i_clk,
            i_reset => s_boundary_i_reset,
            ou9_horizontal_position => su9_boundary_ou9_horizontal_position,
            ou9_vertical_position => su9_boundary_ou9_vertical_position,
            ou9_pixel_x => su9_boundary_ou9_pixel_x,
            ou8_pixel_y => su8_boundary_ou8_pixel_y,
            o_active => s_boundary_o_active,
            o_hsync => s_boundary_o_hsync,
            o_vsync => s_boundary_o_vsync,
            o_hblank => s_boundary_o_hblank,
            o_vblank => s_boundary_o_vblank,
            o_line_start => s_boundary_o_line_start,
            o_visible_line_start => s_boundary_o_visible_line_start,
            o_frame_start => s_boundary_o_frame_start,
            o_vblank_start => s_boundary_o_vblank_start,
            o_half_frame => s_boundary_o_half_frame
        );
end architecture;
