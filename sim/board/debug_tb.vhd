-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity debug_tb is
end entity;

architecture test of debug_tb is
    signal s_clk : std_logic := '0';
    signal s_pixel_enable, s_visible, s_cpu_request, s_cpu_write : std_logic := '0';
    signal s_vertical_sync : std_logic := '1';
    signal s_sound_request, s_sound_write, s_audio_sample : std_logic := '0';
    signal su9_x, su9_y : unsigned(8 downto 0) := (others => '0');
    signal su16_status : unsigned(15 downto 0) := (others => '0');
    signal su24_cpu_address : unsigned(23 downto 0) := (others => '0');
    signal su16_cpu_data, su16_sound_address : unsigned(15 downto 0) := (others => '0');
    signal su8_sound_data : unsigned(7 downto 0) := (others => '0');
    signal su2_bytes : unsigned(1 downto 0) := (others => '0');
    signal su511_snapshot : unsigned(510 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_debug
        generic map (
            GBOOL_JTAG_ENABLE => false,
            GU32_BUILD_ID => x"1234ABCD",
            GINT_COUNTER_WIDTH => 3
        )
        port map (
            i_clk => s_clk,
            i_pixel_enable => s_pixel_enable,
            i_visible => s_visible,
            i_vertical_sync => s_vertical_sync,
            iu9_beam_x => su9_x,
            iu9_beam_y => su9_y,
            iu16_status => su16_status,
            i_cpu_request => s_cpu_request,
            i_cpu_write => s_cpu_write,
            iu24_cpu_address => su24_cpu_address,
            iu16_cpu_data => su16_cpu_data,
            iu2_cpu_bytes => su2_bytes,
            i_sound_request => s_sound_request,
            i_sound_write => s_sound_write,
            iu16_sound_address => su16_sound_address,
            iu8_sound_data => su8_sound_data,
            i_audio_sample => s_audio_sample,
            ou511_snapshot => su511_snapshot
        );
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure settle is
        begin
            tick;
            tick;
        end procedure;
    begin
        settle;
        assert (su511_snapshot(31 downto 0) = x"5250554E" and
                su511_snapshot(63 downto 32) = x"1234ABCD" and
                su511_snapshot(510 downto 480) = 1)
            report "Probe identity or layout version mismatch" severity failure;
        assert (su511_snapshot(223 downto 64) = 0)
            report "Counters did not power up at zero" severity failure;
        -- Sync transitions between pixel enables must not create frames.
        s_vertical_sync <= '0';
        settle;
        s_vertical_sync <= '1';
        settle;
        s_pixel_enable <= '1';
        s_visible <= '1';
        s_vertical_sync <= '0';
        s_cpu_request <= '1';
        s_cpu_write <= '1';
        su24_cpu_address <= x"123456";
        su16_cpu_data <= x"CAFE";
        su2_bytes <= "10";
        s_sound_request <= '1';
        s_sound_write <= '1';
        su16_sound_address <= x"F123";
        su8_sound_data <= x"87";
        s_audio_sample <= '1';
        su16_status <= x"0023";
        su9_x <= to_unsigned(431, 9);
        su9_y <= to_unsigned(255, 9);
        tick;
        s_pixel_enable <= '0';
        s_cpu_request <= '0';
        s_sound_request <= '0';
        s_audio_sample <= '0';
        settle;
        assert (su511_snapshot(95 downto 64) = 1 and
                su511_snapshot(127 downto 96) = 1 and
                su511_snapshot(159 downto 128) = 1 and
                su511_snapshot(191 downto 160) = 1 and
                su511_snapshot(223 downto 192) = 1 and
                su511_snapshot(447 downto 416) = 1 and
                su511_snapshot(479 downto 448) = 1)
            report "Probe event counting mismatch" severity failure;
        assert (su511_snapshot(255 downto 224) = x"02123456" and
                su511_snapshot(271 downto 256) = x"CAFE" and
                su511_snapshot(319 downto 288) = x"0187F123" and
                su511_snapshot(351 downto 320) = x"01123456")
            report "Full address/data/byte capture mismatch" severity failure;
        assert (su511_snapshot(360 downto 352) = 431 and
                su511_snapshot(369 downto 361) = 255 and
                su511_snapshot(399 downto 384) = x"0023")
            report "Probe beam/status mismatch" severity failure;
        -- A read updates the request address without overwriting the last write.
        s_cpu_request <= '1';
        s_cpu_write <= '0';
        su24_cpu_address <= x"ABCDEF";
        tick;
        s_cpu_request <= '0';
        su16_status <= (others => '0');
        settle;
        assert (su511_snapshot(127 downto 96) = 2 and
                su511_snapshot(159 downto 128) = 1 and
                su511_snapshot(351 downto 320) = x"00ABCDEF" and
                su511_snapshot(255 downto 224) = x"02123456" and
                su511_snapshot(479 downto 448) = 1)
            report "Read/write separation or reset-independent counters mismatch" severity failure;
        -- Exercise saturation with the reduced test-only counter width.
        for vint_index in 0 to 11 loop
            s_vertical_sync <= '1';
            s_pixel_enable <= '1';
            su16_status(5) <= '0';
            tick;
            s_vertical_sync <= '0';
            su16_status(5) <= '1';
            s_cpu_request <= '1';
            s_cpu_write <= '1';
            s_sound_request <= '1';
            s_audio_sample <= '1';
            tick;
        end loop;
        s_pixel_enable <= '0';
        s_cpu_request <= '0';
        s_sound_request <= '0';
        s_audio_sample <= '0';
        settle;
        assert (su511_snapshot(95 downto 64) = 7 and
                su511_snapshot(127 downto 96) = 7 and
                su511_snapshot(159 downto 128) = 7 and
                su511_snapshot(191 downto 160) = 7 and
                su511_snapshot(223 downto 192) = 7 and
                su511_snapshot(447 downto 416) = 7 and
                su511_snapshot(479 downto 448) = 7)
            report "Probe counter saturation mismatch" severity failure;
        report "DEBUG_PASS";
        finish;
        wait;
    end process;
end architecture;

