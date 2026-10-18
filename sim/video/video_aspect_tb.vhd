-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity video_aspect_tb is
    generic (
        GBOOL_SMOKE_ONLY : boolean := false
    );
end entity;

architecture test of video_aspect_tb is
    component rabbitpunch_video_aspect is
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
    end component;
    signal s_clk : std_logic := '0';
    signal sint_phase : natural range 0 to 6 := 0;
    signal sint_x : natural range 0 to 47 := 0;
    signal sint_y : natural range 0 to 27 := 0;
    signal sint_frames : natural := 0;
    signal s_enable, s_vertical_sync, s_data_enable : std_logic;
    signal s_direct : std_logic := '0';
    signal su2_aspect : unsigned(1 downto 0) := (others => '0');
    signal su3_scale : unsigned(2 downto 0) := to_unsigned(4, 3);
    signal su12_hdmi_width : unsigned(11 downto 0) := to_unsigned(1920, 12);
    signal su12_hdmi_height : unsigned(11 downto 0) := to_unsigned(1050, 12);
    signal su13_aspect_x, su13_aspect_y : unsigned(12 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when sint_phase = 6 else '0';
    s_vertical_sync <= '1' when sint_y >= 24 and sint_y < 26 else '0';
    s_data_enable <= '1' when sint_x < 32 and sint_y < 20 else '0';
    dut : rabbitpunch_video_aspect
        port map (
            i_clk => s_clk,
            i_pixel_enable => s_enable,
            i_vertical_sync => s_vertical_sync,
            i_data_enable => s_data_enable,
            i_direct_video => s_direct,
            iu12_hdmi_width => su12_hdmi_width,
            iu12_hdmi_height => su12_hdmi_height,
            iu2_aspect => su2_aspect,
            iu3_scale => su3_scale,
            ou13_aspect_x => su13_aspect_x,
            ou13_aspect_y => su13_aspect_y
        );
    raster : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_phase = 6) then
                sint_phase <= 0;
                if (sint_x = 47) then
                    sint_x <= 0;
                    if (sint_y = 27) then
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
    stimulus : process
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure expect_size(vint_width, vint_height : natural) is
        begin
            assert (su13_aspect_x = vint_width and su13_aspect_y = vint_height)
                report "Aspect metadata mismatch: " & integer'image(to_integer(su13_aspect_x)) &
                    "," & integer'image(to_integer(su13_aspect_y)) severity failure;
        end procedure;
    begin
        if (GBOOL_SMOKE_ONLY) then
            cycles(32);
            expect_size(4, 3);
            report "VIDEO_ASPECT_SMOKE_PASS";
            finish;
        end if;
        wait until sint_frames = 3;
        su3_scale <= (others => '0');
        cycles(32);
        expect_size(4, 3);
        for vint_selection in 1 to 3 loop
            su2_aspect <= to_unsigned(vint_selection, 2);
            cycles(32);
            expect_size(vint_selection - 1, 0);
        end loop;
        su2_aspect <= (others => '0');
        -- 32x20 deliberately has non-square display pixels. At 1920x1050,
        -- vertical integer height is 1040 and ideal 4:3 width is 1386.
        -- The adjacent horizontal integer widths are 1376 and 1408.
        for vint_mode in 1 to 4 loop
            su3_scale <= to_unsigned(vint_mode, 3);
            cycles(3000);
            case vint_mode is
                when 1 =>
                    expect_size(4096 + 1386, 4096 + 1040);
                when 3 =>
                    expect_size(4096 + 1408, 4096 + 1040);
                when others =>
                    expect_size(4096 + 1376, 4096 + 1040);
            end case;
        end loop;
        su12_hdmi_width <= to_unsigned(1280, 12);
        su12_hdmi_height <= to_unsigned(720, 12);
        cycles(3000);
        expect_size(4096 + 960, 4096 + 720);
        su2_aspect <= to_unsigned(3, 2);
        s_direct <= '1';
        cycles(32);
        expect_size(4, 3);
        s_direct <= '0';
        su2_aspect <= (others => '0');
        su3_scale <= to_unsigned(7, 3);
        cycles(32);
        expect_size(4, 3);
        report "VIDEO_ASPECT_PASS original_full_custom=checked integer_modes=4 distinct_widths=checked hdmi_resize=checked direct_override=checked invalid_scale=checked";
        finish;
    end process;
end architecture;
