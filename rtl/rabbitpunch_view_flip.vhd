-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Remap source coordinates at the existing random-access line-buffer boundary.
-- RGB is neither delayed nor stored. Orientation changes only between frames
-- while no transaction can still return coordinates in the old orientation.
entity rabbitpunch_view_flip is
    generic (
        GINT_SOURCE_X_OFFSET : natural := 8;
        GINT_SOURCE_Y_OFFSET : natural := 0;
        GINT_VISIBLE_WIDTH : positive := 288;
        GINT_VISIBLE_HEIGHT : positive := 216
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_ready : in std_logic;
        i_request_flip : in std_logic;
        i_frame_prepare : in std_logic;
        i_line_valid : in std_logic;
        i_line_ready : in std_logic;
        i_line_done : in std_logic;
        i_pixel_valid : in std_logic;
        i_pixel_ready : in std_logic;
        i_rgb_valid : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        ou9_source_line_y : out unsigned(8 downto 0);
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        ou9_source_pixel_x : out unsigned(8 downto 0);
        ou8_source_pixel_y : out unsigned(7 downto 0);
        iu9_source_rgb_x : in unsigned(8 downto 0);
        iu8_source_rgb_y : in unsigned(7 downto 0);
        ou9_rgb_x : out unsigned(8 downto 0);
        ou8_rgb_y : out unsigned(7 downto 0);
        o_applied_flip : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_view_flip is
    constant CU9_X_MIRROR_SUM : unsigned(8 downto 0) :=
        to_unsigned(GINT_SOURCE_X_OFFSET + GINT_SOURCE_X_OFFSET + GINT_VISIBLE_WIDTH - 1, 9);
    constant CU9_Y_MIRROR_SUM : unsigned(8 downto 0) :=
        to_unsigned(GINT_SOURCE_Y_OFFSET + GINT_SOURCE_Y_OFFSET + GINT_VISIBLE_HEIGHT - 1, 9);
    signal s_applied_flip : std_logic := '0';
    signal s_render_in_flight : std_logic := '0';
    signal s_pixel_in_flight : std_logic := '0';
begin
    assert (GINT_SOURCE_X_OFFSET + GINT_SOURCE_X_OFFSET + GINT_VISIBLE_WIDTH <= 512)
        report "Flip X mirror sum exceeds coordinate width" severity failure;
    assert (GINT_SOURCE_Y_OFFSET + GINT_SOURCE_Y_OFFSET + GINT_VISIBLE_HEIGHT <= 256)
        report "Flip Y mirror sum exceeds coordinate width" severity failure;

    o_applied_flip <= s_applied_flip;
    ou9_source_line_y <= CU9_Y_MIRROR_SUM - iu9_line_y when s_applied_flip = '1' else iu9_line_y;
    ou9_source_pixel_x <= CU9_X_MIRROR_SUM - iu9_pixel_x when s_applied_flip = '1' else iu9_pixel_x;
    ou8_source_pixel_y <= resize(CU9_Y_MIRROR_SUM, 8) - iu8_pixel_y when s_applied_flip = '1' else iu8_pixel_y;
    ou9_rgb_x <= CU9_X_MIRROR_SUM - iu9_source_rgb_x when s_applied_flip = '1' else iu9_source_rgb_x;
    ou8_rgb_y <= resize(CU9_Y_MIRROR_SUM, 8) - iu8_source_rgb_y when s_applied_flip = '1' else iu8_source_rgb_y;

    orientation : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                s_applied_flip <= '0';
                s_render_in_flight <= '0';
                s_pixel_in_flight <= '0';
            elsif (i_game_ready = '0') then
                s_applied_flip <= i_request_flip;
                s_render_in_flight <= '0';
                s_pixel_in_flight <= '0';
            else
                if (i_line_done = '1') then
                    s_render_in_flight <= '0';
                end if;
                if (i_line_valid = '1' and i_line_ready = '1') then
                    s_render_in_flight <= '1';
                end if;
                if (i_rgb_valid = '1') then
                    s_pixel_in_flight <= '0';
                end if;
                if (i_pixel_valid = '1' and i_pixel_ready = '1') then
                    s_pixel_in_flight <= '1';
                end if;
                if (i_frame_prepare = '1' and s_render_in_flight = '0' and
                    s_pixel_in_flight = '0' and i_line_valid = '0' and
                    i_pixel_valid = '0' and i_rgb_valid = '0') then
                    s_applied_flip <= i_request_flip;
                end if;
            end if;
        end if;
    end process;
end architecture;
