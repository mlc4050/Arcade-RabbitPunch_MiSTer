-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Native RGB is a tap only. This block owns HDMI framebuffer presentation,
-- loader sharing and rotated metadata; it has no analog RGB/sync output.
entity rabbitpunch_hdmi_presentation is
    generic (
        GINT_FRAME_PIXELS : positive := 62208
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_ready : in std_logic;
        i_loader_active : in std_logic;
        i_direct_video : in std_logic;
        iu2_rotation : in unsigned(1 downto 0);
        i_native_pixel_enable : in std_logic;
        iu8_native_red : in unsigned(7 downto 0);
        iu8_native_green : in unsigned(7 downto 0);
        iu8_native_blue : in unsigned(7 downto 0);
        i_native_horizontal_sync_n : in std_logic;
        i_native_vertical_sync_n : in std_logic;
        i_native_data_enable : in std_logic;
        i_presented_pixel_enable : in std_logic;
        i_presented_vertical_sync : in std_logic;
        i_presented_data_enable : in std_logic;
        iu12_hdmi_width : in unsigned(11 downto 0);
        iu12_hdmi_height : in unsigned(11 downto 0);
        iu2_aspect : in unsigned(1 downto 0);
        iu3_scale : in unsigned(2 downto 0);
        ou13_aspect_x : out unsigned(12 downto 0);
        ou13_aspect_y : out unsigned(12 downto 0);
        i_framebuffer_vertical_blank : in std_logic;
        o_framebuffer_enable : out std_logic;
        o_framebuffer_force_blank : out std_logic;
        ou5_framebuffer_format : out unsigned(4 downto 0);
        ou12_framebuffer_width : out unsigned(11 downto 0);
        ou12_framebuffer_height : out unsigned(11 downto 0);
        ou32_framebuffer_base : out unsigned(31 downto 0);
        ou14_framebuffer_stride : out unsigned(13 downto 0);
        o_rotation_active : out std_logic;
        ou2_applied_rotation : out unsigned(1 downto 0);
        o_discard_frame : out std_logic;
        o_queue_overflow : out std_logic;
        o_queue_empty : out std_logic;
        iu8_loader_burst_count : in unsigned(7 downto 0);
        iu29_loader_word_address : in unsigned(28 downto 0);
        iu64_loader_write_data : in unsigned(63 downto 0);
        iu8_loader_byte_enables : in unsigned(7 downto 0);
        i_loader_read : in std_logic;
        i_loader_write : in std_logic;
        o_loader_busy : out std_logic;
        o_loader_read_valid : out std_logic;
        ou64_loader_read_data : out unsigned(63 downto 0);
        i_ddr_busy : in std_logic;
        i_ddr_read_valid : in std_logic;
        iu64_ddr_read_data : in unsigned(63 downto 0);
        ou8_ddr_burst_count : out unsigned(7 downto 0);
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_write_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0);
        o_ddr_read : out std_logic;
        o_ddr_write : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_hdmi_presentation is
    signal su2_requested_rotation, su2_applied_rotation : unsigned(1 downto 0) := (others => '0');
    signal s_previous_vertical_sync : std_logic := '0';
    signal s_vertical_sync, s_vertical_sync_rise, s_apply_mode : std_logic;
    signal s_mode_change : std_logic := '0';
    signal s_rotated, s_capture_rotation, s_counterclockwise, s_donor_enabled : std_logic;
    signal s_raw_write, s_framebuffer_valid : std_logic;
    signal su32_base : unsigned(31 downto 0);
    signal su29_raw_address : unsigned(28 downto 0);
    signal su64_raw_data : unsigned(63 downto 0);
    signal su8_raw_bytes : unsigned(7 downto 0);
    signal su12_transposed_width, su12_transposed_height : unsigned(11 downto 0);
    signal su13_native_aspect_x, su13_native_aspect_y : unsigned(12 downto 0);
