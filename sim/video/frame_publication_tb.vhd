-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity frame_publication_tb is
    generic (
        GINT_FRAME_PIXELS : positive := 4
    );
end entity;

architecture test of frame_publication_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_loader, s_vertical_sync, s_write, s_overflow : std_logic := '0';
    signal s_enable, s_ready, s_donor_enabled, s_empty : std_logic := '1';
    signal s_capture, s_flush, s_valid, s_discard : std_logic;
    signal su2_write_buffer, su2_read_buffer : unsigned(1 downto 0) := (others => '0');
    signal su3_valid_buffers : unsigned(2 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_frame_publication
        generic map (
            GINT_FRAME_PIXELS => GINT_FRAME_PIXELS
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_enable => s_enable,
            i_game_ready => s_ready,
            i_loader_active => s_loader,
            i_vertical_sync => s_vertical_sync,
            i_donor_enabled => s_donor_enabled,
            i_pixel_write => s_write,
            iu2_write_buffer => su2_write_buffer,
            iu2_read_buffer => su2_read_buffer,
            i_queue_empty => s_empty,
            i_queue_overflow => s_overflow,
            o_capture_enable => s_capture,
            o_flush_queue => s_flush,
            o_framebuffer_valid => s_valid,
            o_discard_frame => s_discard,
            ou3_valid_buffers => su3_valid_buffers
        );
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait until falling_edge(s_clk);
        end procedure;
        procedure frame_boundary is
        begin
            s_vertical_sync <= '1';
            tick;
            s_vertical_sync <= '0';
            tick;
        end procedure;
        procedure pixels(constant vint_slot : natural; constant vint_count : natural) is
        begin
            su2_write_buffer <= to_unsigned(vint_slot, 2);
            s_write <= '1';
            for vint_pixel in 1 to vint_count loop
                tick;
            end loop;
            s_write <= '0';
            tick;
        end procedure;
    begin
        s_initialize <= '1';
        tick;
        s_initialize <= '0';
        tick;
        assert (s_capture = '0' and s_valid = '0') report "Uninitialized image was advertised" severity failure;
        pixels(0, GINT_FRAME_PIXELS);
        frame_boundary;
        assert (su3_valid_buffers = 0) report "Partial startup frame was counted" severity failure;
        pixels(0, GINT_FRAME_PIXELS);
        frame_boundary;
        assert (s_valid = '1' and su3_valid_buffers = 1) report "Complete drained frame was not published" severity failure;
        s_donor_enabled <= '0';
        wait for 1 ns;
        assert (s_valid = '0') report "Disabled donor advertised a frame" severity failure;
        s_donor_enabled <= '1';
        -- First write into an old valid slot must invalidate before a clock.
        su2_write_buffer <= to_unsigned(0, 2);
        s_write <= '1';
        wait for 1 ns;
        assert (s_valid = '0') report "Old valid image survived its first overwrite" severity failure;
        tick;
        s_write <= '0';
        tick;
        frame_boundary;
        assert (su3_valid_buffers = 0) report "Short frame was published" severity failure;
        pixels(1, GINT_FRAME_PIXELS + 1);
        frame_boundary;
        assert (su3_valid_buffers = 0) report "Long frame was published" severity failure;
        pixels(1, GINT_FRAME_PIXELS / 2);
        pixels(2, GINT_FRAME_PIXELS / 2);
        frame_boundary;
        assert (su3_valid_buffers = 0) report "Mixed-slot frame was published" severity failure;
        pixels(1, GINT_FRAME_PIXELS);
        s_empty <= '0';
        frame_boundary;
        assert (su3_valid_buffers = 0) report "Undrained frame was published" severity failure;
        s_empty <= '1';
        pixels(2, GINT_FRAME_PIXELS);
        frame_boundary;
        su2_read_buffer <= to_unsigned(2, 2);
        tick;
        assert (s_valid = '1') report "Recovery frame was not published" severity failure;
        s_loader <= '1';
        wait for 1 ns;
        assert (s_flush = '1' and s_capture = '0' and s_valid = '0') report "Loader did not immediately own presentation" severity failure;
        tick;
        s_loader <= '0';
        tick;
        assert (s_capture = '0' and su3_valid_buffers = 0) report "Load retained stale validity" severity failure;
        pixels(0, GINT_FRAME_PIXELS);
        frame_boundary;
        assert (su3_valid_buffers = 0) report "Post-load partial frame was counted" severity failure;
        pixels(0, GINT_FRAME_PIXELS);
        frame_boundary;
        su2_read_buffer <= to_unsigned(0, 2);
        tick;
        assert (s_valid = '1') report "Post-load complete frame failed" severity failure;
        s_overflow <= '1';
        wait for 1 ns;
        assert (s_flush = '1' and s_valid = '0') report "Overflow did not blank/flush immediately" severity failure;
        tick;
        assert (s_discard = '1' and su3_valid_buffers = 0) report "Overflow validity was retained" severity failure;
        s_overflow <= '0';
        tick;
        frame_boundary;
        pixels(0, GINT_FRAME_PIXELS);
        frame_boundary;
        assert (s_valid = '1') report "Overflow recovery failed" severity failure;
        s_enable <= '0';
        tick;
        assert (s_flush = '1' and s_valid = '0' and su3_valid_buffers = 0) report "Disabled rotation retained validity" severity failure;
        s_enable <= '1';
        s_ready <= '0';
        tick;
        assert (s_capture = '0' and s_flush = '1') report "Game-not-ready retained capture" severity failure;
        report "FRAME_PUBLICATION_PASS";
        finish;
    end process;
end architecture;
