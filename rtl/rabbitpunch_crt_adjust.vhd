-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Evaluation adapter around unchanged CRT Adjust. Size/shift words carry the
-- vendor's two's-complement encodings; their public VHDL types are unsigned.
-- Native bypass avoids even the vendor's bypass pipeline. One system clock
-- drives both sides of the optional line buffer through separate enables.
entity rabbitpunch_crt_adjust is
    generic (
        GINT_PIXEL_DIVIDER : positive := 7;
        GINT_LINE_PIXELS : positive := 432;
        GINT_FRAME_LINES : positive := 256
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_pixel_enable : in std_logic;
        i_adjust : in std_logic;
        i_size_enable : in std_logic;
        iu5_horizontal_size : in unsigned(4 downto 0);
        iu7_horizontal_position : in unsigned(6 downto 0);
        iu6_vertical_shift : in unsigned(5 downto 0);
        iu8_red : in unsigned(7 downto 0);
        iu8_green : in unsigned(7 downto 0);
        iu8_blue : in unsigned(7 downto 0);
        i_horizontal_sync : in std_logic;
        i_vertical_sync : in std_logic;
        i_horizontal_blank : in std_logic;
        i_vertical_blank : in std_logic;
        o_pixel_enable : out std_logic;
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        o_horizontal_sync : out std_logic;
        o_vertical_sync : out std_logic;
        o_horizontal_blank : out std_logic;
        o_vertical_blank : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_crt_adjust is
    component crt_adjust is
        generic (
            VTOTAL : integer := 263;
            HTOTAL : integer := 384;
            HPOS_MODE : integer := 1
        );
        port (
            clk : in std_logic;
            pxl_cen : in std_logic;
            pxl2_cen : in std_logic;
            active : in std_logic;
            hsize : in unsigned(4 downto 0);
            hoffset : in unsigned(8 downto 0);
            voffset : in unsigned(5 downto 0);
            r_in : in unsigned(7 downto 0);
            g_in : in unsigned(7 downto 0);
            b_in : in unsigned(7 downto 0);
            hs_in : in std_logic;
            vs_in : in std_logic;
            hb_in : in std_logic;
            vb_in : in std_logic;
            r_out : out unsigned(7 downto 0);
            g_out : out unsigned(7 downto 0);
            b_out : out unsigned(7 downto 0);
            hs_out : out std_logic;
            vs_out : out std_logic;
            hb_out : out std_logic;
            vb_out : out std_logic;
            hs_ref_out : out std_logic
        );
    end component;
    constant CU10_PIXEL_DIVIDER : unsigned(9 downto 0) := to_unsigned(GINT_PIXEL_DIVIDER, 10);
    constant CU10_BASE_PERIOD : unsigned(9 downto 0) :=
        shift_left(CU10_PIXEL_DIVIDER, 4) + shift_left(CU10_PIXEL_DIVIDER, 2);
    constant CU10_RATE_STEP : unsigned(9 downto 0) := to_unsigned(20, 10);
    signal s_active, s_read_enable, s_rate_tick, s_reference_sync : std_logic;
    signal s_previous_reference_sync : std_logic := '0';
    signal s_previous_write_sync : std_logic := '0';
    signal s_bank_vertical_blank, s_read_vertical_blank : std_logic := '1';
    signal su5_horizontal_size : unsigned(4 downto 0) := (others => '0');
    signal su7_horizontal_position : unsigned(6 downto 0) := (others => '0');
    signal su6_vertical_shift : unsigned(5 downto 0) := (others => '0');
    signal su9_horizontal_offset : unsigned(8 downto 0);
    signal su10_size_extended, su10_period, su10_next_accumulator : unsigned(9 downto 0);
    signal su10_accumulator : unsigned(9 downto 0) := (others => '0');
    signal su8_adjusted_red, su8_adjusted_green, su8_adjusted_blue : unsigned(7 downto 0);
    signal s_adjusted_horizontal_sync, s_adjusted_vertical_sync : std_logic;
    signal s_adjusted_horizontal_blank : std_logic;
    signal s_adjusted_vertical_blank : std_logic := '1';
begin
    assert (GINT_PIXEL_DIVIDER >= 5 and GINT_PIXEL_DIVIDER <= 20)
        report "CRT size range exceeds read-enable accumulator limits" severity failure;
    assert (GINT_LINE_PIXELS <= 512 and GINT_FRAME_LINES <= 512)
        report "CRT geometry exceeds vendor line/tap widths" severity failure;
    s_active <= i_adjust and not i_initialize;
    su9_horizontal_offset <= resize(su7_horizontal_position, 9) when su7_horizontal_position <= 48 else
        resize(su7_horizontal_position, 9) - to_unsigned(97, 9);
    su10_size_extended <= "11111" & su5_horizontal_size when su5_horizontal_size(4) = '1' else
        "00000" & su5_horizontal_size;
    -- The fixed native /7 pixel cadence gives 140 twentieths per pixel.
    -- Add five twentieths per signed size step, using modulo unsigned adds.
    su10_period <= CU10_BASE_PERIOD + shift_left(su10_size_extended, 2) + su10_size_extended;
    su10_next_accumulator <= su10_accumulator + CU10_RATE_STEP;
    s_rate_tick <= '1' when su10_next_accumulator >= su10_period else '0';
    s_read_enable <= i_pixel_enable when su5_horizontal_size = 0 else s_rate_tick;
    o_pixel_enable <= s_read_enable when s_active = '1' else i_pixel_enable;
    ou8_red <= iu8_red when s_active = '0' else su8_adjusted_red when s_adjusted_vertical_blank = '0' else (others => '0');
    ou8_green <= iu8_green when s_active = '0' else su8_adjusted_green when s_adjusted_vertical_blank = '0' else (others => '0');
    ou8_blue <= iu8_blue when s_active = '0' else su8_adjusted_blue when s_adjusted_vertical_blank = '0' else (others => '0');
    o_horizontal_sync <= not s_adjusted_horizontal_sync when s_active = '1' else i_horizontal_sync;
    o_vertical_sync <= not s_adjusted_vertical_sync when s_active = '1' else i_vertical_sync;
    o_horizontal_blank <= s_adjusted_horizontal_blank when s_active = '1' else i_horizontal_blank;
    o_vertical_blank <= s_adjusted_vertical_blank when s_active = '1' else i_vertical_blank;

    controls_and_read_rate : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                su5_horizontal_size <= (others => '0');
                su7_horizontal_position <= (others => '0');
                su6_vertical_shift <= (others => '0');
                su10_accumulator <= (others => '0');
                s_previous_reference_sync <= '0';
                s_previous_write_sync <= '0';
                s_bank_vertical_blank <= '1';
                s_read_vertical_blank <= '1';
                s_adjusted_vertical_blank <= '1';
            else
                -- Native HSync follows visible pixels. Its bank switch marks
                -- the just-completed row, whose VBlank tag accompanies the
                -- donor's two read-enable pipeline stages. The donor's own
                -- extra line of VBlank delay would discard our first row.
                if (s_read_enable = '1') then
                    s_read_vertical_blank <= s_bank_vertical_blank;
                    s_adjusted_vertical_blank <= s_read_vertical_blank;
                end if;
                if (i_pixel_enable = '1') then
                    s_previous_write_sync <= s_reference_sync;
                    if (s_reference_sync = '1' and s_previous_write_sync = '0') then
                        s_bank_vertical_blank <= i_vertical_blank;
                    end if;
                    su5_horizontal_size <= (others => '0');
                    su7_horizontal_position <= (others => '0');
                    su6_vertical_shift <= (others => '0');
                    if (i_adjust = '1') then
                        if (i_size_enable = '1') then
                            su5_horizontal_size <= iu5_horizontal_size;
                        end if;
                        if (iu7_horizontal_position <= 96) then
                            su7_horizontal_position <= iu7_horizontal_position;
                        end if;
                        su6_vertical_shift <= iu6_vertical_shift;
                    end if;
                end if;
                s_previous_reference_sync <= s_reference_sync;
                if (s_reference_sync = '1' and s_previous_reference_sync = '0') then
                    su10_accumulator <= (others => '0');
                elsif (s_rate_tick = '1') then
                    su10_accumulator <= su10_next_accumulator - su10_period;
                else
                    su10_accumulator <= su10_next_accumulator;
                end if;
            end if;
        end if;
    end process;

    geometry : crt_adjust
        generic map (
            VTOTAL => GINT_FRAME_LINES,
            HTOTAL => GINT_LINE_PIXELS,
            HPOS_MODE => 1
        )
        port map (
            clk => i_clk,
            pxl_cen => i_pixel_enable,
            pxl2_cen => s_read_enable,
            active => s_active,
            hsize => su5_horizontal_size,
            hoffset => su9_horizontal_offset,
            voffset => su6_vertical_shift,
            r_in => iu8_red,
            g_in => iu8_green,
            b_in => iu8_blue,
            hs_in => not i_horizontal_sync,
            vs_in => not i_vertical_sync,
            hb_in => i_horizontal_blank,
            vb_in => '0',
            r_out => su8_adjusted_red,
            g_out => su8_adjusted_green,
            b_out => su8_adjusted_blue,
            hs_out => s_adjusted_horizontal_sync,
            vs_out => s_adjusted_vertical_sync,
            hb_out => s_adjusted_horizontal_blank,
            vb_out => open,
            hs_ref_out => s_reference_sync
        );
end architecture;
