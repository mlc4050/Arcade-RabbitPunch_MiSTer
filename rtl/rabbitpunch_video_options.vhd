-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Native output is an exact bypass. Optional doubling uses the unchanged
-- MiSTer line-based mixer; every register still runs on i_clk with enables.
-- Native sync pulses are active low; the framework mixer expects active high.
entity rabbitpunch_video_options is
    generic (
        GINT_VISIBLE_WIDTH : positive := 288
    );
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
end entity;

architecture rtl of rabbitpunch_video_options is
    component video_mixer is
        generic (
            LINE_LENGTH : integer;
            HALF_DEPTH : integer;
            GAMMA : integer
        );
        port (
            CLK_VIDEO : in std_logic;
            CE_PIXEL : out std_logic;
            ce_pix : in std_logic;
            scandoubler : in std_logic;
            hq2x : in std_logic;
            gamma_bus : inout unsigned(21 downto 0);
            R : in unsigned(7 downto 0);
            G : in unsigned(7 downto 0);
            B : in unsigned(7 downto 0);
            HSync : in std_logic;
            VSync : in std_logic;
            HBlank : in std_logic;
            VBlank : in std_logic;
            HDMI_FREEZE : in std_logic;
            freeze_sync : out std_logic;
            VGA_R : out unsigned(7 downto 0);
            VGA_G : out unsigned(7 downto 0);
            VGA_B : out unsigned(7 downto 0);
            VGA_VS : out std_logic;
            VGA_HS : out std_logic;
            VGA_DE : out std_logic
        );
    end component;
    signal s_double, s_hq, s_pixel_enable, s_horizontal_sync, s_vertical_sync, s_data_enable : std_logic;
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal su3_effect : unsigned(2 downto 0);
    signal su22_gamma : unsigned(21 downto 0);
begin
    su3_effect <= iu3_effect when i_direct_video = '0' and iu3_effect <= 4 else (others => '0');
    s_double <= '1' when i_direct_video = '0' and (i_forced_scandoubler = '1' or su3_effect /= 0) else '0';
    s_hq <= '1' when su3_effect = 1 else '0';
    -- Bit 21 is driven by the mixer to advertise disabled gamma support.
    su22_gamma(20 downto 0) <= (others => '0');
    ou2_scanlines <= resize(su3_effect - 1, 2) when su3_effect >= 2 else (others => '0');
    o_pixel_enable <= s_pixel_enable when s_double = '1' else i_pixel_enable;
    ou8_red <= su8_red when s_double = '1' else iu8_red;
    ou8_green <= su8_green when s_double = '1' else iu8_green;
    ou8_blue <= su8_blue when s_double = '1' else iu8_blue;
    o_horizontal_sync <= s_horizontal_sync when s_double = '1' else not i_horizontal_sync;
    o_vertical_sync <= s_vertical_sync when s_double = '1' else not i_vertical_sync;
    o_data_enable <= s_data_enable when s_double = '1' else not (i_horizontal_blank or i_vertical_blank);

    framework_video : video_mixer
        generic map (
            LINE_LENGTH => GINT_VISIBLE_WIDTH + 4,
            HALF_DEPTH => 0,
            GAMMA => 0
        )
        port map (
            CLK_VIDEO => i_clk,
            CE_PIXEL => s_pixel_enable,
            ce_pix => i_pixel_enable,
            scandoubler => s_double,
            hq2x => s_hq,
            gamma_bus => su22_gamma,
            R => iu8_red,
            G => iu8_green,
            B => iu8_blue,
            HSync => not i_horizontal_sync,
            VSync => not i_vertical_sync,
            HBlank => i_horizontal_blank,
            VBlank => i_vertical_blank,
            HDMI_FREEZE => '0',
            freeze_sync => open,
            VGA_R => su8_red,
            VGA_G => su8_green,
            VGA_B => su8_blue,
            VGA_VS => s_vertical_sync,
            VGA_HS => s_horizontal_sync,
            VGA_DE => s_data_enable
        );
end architecture;
