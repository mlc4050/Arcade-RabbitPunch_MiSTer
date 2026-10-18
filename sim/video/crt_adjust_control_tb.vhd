-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crt_adjust_control_tb is
end entity;

architecture test of crt_adjust_control_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_adjust : std_logic := '0';
    signal s_size_enable : std_logic := '1';
    signal sint_pixel_phase : natural range 0 to 6 := 0;
    signal s_pixel_enable, s_output_enable : std_logic;
    signal su5_size : unsigned(4 downto 0) := (others => '0');
    signal su7_position : unsigned(6 downto 0) := (others => '0');
    signal su6_shift : unsigned(5 downto 0) := (others => '0');
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0) := (others => '0');
    signal su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0);
    signal s_hsync, s_vsync : std_logic := '1';
    signal s_hblank, s_vblank : std_logic := '1';
    signal s_output_hsync, s_output_vsync, s_output_hblank, s_output_vblank : std_logic;
begin
    s_clk <= not s_clk after 5 ns;
    s_pixel_enable <= '1' when sint_pixel_phase = 0 else '0';
    pixel_enable : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_pixel_phase = 6) then
                sint_pixel_phase <= 0;
            else
                sint_pixel_phase <= sint_pixel_phase + 1;
            end if;
        end if;
    end process;
    dut : entity work.rabbitpunch_crt_adjust
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_pixel_enable => s_pixel_enable,
            i_adjust => s_adjust,
            i_size_enable => s_size_enable,
            iu5_horizontal_size => su5_size,
            iu7_horizontal_position => su7_position,
            iu6_vertical_shift => su6_shift,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            i_horizontal_sync => s_hsync,
            i_vertical_sync => s_vsync,
            i_horizontal_blank => s_hblank,
            i_vertical_blank => s_vblank,
            o_pixel_enable => s_output_enable,
            ou8_red => su8_output_red,
            ou8_green => su8_output_green,
            ou8_blue => su8_output_blue,
            o_horizontal_sync => s_output_hsync,
            o_vertical_sync => s_output_vsync,
            o_horizontal_blank => s_output_hblank,
            o_vertical_blank => s_output_vblank
        );
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        variable vint_signed_size : integer;
        variable vint_period, vint_ticks : natural;
        variable vu8_bits : unsigned(7 downto 0);
    begin
        tick;
        s_initialize <= '0';
        for vint_pattern in 0 to 255 loop
            vu8_bits := to_unsigned(vint_pattern, 8);
            su8_red <= vu8_bits;
            su8_green <= not vu8_bits;
            su8_blue <= rotate_left(vu8_bits, 3);
            s_hsync <= vu8_bits(0);
            s_vsync <= vu8_bits(1);
            s_hblank <= vu8_bits(2);
            s_vblank <= vu8_bits(3);
            su5_size <= vu8_bits(4 downto 0);
            su7_position <= vu8_bits(6 downto 0);
            su6_shift <= vu8_bits(5 downto 0);
            wait for 1 ns;
            assert (su8_output_red = vu8_bits and su8_output_green = not vu8_bits and
                su8_output_blue = rotate_left(vu8_bits, 3))
                report "Native CRT bypass changed RGB" severity failure;
            assert (s_output_hsync = s_hsync and s_output_vsync = s_vsync and
                s_output_hblank = s_hblank and s_output_vblank = s_vblank and
                s_output_enable = s_pixel_enable)
                report "Native CRT bypass changed timing" severity failure;
            tick;
        end loop;
        s_hsync <= '1';
        s_vsync <= '1';
        s_hblank <= '1';
        s_vblank <= '1';
        su7_position <= (others => '0');
        su6_shift <= (others => '0');
        s_initialize <= '1';
        tick;
        s_initialize <= '0';
        s_adjust <= '1';
        for vint_index in 0 to 31 loop
            su5_size <= to_unsigned(vint_index, 5);
            vint_signed_size := vint_index;
            if (vint_index >= 16) then
                vint_signed_size := vint_index - 32;
            end if;
            vint_period := 140 + 5 * vint_signed_size;
            for vint_warmup in 1 to 500 loop
                tick;
            end loop;
            vint_ticks := 0;
            for vint_clock in 1 to vint_period * 8 loop
                tick;
                if (s_output_enable = '1') then
                    vint_ticks := vint_ticks + 1;
                end if;
            end loop;
            assert (vint_ticks = 160)
                report "CRT read-enable density wrong at size " & integer'image(vint_signed_size) &
                    ": " & integer'image(vint_ticks) severity failure;
        end loop;
        s_size_enable <= '0';
        su5_size <= to_unsigned(15, 5);
        for vint_warmup in 1 to 20 loop
            tick;
        end loop;
        for vint_clock in 1 to 100 loop
            tick;
            assert (s_output_enable = s_pixel_enable)
                report "Scandoubler size gate failed to restore native pixel enable" severity failure;
        end loop;
        s_adjust <= '0';
        wait for 1 ns;
        assert (su8_output_red = su8_red and s_output_enable = s_pixel_enable)
            report "Disabling CRT adjustment did not immediately bypass" severity failure;
        report "CRT_ADJUST_CONTROL_PASS bypass=256 size_rates=32 size_gate=pass";
        std.env.finish;
        wait;
    end process;
end architecture;
