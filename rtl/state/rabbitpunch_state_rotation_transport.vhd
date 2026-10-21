-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Real presentation queue/publication logic with independent loader, rotation
-- and state DDR ownership. Presentation flush never resets read ownership.
entity rabbitpunch_state_rotation_transport is
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
        i_state_active : in std_logic := '0';
        i_state_read : in std_logic := '0';
        i_state_write : in std_logic := '0';
        iu29_state_word_address : in unsigned(28 downto 0) := (others => '0');
        iu64_state_write_data : in unsigned(63 downto 0) := (others => '0');
        iu8_state_byte_enables : in unsigned(7 downto 0) := (others => '1');
        o_state_busy : out std_logic;
        o_state_read_valid : out std_logic;
        ou64_state_read_data : out unsigned(63 downto 0);
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

architecture rtl of rabbitpunch_state_rotation_transport is
    signal s_capture, s_flush, s_empty, s_overflow, s_write, s_queue_busy : std_logic;
    signal su29_queue_address : unsigned(28 downto 0);
    signal su64_queue_data : unsigned(63 downto 0);
    signal su8_queue_bytes : unsigned(7 downto 0);
begin
    o_queue_empty <= s_empty;
    o_queue_overflow <= s_overflow;
    ddr_owner : entity work.rabbitpunch_state_ddr_arbiter
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_loader_active => i_loader_active,
            i_loader_read => i_loader_read,
            i_loader_write => i_loader_write,
            iu8_loader_burst_count => iu8_loader_burst_count,
            iu29_loader_word_address => iu29_loader_word_address,
            iu64_loader_write_data => iu64_loader_write_data,
            iu8_loader_byte_enables => iu8_loader_byte_enables,
            o_loader_busy => o_loader_busy,
            o_loader_read_valid => o_loader_read_valid,
            ou64_loader_read_data => ou64_loader_read_data,
            i_rotation_write => s_write,
            iu29_rotation_word_address => su29_queue_address,
            iu64_rotation_data => su64_queue_data,
            iu8_rotation_byte_enables => su8_queue_bytes,
            o_rotation_busy => s_queue_busy,
            i_state_active => i_state_active,
            i_state_read => i_state_read,
            i_state_write => i_state_write,
            iu29_state_word_address => iu29_state_word_address,
            iu64_state_write_data => iu64_state_write_data,
            iu8_state_byte_enables => iu8_state_byte_enables,
            o_state_busy => o_state_busy,
            o_state_read_valid => o_state_read_valid,
            ou64_state_read_data => ou64_state_read_data,
            o_read_idle => open,
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
            i_ddr_busy => s_queue_busy,
            o_ddr_write => s_write,
            ou29_ddr_word_address => su29_queue_address,
            ou64_ddr_data => su64_queue_data,
            ou8_ddr_byte_enables => su8_queue_bytes
        );
end architecture;
