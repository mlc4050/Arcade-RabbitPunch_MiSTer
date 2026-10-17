-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Provisional geometry is adjustable; it is not a decoded C7-01 model.
-- All outputs describe the pixel consumed on an enabled rising i_clk edge.
entity rabbitpunch_raster is
    generic (
        sint_HORIZONTAL_TOTAL : positive := 432;
        sint_HORIZONTAL_VISIBLE_START : natural := 0;
        sint_HORIZONTAL_VISIBLE_WIDTH : positive := 288;
        sint_HORIZONTAL_SYNC_START : natural := 352;
        sint_HORIZONTAL_SYNC_END : positive := 392;
        sint_VERTICAL_TOTAL : positive := 256;
        sint_VERTICAL_VISIBLE_START : natural := 0;
        sint_VERTICAL_VISIBLE_HEIGHT : positive := 216;
        sint_VERTICAL_SYNC_START : natural := 232;
        sint_VERTICAL_SYNC_END : positive := 240;
        sint_HALF_FRAME_OFFSET : natural := sint_VERTICAL_TOTAL / 2;
        sint_RENDER_X_OFFSET : natural := 8;
        sint_RENDER_Y_OFFSET : natural := 0;
        s_HORIZONTAL_SYNC_ACTIVE : std_logic := '0';
        s_VERTICAL_SYNC_ACTIVE : std_logic := '0'
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_pixel_enable : in std_logic;
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
        o_half_frame : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_raster is
    constant C_VBLANK_LINE : natural :=
        (sint_VERTICAL_VISIBLE_START + sint_VERTICAL_VISIBLE_HEIGHT) mod sint_VERTICAL_TOTAL;
    constant C_HALF_FRAME_LINE : natural :=
        (C_VBLANK_LINE + sint_HALF_FRAME_OFFSET) mod sint_VERTICAL_TOTAL;
    signal su9_horizontal_position, su9_vertical_position : unsigned(8 downto 0) := (others => '0');
    signal s_horizontal_active, s_vertical_active, s_line_start : std_logic;
begin
    assert (sint_HORIZONTAL_TOTAL <= 512 and sint_VERTICAL_TOTAL <= 512)
        report "Raster total exceeds the beam counter width" severity failure;
    assert (sint_HORIZONTAL_VISIBLE_START + sint_HORIZONTAL_VISIBLE_WIDTH <= sint_HORIZONTAL_TOTAL and
        sint_VERTICAL_VISIBLE_START + sint_VERTICAL_VISIBLE_HEIGHT <= sint_VERTICAL_TOTAL)
        report "Raster visible window exceeds total" severity failure;
    assert (sint_HORIZONTAL_SYNC_START < sint_HORIZONTAL_SYNC_END and sint_HORIZONTAL_SYNC_END <= sint_HORIZONTAL_TOTAL and
        sint_VERTICAL_SYNC_START < sint_VERTICAL_SYNC_END and sint_VERTICAL_SYNC_END <= sint_VERTICAL_TOTAL)
        report "Invalid raster sync window" severity failure;
    assert (sint_RENDER_X_OFFSET + sint_HORIZONTAL_VISIBLE_WIDTH <= 512 and
        sint_RENDER_Y_OFFSET + sint_VERTICAL_VISIBLE_HEIGHT <= 256 and sint_HALF_FRAME_OFFSET < sint_VERTICAL_TOTAL)
        report "Raster render coordinates or half-frame offset exceed range" severity failure;

    ou9_horizontal_position <= su9_horizontal_position;
    ou9_vertical_position <= su9_vertical_position;
    s_horizontal_active <= '1' when su9_horizontal_position >= sint_HORIZONTAL_VISIBLE_START and
        su9_horizontal_position < sint_HORIZONTAL_VISIBLE_START + sint_HORIZONTAL_VISIBLE_WIDTH else '0';
    s_vertical_active <= '1' when su9_vertical_position >= sint_VERTICAL_VISIBLE_START and
        su9_vertical_position < sint_VERTICAL_VISIBLE_START + sint_VERTICAL_VISIBLE_HEIGHT else '0';
    o_active <= s_horizontal_active and s_vertical_active and not i_reset;
    o_hblank <= not s_horizontal_active or i_reset;
    o_vblank <= not s_vertical_active or i_reset;
    o_hsync <= s_HORIZONTAL_SYNC_ACTIVE when i_reset = '0' and su9_horizontal_position >= sint_HORIZONTAL_SYNC_START and
        su9_horizontal_position < sint_HORIZONTAL_SYNC_END else not s_HORIZONTAL_SYNC_ACTIVE;
    o_vsync <= s_VERTICAL_SYNC_ACTIVE when i_reset = '0' and su9_vertical_position >= sint_VERTICAL_SYNC_START and
        su9_vertical_position < sint_VERTICAL_SYNC_END else not s_VERTICAL_SYNC_ACTIVE;
    ou9_pixel_x <= su9_horizontal_position - sint_HORIZONTAL_VISIBLE_START + sint_RENDER_X_OFFSET
        when s_horizontal_active = '1' else (others => '0');
    ou8_pixel_y <= resize(su9_vertical_position - sint_VERTICAL_VISIBLE_START + sint_RENDER_Y_OFFSET, 8)
        when s_vertical_active = '1' else (others => '0');
    s_line_start <= i_pixel_enable and not i_reset when su9_horizontal_position = 0 else '0';
    o_line_start <= s_line_start;
    o_visible_line_start <= s_line_start and s_vertical_active;
    o_frame_start <= s_line_start when su9_vertical_position = 0 else '0';
    o_vblank_start <= s_line_start when su9_vertical_position = C_VBLANK_LINE and
        sint_VERTICAL_VISIBLE_HEIGHT < sint_VERTICAL_TOTAL else '0';
    o_half_frame <= s_line_start when su9_vertical_position = C_HALF_FRAME_LINE else '0';

    beam : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_reset = '1') then
                su9_horizontal_position <= (others => '0');
                su9_vertical_position <= (others => '0');
            elsif (i_pixel_enable = '1') then
                if (su9_horizontal_position = sint_HORIZONTAL_TOTAL - 1) then
                    su9_horizontal_position <= (others => '0');
                    if (su9_vertical_position = sint_VERTICAL_TOTAL - 1) then
                        su9_vertical_position <= (others => '0');
                    else
                        su9_vertical_position <= su9_vertical_position + 1;
                    end if;
                else
                    su9_horizontal_position <= su9_horizontal_position + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
