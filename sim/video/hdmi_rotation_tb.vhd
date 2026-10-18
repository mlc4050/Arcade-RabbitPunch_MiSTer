-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;

entity hdmi_rotation_tb is
    generic (
        GBOOL_COUNTERCLOCKWISE : boolean := false;
        GINT_VISIBLE_WIDTH : positive := 16;
        GINT_VISIBLE_HEIGHT : positive := 8;
        GINT_TOTAL_WIDTH : positive := 24;
        GINT_TOTAL_HEIGHT : positive := 12;
        GINT_HORIZONTAL_SYNC_START : natural := 20;
        GINT_HORIZONTAL_SYNC_END : positive := 22;
        GINT_VERTICAL_SYNC_START : natural := 9;
        GINT_VERTICAL_SYNC_END : positive := 11
    );
end entity;

architecture test of hdmi_rotation_tb is
    type t_seen is array(0 to GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT - 1) of boolean;
    constant CINT_STRIDE : positive := ((GINT_VISIBLE_HEIGHT + 3) / 4) * 16;
    signal s_clk : std_logic := '0';
    signal s_pixel_enable, s_horizontal_sync, s_vertical_sync, s_data_enable : std_logic;
    signal s_counterclockwise, s_enabled, s_write : std_logic;
    signal sint_phase : natural range 0 to 6 := 0;
    signal sint_x : natural range 0 to GINT_TOTAL_WIDTH - 1 := 0;
    signal sint_y : natural range 0 to GINT_TOTAL_HEIGHT - 1 := 0;
    signal sint_frames : natural := 0;
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal su5_format : unsigned(4 downto 0);
    signal su12_width, su12_height : unsigned(11 downto 0);
    signal su32_base : unsigned(31 downto 0);
    signal su14_stride : unsigned(13 downto 0);
    signal su8_burst_count, su8_byte_enables : unsigned(7 downto 0);
    signal su29_word_address : unsigned(28 downto 0);
    signal su64_data : unsigned(63 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    s_pixel_enable <= '1' when sint_phase = 6 else '0';
    s_horizontal_sync <= '1' when sint_x >= GINT_HORIZONTAL_SYNC_START and sint_x < GINT_HORIZONTAL_SYNC_END else '0';
    s_vertical_sync <= '1' when sint_y >= GINT_VERTICAL_SYNC_START and sint_y < GINT_VERTICAL_SYNC_END else '0';
    s_data_enable <= '1' when sint_x < GINT_VISIBLE_WIDTH and sint_y < GINT_VISIBLE_HEIGHT else '0';
    s_counterclockwise <= '1' when GBOOL_COUNTERCLOCKWISE else '0';
    su8_red <= to_unsigned(sint_x mod 256, 8);
    su8_green <= to_unsigned(sint_y, 8);
    su8_blue <= ((su8_red xor su8_green) and x"FE") or to_unsigned(sint_x / 256, 8);
    raster : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_phase = 6) then
                sint_phase <= 0;
                if (sint_x = GINT_TOTAL_WIDTH - 1) then
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
    dut : entity work.rabbitpunch_hdmi_rotation
        port map (
            i_clk => s_clk,
            i_pixel_enable => s_pixel_enable,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            i_horizontal_sync => s_horizontal_sync,
            i_vertical_sync => s_vertical_sync,
            i_data_enable => s_data_enable,
            i_enable => '1',
            i_counterclockwise => s_counterclockwise,
            i_framebuffer_vertical_blank => s_vertical_sync,
            i_framebuffer_low_latency => '0',
            o_enabled => s_enabled,
            ou5_format => su5_format,
            ou12_width => su12_width,
            ou12_height => su12_height,
            ou32_base => su32_base,
            ou14_stride => su14_stride,
            i_ddr_busy => '0',
            ou8_ddr_burst_count => su8_burst_count,
            ou29_ddr_word_address => su29_word_address,
            ou64_ddr_data => su64_data,
            ou8_ddr_byte_enables => su8_byte_enables,
            o_ddr_write => s_write
        );
    monitor : process
        variable v_seen : t_seen := (others => false);
        variable vint_pixels : natural := 0;
        variable vint_x, vint_y, vint_offset, vint_pixel : natural;
        variable vint_buffer : natural := 0;
        variable vu32_pixel : unsigned(31 downto 0);
    begin
        wait until falling_edge(s_clk);
        if (sint_frames = 3) then
            assert (s_enabled = '1' and su5_format = 6 and su12_width = GINT_VISIBLE_HEIGHT and
                su12_height = GINT_VISIBLE_WIDTH and su14_stride = CINT_STRIDE)
                report "Rotation framebuffer geometry mismatch" severity failure;
            assert (su32_base(31 downto 25) = 18 and su32_base(22 downto 0) = 0)
                report "Rotation framebuffer base outside reserved donor slots" severity failure;
            if (s_write = '1') then
                assert (su8_burst_count = 1 and su64_data(63 downto 32) = su64_data(31 downto 0))
                    report "Rotation DDR burst/data lanes mismatch" severity failure;
                vu32_pixel := su64_data(31 downto 0);
                vint_x := to_integer(vu32_pixel(7 downto 0)) + 256 * to_integer(vu32_pixel(16 downto 16));
                vint_y := to_integer(vu32_pixel(15 downto 8));
                assert (vint_x < GINT_VISIBLE_WIDTH and vint_y < GINT_VISIBLE_HEIGHT and vu32_pixel(31 downto 24) = 0 and
                    vu32_pixel(23 downto 16) = (((vu32_pixel(7 downto 0) xor vu32_pixel(15 downto 8)) and x"FE") or to_unsigned(vint_x / 256, 8)))
                    report "Rotation pixel colour/source coordinate mismatch" severity failure;
                vint_pixel := vint_y * GINT_VISIBLE_WIDTH + vint_x;
                assert (not v_seen(vint_pixel)) report "Rotation duplicated source pixel" severity failure;
                v_seen(vint_pixel) := true;
                if (GBOOL_COUNTERCLOCKWISE) then
                    vint_offset := (GINT_VISIBLE_WIDTH - 1 - vint_x) * CINT_STRIDE + vint_y * 4;
                else
                    vint_offset := vint_x * CINT_STRIDE + (GINT_VISIBLE_HEIGHT - 1 - vint_y) * 4;
                end if;
                assert (su29_word_address(28 downto 22) = 18 and
                    su29_word_address(19 downto 0) = vint_offset / 8)
                    report "Rotation DDR address differs from independent coordinate model" severity failure;
                if (vint_offset mod 8 = 0) then
                    assert (su8_byte_enables = x"0F") report "Rotation low pixel byte mask mismatch" severity failure;
                else
                    assert (su8_byte_enables = x"F0") report "Rotation high pixel byte mask mismatch" severity failure;
                end if;
                if (vint_pixels = 0) then
                    vint_buffer := to_integer(su29_word_address(21 downto 20));
                end if;
                assert (su29_word_address(21 downto 20) = vint_buffer and vint_buffer < 3)
                    report "Rotation changed write buffer inside a visible frame" severity failure;
                vint_pixels := vint_pixels + 1;
            end if;
        elsif (sint_frames = 4) then
            assert (vint_pixels = GINT_VISIBLE_WIDTH * GINT_VISIBLE_HEIGHT) report "Rotation missing visible pixels" severity failure;
            for vint_index in v_seen'range loop
                assert (v_seen(vint_index)) report "Rotation skipped source pixel" severity failure;
            end loop;
            report "HDMI_ROTATION_PASS pixels=" & integer'image(vint_pixels) &
                " counterclockwise=" & boolean'image(GBOOL_COUNTERCLOCKWISE);
            finish;
        end if;
    end process;
    progress : process
        file v_progress : text open write_mode is "progress.txt";
        variable v_line : line;
    begin
        loop
            wait for 1 ms;
            write(v_line, time'image(now) & "; frame=" & integer'image(sint_frames) &
                "; row=" & integer'image(sint_y) & "; column=" & integer'image(sint_x));
            writeline(v_progress, v_line);
            flush(v_progress);
        end loop;
    end process;
    watchdog : process
    begin
        wait for 100 ms;
        assert (false) report "Rotation arrival test did not complete" severity failure;
        wait;
    end process;
end architecture;