begin
    s_vertical_sync <= not i_native_vertical_sync_n;
    s_vertical_sync_rise <= s_vertical_sync and not s_previous_vertical_sync;
    su2_requested_rotation <= iu2_rotation when i_direct_video = '0' and iu2_rotation <= 2 else (others => '0');
    s_apply_mode <= s_vertical_sync_rise and i_game_ready and not i_loader_active;
    s_rotated <= '1' when su2_applied_rotation /= 0 and i_direct_video = '0' else '0';
    s_capture_rotation <= s_rotated and not s_mode_change;
    s_counterclockwise <= '1' when su2_applied_rotation = 2 else '0';
    o_rotation_active <= s_rotated;
    ou2_applied_rotation <= su2_applied_rotation;
    o_framebuffer_enable <= s_rotated and s_donor_enabled;
    o_framebuffer_force_blank <= s_rotated and not s_framebuffer_valid;
    ou32_framebuffer_base <= su32_base;
    apply_mode : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_previous_vertical_sync <= s_vertical_sync;
            s_mode_change <= '0';
            if (i_initialize = '1') then
                su2_applied_rotation <= (others => '0');
            elsif (s_apply_mode = '1' and su2_requested_rotation /= su2_applied_rotation) then
                su2_applied_rotation <= su2_requested_rotation;
                s_mode_change <= '1';
            end if;
        end if;
    end process;
    rotation : entity work.rabbitpunch_hdmi_rotation
        port map (
            i_clk => i_clk,
            i_pixel_enable => i_native_pixel_enable,
            iu8_red => iu8_native_red,
            iu8_green => iu8_native_green,
            iu8_blue => iu8_native_blue,
            i_horizontal_sync => not i_native_horizontal_sync_n,
            i_vertical_sync => s_vertical_sync,
            i_data_enable => i_native_data_enable,
            i_enable => s_rotated,
            i_counterclockwise => s_counterclockwise,
            i_framebuffer_vertical_blank => i_framebuffer_vertical_blank,
            i_framebuffer_low_latency => '0',
            o_enabled => s_donor_enabled,
            ou5_format => ou5_framebuffer_format,
            ou12_width => ou12_framebuffer_width,
            ou12_height => ou12_framebuffer_height,
            ou32_base => su32_base,
            ou14_stride => ou14_framebuffer_stride,
            i_ddr_busy => '0',
            ou8_ddr_burst_count => open,
            ou29_ddr_word_address => su29_raw_address,
            ou64_ddr_data => su64_raw_data,
            ou8_ddr_byte_enables => su8_raw_bytes,
            o_ddr_write => s_raw_write
        );
    ddr_transport : entity work.rabbitpunch_rotation_transport
        generic map (
            GINT_FRAME_PIXELS => GINT_FRAME_PIXELS
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_enable => s_capture_rotation,
            i_game_ready => i_game_ready,
            i_loader_active => i_loader_active,
            i_vertical_sync => s_vertical_sync,
            i_donor_enabled => s_donor_enabled,
            i_pixel_write => s_raw_write,
            iu29_pixel_word_address => su29_raw_address,
            iu64_pixel_data => su64_raw_data,
            iu8_pixel_byte_enables => su8_raw_bytes,
            iu2_framebuffer_read_slot => su32_base(24 downto 23),
            o_framebuffer_valid => s_framebuffer_valid,
            o_discard_frame => o_discard_frame,
            o_queue_empty => o_queue_empty,
            o_queue_overflow => o_queue_overflow,
            iu8_loader_burst_count => iu8_loader_burst_count,
            iu29_loader_word_address => iu29_loader_word_address,
            iu64_loader_write_data => iu64_loader_write_data,
            iu8_loader_byte_enables => iu8_loader_byte_enables,
            i_loader_read => i_loader_read,
            i_loader_write => i_loader_write,
            o_loader_busy => o_loader_busy,
            o_loader_read_valid => o_loader_read_valid,
            ou64_loader_read_data => ou64_loader_read_data,
            i_ddr_busy => i_ddr_busy,
            i_ddr_read_valid => i_ddr_read_valid,
            iu64_ddr_read_data => iu64_ddr_read_data,
            ou8_ddr_burst_count => ou8_ddr_burst_count,
            ou29_ddr_word_address => ou29_ddr_word_address,
            ou64_ddr_write_data => ou64_ddr_write_data,
            ou8_ddr_byte_enables => ou8_ddr_byte_enables,
            o_ddr_read => o_ddr_read,
            o_ddr_write => o_ddr_write
        );
    -- Compute integer sizes in the unrotated coordinate system against the
    -- transposed HDMI rectangle, then transpose explicit pixel dimensions.
    -- ARC1/ARC2 are encoded selectors (ARY=0), so keep their encoding intact.
    su12_transposed_width <= iu12_hdmi_height when s_rotated = '1' else iu12_hdmi_width;
    su12_transposed_height <= iu12_hdmi_width when s_rotated = '1' else iu12_hdmi_height;
    aspect : entity work.rabbitpunch_video_aspect
        port map (
            i_clk => i_clk,
            i_pixel_enable => i_presented_pixel_enable,
            i_vertical_sync => i_presented_vertical_sync,
            i_data_enable => i_presented_data_enable,
            i_direct_video => i_direct_video,
            iu12_hdmi_width => su12_transposed_width,
            iu12_hdmi_height => su12_transposed_height,
            iu2_aspect => iu2_aspect,
            iu3_scale => iu3_scale,
            ou13_aspect_x => su13_native_aspect_x,
            ou13_aspect_y => su13_native_aspect_y
        );
    rotated_aspect : process(all)
    begin
        ou13_aspect_x <= su13_native_aspect_x;
        ou13_aspect_y <= su13_native_aspect_y;
        if (s_rotated = '1' and (iu2_aspect = 0 or
            su13_native_aspect_x(12) = '1' or su13_native_aspect_y(12) = '1')) then
            ou13_aspect_x <= su13_native_aspect_y;
            ou13_aspect_y <= su13_native_aspect_x;
        end if;
    end process;
end architecture;
