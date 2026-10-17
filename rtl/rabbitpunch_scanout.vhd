-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Provisional continuous raster plus one-row-ahead rendering and fixed-latency
-- RGB output. Game reset/loading blank RGB without stopping clocks or sync.
entity rabbitpunch_scanout is
    generic (
        sint_HORIZONTAL_TOTAL : positive := 432;
        sint_VISIBLE_WIDTH : positive := 288;
        sint_HORIZONTAL_SYNC_START : natural := 352;
        sint_HORIZONTAL_SYNC_END : positive := 392;
        sint_VERTICAL_TOTAL : positive := 256;
        sint_VISIBLE_LINES : positive := 216;
        sint_VERTICAL_SYNC_START : natural := 232;
        sint_VERTICAL_SYNC_END : positive := 240;
        sint_RENDER_X_OFFSET : natural := 8
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_ready : in std_logic;
        o_main_phase_enable : out std_logic;
        o_sound_cpu_enable : out std_logic;
        o_ym_enable : out std_logic;
        o_ym_half_enable : out std_logic;
        o_adpcm_enable : out std_logic;
        o_vblank_start : out std_logic;
        o_half_frame : out std_logic;
        o_line_valid : out std_logic;
        i_line_ready : in std_logic;
        o_render_bank : out std_logic;
        ou9_line_y : out unsigned(8 downto 0);
        i_line_done : in std_logic;
        o_pixel_valid : out std_logic;
        i_pixel_ready : in std_logic;
        o_pixel_bank : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        i_rgb_valid : in std_logic;
        i_rgb_error : in std_logic;
        iu9_rgb_x : in unsigned(8 downto 0);
        iu8_rgb_y : in unsigned(7 downto 0);
        iu8_red : in unsigned(7 downto 0);
        iu8_green : in unsigned(7 downto 0);
        iu8_blue : in unsigned(7 downto 0);
        o_pixel_enable : out std_logic;
        o_active : out std_logic;
        o_hsync : out std_logic;
        o_vsync : out std_logic;
        o_hblank : out std_logic;
        o_vblank : out std_logic;
        ou9_output_x : out unsigned(8 downto 0);
        ou8_output_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        ou9_horizontal_position : out unsigned(8 downto 0);
        ou9_vertical_position : out unsigned(8 downto 0);
        o_armed : out std_logic;
        o_underflow : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_scanout is
    signal s_pixel_enable, s_raster_active, s_hsync, s_vsync, s_hblank, s_vblank : std_logic;
    signal s_line_start, s_visible_line_start, s_frame_start, s_vblank_start, s_half_frame : std_logic;
    signal su9_horizontal, su9_vertical, su9_next_vertical, su9_x : unsigned(8 downto 0);
    signal su8_y : unsigned(7 downto 0);
    signal s_line_handoff, s_next_visible, s_display_bank, s_display_valid, s_armed : std_logic;
    signal s_video_initialize, s_line_underflow, s_rgb_underflow, s_pixel_request, s_active : std_logic;
begin
    s_video_initialize <= i_initialize or not i_game_ready;
    s_active <= s_raster_active and s_armed and i_game_ready;
    s_line_handoff <= s_pixel_enable when su9_horizontal = sint_HORIZONTAL_TOTAL - 1 else '0';
    su9_next_vertical <= (others => '0') when su9_vertical = sint_VERTICAL_TOTAL - 1 else su9_vertical + 1;
    s_next_visible <= '1' when su9_next_vertical < sint_VISIBLE_LINES else '0';
    o_vblank_start <= s_vblank_start and i_game_ready;
    o_half_frame <= s_half_frame and i_game_ready;
    o_pixel_valid <= s_pixel_request and s_display_valid;
    o_pixel_bank <= s_display_bank;
    ou9_pixel_x <= su9_x;
    ou8_pixel_y <= su8_y;
    ou9_horizontal_position <= su9_horizontal;
    ou9_vertical_position <= su9_vertical;
    o_armed <= s_armed;
    o_underflow <= (s_line_underflow or s_rgb_underflow) and i_game_ready;

    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => i_clk,
            i_reset => i_initialize,
            o_pixel_enable => s_pixel_enable,
            o_main_phase_enable => o_main_phase_enable,
            o_sound_cpu_enable => o_sound_cpu_enable,
            o_ym_enable => o_ym_enable,
            o_ym_half_enable => o_ym_half_enable,
            o_adpcm_enable => o_adpcm_enable
        );
    raster : entity work.rabbitpunch_raster
        generic map (
            sint_HORIZONTAL_TOTAL => sint_HORIZONTAL_TOTAL,
            sint_HORIZONTAL_VISIBLE_WIDTH => sint_VISIBLE_WIDTH,
            sint_HORIZONTAL_SYNC_START => sint_HORIZONTAL_SYNC_START,
            sint_HORIZONTAL_SYNC_END => sint_HORIZONTAL_SYNC_END,
            sint_VERTICAL_TOTAL => sint_VERTICAL_TOTAL,
            sint_VERTICAL_VISIBLE_HEIGHT => sint_VISIBLE_LINES,
            sint_VERTICAL_SYNC_START => sint_VERTICAL_SYNC_START,
            sint_VERTICAL_SYNC_END => sint_VERTICAL_SYNC_END,
            sint_RENDER_X_OFFSET => sint_RENDER_X_OFFSET
        )
        port map (
            i_clk => i_clk,
            i_reset => i_initialize,
            i_pixel_enable => s_pixel_enable,
            ou9_horizontal_position => su9_horizontal,
            ou9_vertical_position => su9_vertical,
            ou9_pixel_x => su9_x,
            ou8_pixel_y => su8_y,
            o_active => s_raster_active,
            o_hsync => s_hsync,
            o_vsync => s_vsync,
            o_hblank => s_hblank,
            o_vblank => s_vblank,
            o_line_start => s_line_start,
            o_visible_line_start => s_visible_line_start,
            o_frame_start => s_frame_start,
            o_vblank_start => s_vblank_start,
            o_half_frame => s_half_frame
        );
    scheduler : entity work.rabbitpunch_scanline_scheduler
        generic map (
            sint_VISIBLE_LINES => sint_VISIBLE_LINES
        )
        port map (
            i_clk => i_clk,
            i_initialize => s_video_initialize,
            i_frame_prepare => s_vblank_start,
            i_visible_line_start => s_visible_line_start,
            iu8_visible_line_y => su8_y,
            i_line_handoff => s_line_handoff,
            i_next_line_visible => s_next_visible,
            iu8_next_line_y => resize(su9_next_vertical, 8),
            o_render_valid => o_line_valid,
            i_render_ready => i_line_ready,
            o_render_bank => o_render_bank,
            ou9_render_y => ou9_line_y,
            i_render_done => i_line_done,
            o_display_bank => s_display_bank,
            o_display_valid => s_display_valid,
            o_armed => s_armed,
            o_underflow => s_line_underflow
        );
    output_alignment : entity work.rabbitpunch_video_output
        port map (
            i_clk => i_clk,
            i_reset => i_initialize,
            i_clear_underflow => not i_game_ready,
            i_pixel_enable => s_pixel_enable,
            i_active => s_active,
            i_hsync => s_hsync,
            i_vsync => s_vsync,
            i_hblank => s_hblank,
            i_vblank => s_vblank,
            iu9_pixel_x => su9_x,
            iu8_pixel_y => su8_y,
            o_pixel_request => s_pixel_request,
            i_pixel_ready => i_pixel_ready and s_display_valid,
            i_rgb_valid => i_rgb_valid,
            i_rgb_error => i_rgb_error,
            iu9_rgb_x => iu9_rgb_x,
            iu8_rgb_y => iu8_rgb_y,
            iu8_red => iu8_red,
            iu8_green => iu8_green,
            iu8_blue => iu8_blue,
            o_pixel_enable => o_pixel_enable,
            o_active => o_active,
            o_hsync => o_hsync,
            o_vsync => o_vsync,
            o_hblank => o_hblank,
            o_vblank => o_vblank,
            ou9_pixel_x => ou9_output_x,
            ou8_pixel_y => ou8_output_y,
            ou8_red => ou8_red,
            ou8_green => ou8_green,
            ou8_blue => ou8_blue,
            o_underflow => s_rgb_underflow
        );
end architecture;
