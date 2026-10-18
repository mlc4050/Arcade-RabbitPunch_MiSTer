-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity hdmi_presentation_control_tb is
    generic (
        GINT_FRAME_PIXELS : positive := 640;
        GBOOL_SMOKE_ONLY : boolean := false
    );
end entity;

architecture test of hdmi_presentation_control_tb is

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
    signal s_initialize : std_logic := '1';
    signal s_loader : std_logic := '0';
    signal s_framebuffer_enable, s_force_blank, s_rotated, s_queue_empty, s_overflow, s_ddr_write : std_logic;
    signal su2_rotation_request : unsigned(1 downto 0) := (others => '0');
    signal su2_applied : unsigned(1 downto 0);
    signal su13_reference_x, su13_reference_y : unsigned(12 downto 0);
begin
    s_initialize <= '0' after 30 ns;
    assert (s_overflow /= '1') report "Presentation control fixture overflowed" severity failure;
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when sint_phase = 6 else '0';
    s_vertical_sync <= '1' when sint_y >= 24 and sint_y < 26 else '0';
    s_data_enable <= '1' when sint_x < 32 and sint_y < 20 else '0';
    dut : entity work.rabbitpunch_hdmi_presentation
        generic map (
            GINT_FRAME_PIXELS => GINT_FRAME_PIXELS
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_ready => '1',
            i_loader_active => s_loader,
            i_direct_video => s_direct,
            iu2_rotation => su2_rotation_request,
            i_native_pixel_enable => s_enable,
            iu8_native_red => to_unsigned(0, 8),
            iu8_native_green => to_unsigned(0, 8),
            iu8_native_blue => to_unsigned(0, 8),
            i_native_horizontal_sync_n => '1',
            i_native_vertical_sync_n => not s_vertical_sync,
            i_native_data_enable => s_data_enable,
            i_presented_pixel_enable => s_enable,
            i_presented_vertical_sync => s_vertical_sync,
            i_presented_data_enable => s_data_enable,
            iu12_hdmi_width => su12_hdmi_width,
            iu12_hdmi_height => su12_hdmi_height,
            iu2_aspect => su2_aspect,
            iu3_scale => su3_scale,
            ou13_aspect_x => su13_aspect_x,
            ou13_aspect_y => su13_aspect_y,
            i_framebuffer_vertical_blank => s_vertical_sync,
            o_framebuffer_enable => s_framebuffer_enable,
            o_framebuffer_force_blank => s_force_blank,
            ou5_framebuffer_format => open,
            ou12_framebuffer_width => open,
            ou12_framebuffer_height => open,
            ou32_framebuffer_base => open,
            ou14_framebuffer_stride => open,
            o_rotation_active => s_rotated,
            ou2_applied_rotation => su2_applied,
            o_discard_frame => open,
            o_queue_overflow => s_overflow,
            o_queue_empty => s_queue_empty,
            iu8_loader_burst_count => to_unsigned(1, 8),
            iu29_loader_word_address => to_unsigned(0, 29),
            iu64_loader_write_data => to_unsigned(0, 64),
            iu8_loader_byte_enables => to_unsigned(0, 8),
            i_loader_read => '0',
            i_loader_write => '0',
            o_loader_busy => open,
            o_loader_read_valid => open,
            ou64_loader_read_data => open,
            i_ddr_busy => '0',
            i_ddr_read_valid => '0',
            iu64_ddr_read_data => to_unsigned(0, 64),
            ou8_ddr_burst_count => open,
            ou29_ddr_word_address => open,
            ou64_ddr_write_data => open,
            ou8_ddr_byte_enables => open,
            o_ddr_read => open,
            o_ddr_write => s_ddr_write
        );
    integer_reference : entity work.rabbitpunch_video_aspect
        port map (
            i_clk => s_clk,
            i_pixel_enable => s_enable,
            i_vertical_sync => s_vertical_sync,
            i_data_enable => s_data_enable,
            i_direct_video => '0',
            iu12_hdmi_width => su12_hdmi_height,
            iu12_hdmi_height => su12_hdmi_width,
            iu2_aspect => su2_aspect,
            iu3_scale => su3_scale,
            ou13_aspect_x => su13_reference_x,
            ou13_aspect_y => su13_reference_y
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
            report "HDMI_PRESENTATION_SMOKE_PASS";
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
        -- Mode requests made at the start of active video wait for VS.
        su12_hdmi_width <= to_unsigned(1920, 12);
        su12_hdmi_height <= to_unsigned(1050, 12);
        su2_aspect <= (others => '0');
        su3_scale <= (others => '0');
        wait until sint_y = 0 and sint_x = 0;
        su2_rotation_request <= to_unsigned(1, 2);
        cycles(32);
        assert (su2_applied = 0) report "Rotation mode changed during active video" severity failure;
        wait until s_vertical_sync = '1';
        cycles(4);
        assert (su2_applied = 1 and s_rotated = '1' and s_force_blank = '1')
            report "CW mode did not latch/blank at VS" severity failure;
        expect_size(3, 4);
        for vint_selection in 1 to 3 loop
            su2_aspect <= to_unsigned(vint_selection, 2);
            cycles(32);
            expect_size(vint_selection - 1, 0);
        end loop;
        su2_aspect <= (others => '0');
        for vint_mode in 1 to 4 loop
            su3_scale <= to_unsigned(vint_mode, 3);
            cycles(3000);
            assert (su13_aspect_x = su13_reference_y and su13_aspect_y = su13_reference_x and
                su13_aspect_x(12) = '1' and su13_aspect_y(12) = '1' and
                su13_aspect_x(11 downto 0) <= su12_hdmi_width and
                su13_aspect_y(11 downto 0) <= su12_hdmi_height)
                report "Rotated integer metadata does not fit transposed HDMI rectangle" severity failure;
        end loop;
        su3_scale <= (others => '0');
        wait until sint_y = 0 and sint_x = 0;
        su2_rotation_request <= to_unsigned(2, 2);
        cycles(32);
        assert (su2_applied = 1) report "Direction changed during active video" severity failure;
        wait until s_vertical_sync = '1';
        cycles(4);
        assert (su2_applied = 2 and s_framebuffer_enable = '1' and s_force_blank = '1') report "CCW change retained an old valid image" severity failure;
        s_loader <= '1';
        su2_rotation_request <= (others => '0');
        for vint_frame in 0 to 1 loop
            wait until s_vertical_sync = '1';
            cycles(4);
            assert (su2_applied = 2 and s_force_blank = '1' and s_queue_empty = '1' and s_ddr_write = '0')
                report "Loader did not hold presentation mode/blank/queue ownership" severity failure;
        end loop;
        s_loader <= '0';
        wait until s_vertical_sync = '1';
        cycles(4);
        assert (su2_applied = 0 and s_rotated = '0' and s_framebuffer_enable = '0' and s_force_blank = '0')
            report "None mode did not release the native path" severity failure;
        expect_size(4, 3);
        su2_rotation_request <= to_unsigned(1, 2);
        wait until s_vertical_sync = '1';
        cycles(4);
        s_direct <= '1';
        su2_aspect <= to_unsigned(3, 2);
        cycles(4);
        assert (s_rotated = '0' and s_framebuffer_enable = '0' and s_force_blank = '0' and s_ddr_write = '0')
            report "Direct video retained HDMI framebuffer state" severity failure;
        expect_size(4, 3);
        s_direct <= '0';
        su2_rotation_request <= to_unsigned(3, 2);
        wait until s_vertical_sync = '1';
        cycles(4);
        assert (su2_applied = 0 and s_rotated = '0') report "Reserved rotation encoding was enabled" severity failure;
        report "HDMI_PRESENTATION_CONTROL_PASS native_integer=4 rotated_integer=4 custom_selectors=checked midframe_latch=checked direction_flush=checked loader_hold=checked direct=checked reserved=checked";
        finish;
    end process;
end architecture;
