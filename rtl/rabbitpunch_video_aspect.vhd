-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Metadata only: the native RGB/sync/data-enable stream has no added storage.
-- The unchanged framework measures output geometry and selects integer sizes.
entity rabbitpunch_video_aspect is
    port (
        i_clk : in std_logic;
        i_pixel_enable : in std_logic;
        i_vertical_sync : in std_logic;
        i_data_enable : in std_logic;
        i_direct_video : in std_logic;
        iu12_hdmi_width : in unsigned(11 downto 0);
        iu12_hdmi_height : in unsigned(11 downto 0);
        iu2_aspect : in unsigned(1 downto 0);
        iu3_scale : in unsigned(2 downto 0);
        ou13_aspect_x : out unsigned(12 downto 0);
        ou13_aspect_y : out unsigned(12 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_video_aspect is
    component video_freak is
        port (
            CLK_VIDEO : in std_logic;
            CE_PIXEL : in std_logic;
            VGA_VS : in std_logic;
            HDMI_WIDTH : in unsigned(11 downto 0);
            HDMI_HEIGHT : in unsigned(11 downto 0);
            VGA_DE : out std_logic;
            VIDEO_ARX : out unsigned(12 downto 0);
            VIDEO_ARY : out unsigned(12 downto 0);
            VGA_DE_IN : in std_logic;
            ARX : in unsigned(11 downto 0);
            ARY : in unsigned(11 downto 0);
            CROP_SIZE : in unsigned(11 downto 0);
            CROP_OFF : in unsigned(4 downto 0);
            SCALE : in unsigned(2 downto 0)
        );
    end component;
    signal su12_aspect_x, su12_aspect_y : unsigned(11 downto 0);
    signal su3_scale : unsigned(2 downto 0);
    signal su13_scaled_x, su13_scaled_y : unsigned(12 downto 0);
    signal su2_completed_frames : unsigned(1 downto 0) := (others => '0');
    signal s_previous_vertical_sync : std_logic := '0';
begin
    su12_aspect_x <= to_unsigned(4, 12) when i_direct_video = '1' or iu2_aspect = 0 else
        resize(iu2_aspect - 1, 12);
    su12_aspect_y <= to_unsigned(3, 12) when i_direct_video = '1' or iu2_aspect = 0 else (others => '0');
    su3_scale <= iu3_scale when i_direct_video = '0' and iu3_scale <= 4 and su2_completed_frames >= 2 else (others => '0');
    -- Default/custom ratio selectors are valid immediately, including before
    -- the framework has measured a frame. Integer sizes need measured geometry.
    ou13_aspect_x <= resize(su12_aspect_x, 13) when su3_scale = 0 else su13_scaled_x;
    ou13_aspect_y <= resize(su12_aspect_y, 13) when su3_scale = 0 else su13_scaled_y;
    geometry_startup : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_pixel_enable = '1') then
                s_previous_vertical_sync <= i_vertical_sync;
                if (i_vertical_sync = '1' and s_previous_vertical_sync = '0' and su2_completed_frames < 3) then
                    su2_completed_frames <= su2_completed_frames + 1;
                end if;
            end if;
        end if;
    end process;
    framework_aspect : video_freak
        port map (
            CLK_VIDEO => i_clk,
            CE_PIXEL => i_pixel_enable,
            VGA_VS => i_vertical_sync,
            HDMI_WIDTH => iu12_hdmi_width,
            HDMI_HEIGHT => iu12_hdmi_height,
            VGA_DE => open,
            VIDEO_ARX => su13_scaled_x,
            VIDEO_ARY => su13_scaled_y,
            VGA_DE_IN => i_data_enable,
            ARX => su12_aspect_x,
            ARY => su12_aspect_y,
            CROP_SIZE => (others => '0'),
            CROP_OFF => (others => '0'),
            SCALE => su3_scale
        );
end architecture;
