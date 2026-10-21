-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity state_presentation_constant_eval is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        o_done : out std_logic;
        ou2_mode : out unsigned(1 downto 0);
        ou32_writes : out unsigned(31 downto 0);
        o_unblanked : out std_logic
    );
end entity;

architecture test of state_presentation_constant_eval is
    signal sint_phase : natural range 0 to 6 := 0;
    signal sint_x : natural range 0 to 47 := 0;
    signal sint_y : natural range 0 to 27 := 0;
    signal sint_cycles : natural range 0 to 150528 := 0;
    signal s_pixel_enable, s_horizontal_sync, s_vertical_sync, s_data_enable : std_logic;
    signal s_write, s_blank, s_overflow : std_logic;
    signal su32_writes : unsigned(31 downto 0) := (others => '0');
    signal s_unblanked : std_logic := '0';
begin
    s_pixel_enable <= '1' when sint_phase = 6 else '0';
    s_horizontal_sync <= '1' when sint_x >= 40 and sint_x < 44 else '0';
    s_vertical_sync <= '1' when sint_y >= 24 and sint_y < 26 else '0';
    s_data_enable <= '1' when sint_x < 32 and sint_y < 20 else '0';
    o_done <= '1' when sint_cycles = 150528 else '0';
    ou32_writes <= su32_writes;
    o_unblanked <= s_unblanked;
    raster : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                sint_phase <= 0;
                sint_x <= 0;
                sint_y <= 0;
                sint_cycles <= 0;
                su32_writes <= (others => '0');
                s_unblanked <= '0';
            else
                assert (s_overflow = '0') report "Constant-mode queue overflow" severity failure;
                if (sint_cycles < 150528) then
                    sint_cycles <= sint_cycles + 1;
                end if;
                if (s_write = '1') then
                    su32_writes <= su32_writes + 1;
                end if;
                if (s_blank = '0' and ou2_mode /= 0) then
                    s_unblanked <= '1';
                end if;
                if (sint_phase = 6) then
                    sint_phase <= 0;
                    if (sint_x = 47) then
                        sint_x <= 0;
                        if (sint_y = 27) then
                            sint_y <= 0;
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
        end if;
    end process;
    presentation : entity work.rabbitpunch_state_hdmi_presentation
        generic map (
            GINT_FRAME_PIXELS => 640
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_game_ready => '1',
            i_loader_active => '0',
            i_direct_video => '0',
            iu2_rotation => "01",
            i_native_pixel_enable => s_pixel_enable,
            iu8_native_red => to_unsigned(sint_x, 8),
            iu8_native_green => to_unsigned(sint_y, 8),
            iu8_native_blue => x"A5",
            i_native_horizontal_sync_n => not s_horizontal_sync,
            i_native_vertical_sync_n => not s_vertical_sync,
            i_native_data_enable => s_data_enable,
            i_presented_pixel_enable => s_pixel_enable,
            i_presented_vertical_sync => s_vertical_sync,
            i_presented_data_enable => s_data_enable,
            iu12_hdmi_width => to_unsigned(1920, 12),
            iu12_hdmi_height => to_unsigned(1080, 12),
            iu2_aspect => "00",
            iu3_scale => "000",
            ou13_aspect_x => open,
            ou13_aspect_y => open,
            i_framebuffer_vertical_blank => s_vertical_sync,
            o_framebuffer_enable => open,
            o_framebuffer_force_blank => s_blank,
            ou5_framebuffer_format => open,
            ou12_framebuffer_width => open,
            ou12_framebuffer_height => open,
            ou32_framebuffer_base => open,
            ou14_framebuffer_stride => open,
            o_rotation_active => open,
            ou2_applied_rotation => ou2_mode,
            o_discard_frame => open,
            o_queue_overflow => s_overflow,
            o_queue_empty => open,
            iu8_loader_burst_count => to_unsigned(0, 8),
            iu29_loader_word_address => to_unsigned(0, 29),
            iu64_loader_write_data => to_unsigned(0, 64),
            iu8_loader_byte_enables => to_unsigned(0, 8),
            i_loader_read => '0',
            i_loader_write => '0',
            o_loader_busy => open,
            o_loader_read_valid => open,
            ou64_loader_read_data => open,
            o_state_busy => open,
            o_state_read_valid => open,
            ou64_state_read_data => open,
            i_ddr_busy => '0',
            i_ddr_read_valid => '0',
            iu64_ddr_read_data => to_unsigned(0, 64),
            ou8_ddr_burst_count => open,
            ou29_ddr_word_address => open,
            ou64_ddr_write_data => open,
            ou8_ddr_byte_enables => open,
            o_ddr_read => open,
            o_ddr_write => s_write
        );
end architecture;
