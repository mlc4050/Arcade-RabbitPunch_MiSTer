-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Presentation writes may be discarded during a ROM load. The caller must
-- assert loader ownership before its first request and retain it through the
-- final read response/output word. Only the loader issues DDR reads; responses
-- remain connected to it continuously. This boundary is not in production yet.
entity rabbitpunch_rotation_transport is
    generic (
        GINT_FRAME_PIXELS : positive := 62208
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_enable : in std_logic;
        i_game_ready : in std_logic;
        i_loader_active : in std_logic;
        i_vertical_sync : in std_logic;
        i_donor_enabled : in std_logic;
        i_pixel_write : in std_logic;
        iu29_pixel_word_address : in unsigned(28 downto 0);
        iu64_pixel_data : in unsigned(63 downto 0);
        iu8_pixel_byte_enables : in unsigned(7 downto 0);
        iu2_framebuffer_read_slot : in unsigned(1 downto 0);
        o_framebuffer_valid : out std_logic;
        o_discard_frame : out std_logic;
        o_queue_empty : out std_logic;
        o_queue_overflow : out std_logic;
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

architecture rtl of rabbitpunch_rotation_transport is
    signal s_capture, s_flush, s_empty, s_overflow, s_write : std_logic;
    signal su29_queue_address : unsigned(28 downto 0);
    signal su64_queue_data : unsigned(63 downto 0);
    signal su8_queue_bytes : unsigned(7 downto 0);
begin
    o_queue_empty <= s_empty;
    o_queue_overflow <= s_overflow;
    o_loader_busy <= i_ddr_busy or not i_loader_active or i_initialize;
    o_loader_read_valid <= i_ddr_read_valid;
    ou64_loader_read_data <= iu64_ddr_read_data;
    ou8_ddr_burst_count <= iu8_loader_burst_count when i_loader_active = '1' else to_unsigned(1, 8);
    ou29_ddr_word_address <= iu29_loader_word_address when i_loader_active = '1' else su29_queue_address;
    ou64_ddr_write_data <= iu64_loader_write_data when i_loader_active = '1' else su64_queue_data;
    ou8_ddr_byte_enables <= iu8_loader_byte_enables when i_loader_active = '1' else su8_queue_bytes;
    o_ddr_read <= i_loader_read and i_loader_active and not i_initialize;
    o_ddr_write <= (i_loader_write and i_loader_active and not i_initialize) or
        (s_write and not i_loader_active and not i_initialize);
    publication : entity work.rabbitpunch_frame_publication
        generic map (
            GINT_FRAME_PIXELS => GINT_FRAME_PIXELS
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_enable => i_enable,
            i_game_ready => i_game_ready,
            i_loader_active => i_loader_active,
            i_vertical_sync => i_vertical_sync,
            i_donor_enabled => i_donor_enabled,
            i_pixel_write => i_pixel_write,
            iu2_write_buffer => iu29_pixel_word_address(21 downto 20),
            iu2_read_buffer => iu2_framebuffer_read_slot,
            i_queue_empty => s_empty,
            i_queue_overflow => s_overflow,
            o_capture_enable => s_capture,
            o_flush_queue => s_flush,
            o_framebuffer_valid => o_framebuffer_valid,
            o_discard_frame => o_discard_frame,
            ou3_valid_buffers => open
        );
    pixels : entity work.rabbitpunch_ddr_write_queue
        port map (
            i_clk => i_clk,
            i_initialize => s_flush,
            i_write => i_pixel_write and s_capture,
            iu29_word_address => iu29_pixel_word_address,
            iu64_data => iu64_pixel_data,
            iu8_byte_enables => iu8_pixel_byte_enables,
            o_full => open,
            o_empty => s_empty,
            o_overflow => s_overflow,
            i_ddr_busy => i_ddr_busy or i_loader_active or i_initialize,
            o_ddr_write => s_write,
            ou29_ddr_word_address => su29_queue_address,
            ou64_ddr_data => su64_queue_data,
            ou8_ddr_byte_enables => su8_queue_bytes
        );
end architecture;
