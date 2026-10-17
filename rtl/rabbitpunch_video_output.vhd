-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Align raster metadata with the native fixed-latency RGB pipeline. This
-- generates no timing and stores no pixel row/frame. Missing pixels go black;
-- o_underflow stays set until reset instead of stalling the physical raster.
entity rabbitpunch_video_output is
    generic (
        sint_RGB_LATENCY : positive := 4
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_pixel_enable : in std_logic;
        i_active : in std_logic;
        i_hsync : in std_logic;
        i_vsync : in std_logic;
        i_hblank : in std_logic;
        i_vblank : in std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        o_pixel_request : out std_logic;
        i_pixel_ready : in std_logic;
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
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        o_underflow : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_video_output is
    type t_metadata is array (natural range <>) of unsigned(6 downto 0);
    type t_x_coordinates is array (natural range <>) of unsigned(8 downto 0);
    type t_y_coordinates is array (natural range <>) of unsigned(7 downto 0);
    -- Bit 0 enable, 1 active, 2/3 sync, 4/5 blank, 6 accepted request.
    signal su7_metadata : t_metadata(0 to sint_RGB_LATENCY) := (others => (others => '0'));
    signal su9_x : t_x_coordinates(0 to sint_RGB_LATENCY) := (others => (others => '0'));
    signal su8_y : t_y_coordinates(0 to sint_RGB_LATENCY) := (others => (others => '0'));
    signal s_request, s_underflow : std_logic := '0';
begin
    s_request <= i_pixel_enable and i_active and not i_reset;
    o_pixel_request <= s_request;
    o_underflow <= s_underflow;
    process(i_clk)
        variable v_expected : boolean;
    begin
        if (rising_edge(i_clk)) then
            o_pixel_enable <= '0';
            su7_metadata(0) <= (s_request and i_pixel_ready) & i_vblank & i_hblank & i_vsync & i_hsync & i_active & i_pixel_enable;
            su9_x(0) <= iu9_pixel_x;
            su8_y(0) <= iu8_pixel_y;
            for vint_stage in 1 to sint_RGB_LATENCY loop
                su7_metadata(vint_stage) <= su7_metadata(vint_stage - 1);
                su9_x(vint_stage) <= su9_x(vint_stage - 1);
                su8_y(vint_stage) <= su8_y(vint_stage - 1);
            end loop;
            v_expected := su7_metadata(sint_RGB_LATENCY)(1 downto 0) = "11";
            if (i_rgb_error = '1' or (i_rgb_valid = '1' and not v_expected)) then
                s_underflow <= '1';
            end if;
            if (su7_metadata(sint_RGB_LATENCY)(0) = '1') then
                o_pixel_enable <= '1';
                o_active <= su7_metadata(sint_RGB_LATENCY)(1);
                o_hsync <= su7_metadata(sint_RGB_LATENCY)(2);
                o_vsync <= su7_metadata(sint_RGB_LATENCY)(3);
                o_hblank <= su7_metadata(sint_RGB_LATENCY)(4);
                o_vblank <= su7_metadata(sint_RGB_LATENCY)(5);
                ou9_pixel_x <= su9_x(sint_RGB_LATENCY);
                ou8_pixel_y <= su8_y(sint_RGB_LATENCY);
                ou8_red <= (others => '0');
                ou8_green <= (others => '0');
                ou8_blue <= (others => '0');
                if (v_expected) then
                    if (su7_metadata(sint_RGB_LATENCY)(6) = '1' and i_rgb_valid = '1' and i_rgb_error = '0' and
                        iu9_rgb_x = su9_x(sint_RGB_LATENCY) and iu8_rgb_y = su8_y(sint_RGB_LATENCY)) then
                        ou8_red <= iu8_red;
                        ou8_green <= iu8_green;
                        ou8_blue <= iu8_blue;
                    else
                        s_underflow <= '1';
                    end if;
                end if;
            end if;
            if (i_reset = '1') then
                su7_metadata <= (others => (others => '0'));
                o_pixel_enable <= '0';
                o_active <= '0';
                o_hsync <= '0';
                o_vsync <= '0';
                o_hblank <= '1';
                o_vblank <= '1';
                ou9_pixel_x <= (others => '0');
                ou8_pixel_y <= (others => '0');
                ou8_red <= (others => '0');
                ou8_green <= (others => '0');
                ou8_blue <= (others => '0');
                s_underflow <= '0';
            end if;
        end if;
    end process;
end architecture;
