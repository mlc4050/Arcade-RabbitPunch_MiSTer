-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Presentation-only validity. This does not choose slots or retain game pixels.
-- The upstream rotator must emit each visible pixel exactly once into one slot;
-- its independent address/colour scoreboard establishes that prerequisite.
entity rabbitpunch_frame_publication is
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
        iu2_write_buffer : in unsigned(1 downto 0);
        iu2_read_buffer : in unsigned(1 downto 0);
        i_queue_empty : in std_logic;
        i_queue_overflow : in std_logic;
        o_capture_enable : out std_logic;
        o_flush_queue : out std_logic;
        o_framebuffer_valid : out std_logic;
        o_discard_frame : out std_logic;
        ou3_valid_buffers : out unsigned(2 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_frame_publication is
    signal s_previous_vertical_sync, s_capturing : std_logic := '0';
    signal s_seen_buffer, s_bad_frame : std_logic := '0';
    signal s_allowed, s_flush, s_vertical_sync_rise : std_logic;
    signal su2_frame_buffer : unsigned(1 downto 0) := (others => '0');
    signal su3_valid_buffers : unsigned(2 downto 0) := (others => '0');
    signal sint_pixels : natural range 0 to GINT_FRAME_PIXELS := 0;
begin
    s_allowed <= i_enable and i_game_ready and not i_loader_active;
    s_flush <= i_initialize or not s_allowed or i_queue_overflow;
    s_vertical_sync_rise <= i_vertical_sync and not s_previous_vertical_sync;
    o_flush_queue <= s_flush;
    -- Start at a source frame boundary, not halfway through an image after a
    -- load/reset. A packet coincident with VS is discarded as malformed input.
    o_capture_enable <= '1' when s_capturing = '1' and s_flush = '0' and
        s_vertical_sync_rise = '0' and iu2_write_buffer < 3 else '0';
    ou3_valid_buffers <= su3_valid_buffers;
    advertised_frame : process(all)
    begin
        o_framebuffer_valid <= '0';
        if (s_flush = '0' and i_donor_enabled = '1' and iu2_read_buffer < 3) then
            -- Invalidate on the first write immediately, before the validity
            -- register catches up. Known slot exclusion is also checked upstream.
            if (not (i_pixel_write = '1' and iu2_write_buffer = iu2_read_buffer)) then
                o_framebuffer_valid <= su3_valid_buffers(to_integer(iu2_read_buffer));
            end if;
        end if;
    end process;
    frame_status : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_discard_frame <= '0';
            s_previous_vertical_sync <= i_vertical_sync;
            if (s_flush = '1') then
                su3_valid_buffers <= (others => '0');
                s_capturing <= '0';
                s_seen_buffer <= '0';
                s_bad_frame <= '0';
                sint_pixels <= 0;
                if (i_queue_overflow = '1') then
                    o_discard_frame <= '1';
                end if;
            elsif (s_vertical_sync_rise = '1') then
                if (s_capturing = '1' and s_seen_buffer = '1') then
                    if (s_bad_frame = '0' and sint_pixels = GINT_FRAME_PIXELS and
                        i_queue_empty = '1' and i_pixel_write = '0') then
                        su3_valid_buffers(to_integer(su2_frame_buffer)) <= '1';
                    else
                        o_discard_frame <= '1';
                    end if;
                end if;
                s_capturing <= '1';
                s_seen_buffer <= '0';
                s_bad_frame <= '0';
                sint_pixels <= 0;
            elsif (s_capturing = '1' and i_pixel_write = '1') then
                if (iu2_write_buffer < 3) then
                    su3_valid_buffers(to_integer(iu2_write_buffer)) <= '0';
                    if (s_seen_buffer = '0') then
                        su2_frame_buffer <= iu2_write_buffer;
                        s_seen_buffer <= '1';
                    elsif (iu2_write_buffer /= su2_frame_buffer) then
                        s_bad_frame <= '1';
                    end if;
                else
                    s_bad_frame <= '1';
                end if;
                if (sint_pixels < GINT_FRAME_PIXELS) then
                    sint_pixels <= sint_pixels + 1;
                else
                    s_bad_frame <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
