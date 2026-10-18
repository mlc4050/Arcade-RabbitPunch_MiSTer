-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity rotation_transport_tb is
    generic (
        GINT_FRAME_PIXELS : positive := 4
    );
end entity;

architecture test of rotation_transport_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_loader, s_vertical_sync, s_pixel_write : std_logic := '0';
    signal s_busy, s_loader_read, s_loader_write, s_read_valid : std_logic := '0';
    signal s_valid, s_discard, s_empty, s_overflow, s_loader_busy, s_loader_valid : std_logic;
    signal s_ddr_read, s_ddr_write : std_logic;
    signal su29_pixel_address, su29_ddr_address : unsigned(28 downto 0) := (others => '0');
    signal su64_pixel_data, su64_ddr_data, su64_loader_data : unsigned(63 downto 0) := (others => '0');
    signal su8_pixel_bytes, su8_ddr_bytes, su8_ddr_burst : unsigned(7 downto 0) := (others => '0');
    signal su2_read_slot, su2_expected_slot : unsigned(1 downto 0) := (others => '0');
    signal sint_received : natural := 0;
    constant CU29_LOADER_ADDRESS : unsigned(28 downto 0) := to_unsigned(16#06000000#, 29);
    constant CU64_LOADER_DATA : unsigned(63 downto 0) := x"0123456789ABCDEF";
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_rotation_transport
        generic map (
            GINT_FRAME_PIXELS => GINT_FRAME_PIXELS
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_enable => '1',
            i_game_ready => '1',
            i_loader_active => s_loader,
            i_vertical_sync => s_vertical_sync,
            i_donor_enabled => '1',
            i_pixel_write => s_pixel_write,
            iu29_pixel_word_address => su29_pixel_address,
            iu64_pixel_data => su64_pixel_data,
            iu8_pixel_byte_enables => su8_pixel_bytes,
            iu2_framebuffer_read_slot => su2_read_slot,
            o_framebuffer_valid => s_valid,
            o_discard_frame => s_discard,
            o_queue_empty => s_empty,
            o_queue_overflow => s_overflow,
            iu8_loader_burst_count => to_unsigned(1, 8),
            iu29_loader_word_address => CU29_LOADER_ADDRESS,
            iu64_loader_write_data => CU64_LOADER_DATA,
            iu8_loader_byte_enables => to_unsigned(16#A5#, 8),
            i_loader_read => s_loader_read,
            i_loader_write => s_loader_write,
            o_loader_busy => s_loader_busy,
            o_loader_read_valid => s_loader_valid,
            ou64_loader_read_data => su64_loader_data,
            i_ddr_busy => s_busy,
            i_ddr_read_valid => s_read_valid,
            iu64_ddr_read_data => CU64_LOADER_DATA,
            ou8_ddr_burst_count => su8_ddr_burst,
            ou29_ddr_word_address => su29_ddr_address,
            ou64_ddr_write_data => su64_ddr_data,
            ou8_ddr_byte_enables => su8_ddr_bytes,
            o_ddr_read => s_ddr_read,
            o_ddr_write => s_ddr_write
        );
    scoreboard : process
        variable vint_received : natural := 0;
        variable vu29_expected : unsigned(28 downto 0);
    begin
        wait until rising_edge(s_clk);
        if (s_loader = '1' or s_initialize = '1') then
            vint_received := 0;
            if (s_loader = '1' and (s_ddr_read = '1' or s_ddr_write = '1')) then
                assert (su29_ddr_address = CU29_LOADER_ADDRESS and su8_ddr_burst = 1 and
                    su64_ddr_data = CU64_LOADER_DATA and su8_ddr_bytes = x"A5")
                    report "Loader DDR command was corrupted by presentation traffic" severity failure;
            end if;
        elsif (s_ddr_write = '1') then
            assert (s_busy = '0') report "Presentation wrote while DDR busy" severity failure;
            vint_received := vint_received + 1;
            vu29_expected := to_unsigned(16#04800000#, 29) + shift_left(resize(su2_expected_slot, 29), 20) + vint_received;
            assert (su29_ddr_address = vu29_expected and su64_ddr_data = vint_received and su8_ddr_burst = 1)
                report "Presentation DDR packet order/data/address mismatch" severity failure;
            if (vint_received mod 2 = 0) then
                assert (su8_ddr_bytes = x"F0") report "Presentation byte enables mismatch" severity failure;
            else
                assert (su8_ddr_bytes = x"0F") report "Presentation byte enables mismatch" severity failure;
            end if;
        end if;
        sint_received <= vint_received;
    end process;
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait until falling_edge(s_clk);
        end procedure;
        procedure boundary is
        begin
            s_vertical_sync <= '1';
            tick;
            s_vertical_sync <= '0';
            tick;
        end procedure;
        procedure packet(constant vint_slot : natural; constant vint_number : positive) is
        begin
            su29_pixel_address <= to_unsigned(16#04800000#, 29) + shift_left(to_unsigned(vint_slot, 29), 20) + vint_number;
            su64_pixel_data <= to_unsigned(vint_number, 64);
            if (vint_number mod 2 = 0) then
                su8_pixel_bytes <= x"F0";
            else
                su8_pixel_bytes <= x"0F";
            end if;
            s_pixel_write <= '1';
            tick;
            s_pixel_write <= '0';
            tick;
        end procedure;
        procedure complete_frame(constant vint_slot : natural) is
        begin
            su2_expected_slot <= to_unsigned(vint_slot, 2);
            for vint_number in 1 to GINT_FRAME_PIXELS loop
                packet(vint_slot, vint_number);
            end loop;
            tick;
            tick;
            assert (s_empty = '1' and sint_received = GINT_FRAME_PIXELS)
                report "Complete presentation frame did not drain" severity failure;
            boundary;
            su2_read_slot <= to_unsigned(vint_slot, 2);
            tick;
            assert (s_valid = '1') report "Complete transport frame was not published" severity failure;
        end procedure;
    begin
        s_initialize <= '1';
        tick;
        s_initialize <= '0';
        tick;
        assert (s_loader_busy = '1' and s_ddr_read = '0' and s_ddr_write = '0')
            report "Idle loader was granted DDR without ownership" severity failure;
        boundary;
        complete_frame(0);
        s_busy <= '1';
        packet(1, GINT_FRAME_PIXELS + 1);
        packet(1, GINT_FRAME_PIXELS + 2);
        packet(1, GINT_FRAME_PIXELS + 3);
        assert (s_empty = '0') report "Loader takeover did not have queued presentation writes" severity failure;
        s_loader <= '1';
        wait for 1 ns;
        assert (s_valid = '0' and s_ddr_write = '0' and s_loader_busy = '1')
            report "Loader did not immediately blank/block presentation" severity failure;
        tick;
        s_busy <= '0';
        s_loader_read <= '1';
        tick;
        assert (s_ddr_read = '1' and s_ddr_write = '0' and s_loader_busy = '0')
            report "Loader read was not granted" severity failure;
        s_loader_read <= '0';
        for vint_delay in 0 to 3 loop
            tick;
            assert (s_ddr_write = '0' and s_valid = '0') report "Queued pixel escaped during loader read wait" severity failure;
        end loop;
        s_read_valid <= '1';
        wait for 1 ns;
        assert (s_loader_valid = '1' and su64_loader_data = CU64_LOADER_DATA)
            report "Delayed DDR read response did not reach loader" severity failure;
        tick;
        s_read_valid <= '0';
        s_loader_write <= '1';
        tick;
        assert (s_ddr_write = '1' and s_ddr_read = '0') report "Loader write was not forwarded" severity failure;
        s_loader_write <= '0';
        tick;
        s_loader <= '0';
        tick;
        assert (s_empty = '1' and s_valid = '0' and s_ddr_write = '0')
            report "Loader release retained queued pixels or valid image" severity failure;
        -- Discard pixels until a fresh native frame boundary.
        packet(2, 99);
        assert (s_empty = '1' and sint_received = 0) report "Partial post-load frame escaped" severity failure;
        boundary;
        complete_frame(2);
        assert (s_overflow = '0') report "Bounded transport test overflowed" severity failure;
        report "ROTATION_TRANSPORT_PASS pixels_per_frame=" & integer'image(GINT_FRAME_PIXELS);
        finish;
    end process;
end architecture;
