-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Emulated game timing is distinct from the continuously running physical
-- presentation timing. This wrapper cannot stop or load physical sync: it
-- receives only its current phase/beam for an explicit parent release barrier.
entity rabbitpunch_state_game_timing is
    generic (
        GINT_HORIZONTAL_TOTAL : positive := 432;
        GINT_VISIBLE_WIDTH : positive := 288;
        GINT_HORIZONTAL_SYNC_START : natural := 352;
        GINT_HORIZONTAL_SYNC_END : positive := 392;
        GINT_VERTICAL_TOTAL : positive := 256;
        GINT_VISIBLE_LINES : positive := 216;
        GINT_VERTICAL_SYNC_START : natural := 232;
        GINT_VERTICAL_SYNC_END : positive := 240;
        GINT_RENDER_X_OFFSET : natural := 8
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_hold : in std_logic;
        i_load : in std_logic;
        iu32_cadence : in unsigned(31 downto 0);
        iu18_beam : in unsigned(17 downto 0);
        ou32_cadence : out unsigned(31 downto 0);
        ou18_beam : out unsigned(17 downto 0);
        iu3_physical_pixel_phase : in unsigned(2 downto 0);
        iu18_physical_beam : in unsigned(17 downto 0);
        o_aligned : out std_logic;
        o_main_phase_enable : out std_logic;
        o_sound_cpu_enable : out std_logic;
        o_ym_enable : out std_logic;
        o_ym_half_enable : out std_logic;
        o_adpcm_enable : out std_logic;
        o_vblank_start : out std_logic;
        o_half_frame : out std_logic;
        ou7_phase_offset : out unsigned(6 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_state_game_timing is
    signal s_pixel_enable : std_logic;
    signal su32_cadence : unsigned(31 downto 0);
    signal su18_beam : unsigned(17 downto 0);
    constant CU7_ROW_STEP : unsigned(6 downto 0) := to_unsigned((GINT_HORIZONTAL_TOTAL * 7) mod 128, 7);
    function F_BEAM_PHASE(vu18_beam : unsigned(17 downto 0);
                          vu3_pixel_phase : unsigned(2 downto 0)) return unsigned is
        variable vu7_x, vu7_y, vu7_result : unsigned(6 downto 0);
    begin
        vu7_x := resize(vu18_beam(8 downto 0), 7);
        vu7_y := resize(vu18_beam(17 downto 9), 7);
        -- For the board's432-pixel line this reduces to80*y +7*x +phase.
        -- The loop also supports the smaller native timing fixture, using
        -- only constant-selected shifts/adds rather than a hardware multiply.
        vu7_result := shift_left(vu7_x, 3) - vu7_x + resize(vu3_pixel_phase, 7);
        for vint_bit in 0 to 6 loop
            if (CU7_ROW_STEP(vint_bit) = '1') then
                vu7_result := vu7_result + shift_left(vu7_y, vint_bit);
            end if;
        end loop;
        return vu7_result;
    end function;
begin
    ou32_cadence <= su32_cadence;
    ou18_beam <= su18_beam;
    ou7_phase_offset <= F_BEAM_PHASE(iu18_physical_beam, iu3_physical_pixel_phase) -
        F_BEAM_PHASE(su18_beam, su32_cadence(2 downto 0));
    o_aligned <= '1' when i_initialize = '0' and
        iu3_physical_pixel_phase = su32_cadence(2 downto 0) and iu18_physical_beam = su18_beam else '0';
    guest_cadence : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => i_clk,
            i_reset => i_initialize,
            o_pixel_enable => s_pixel_enable,
            o_main_phase_enable => o_main_phase_enable,
            o_sound_cpu_enable => o_sound_cpu_enable,
            o_ym_enable => o_ym_enable,
            o_ym_half_enable => o_ym_half_enable,
            o_adpcm_enable => o_adpcm_enable,
            i_state_hold => i_hold,
            i_state_load => i_load,
            iu32_state => iu32_cadence,
            ou32_state => su32_cadence
        );
    guest_beam : entity work.rabbitpunch_raster
        generic map (
            GINT_HORIZONTAL_TOTAL => GINT_HORIZONTAL_TOTAL,
            GINT_HORIZONTAL_VISIBLE_WIDTH => GINT_VISIBLE_WIDTH,
            GINT_HORIZONTAL_SYNC_START => GINT_HORIZONTAL_SYNC_START,
            GINT_HORIZONTAL_SYNC_END => GINT_HORIZONTAL_SYNC_END,
            GINT_VERTICAL_TOTAL => GINT_VERTICAL_TOTAL,
            GINT_VERTICAL_VISIBLE_HEIGHT => GINT_VISIBLE_LINES,
            GINT_VERTICAL_SYNC_START => GINT_VERTICAL_SYNC_START,
            GINT_VERTICAL_SYNC_END => GINT_VERTICAL_SYNC_END,
            GINT_RENDER_X_OFFSET => GINT_RENDER_X_OFFSET
        )
        port map (
            i_clk => i_clk,
            i_reset => i_initialize,
            i_pixel_enable => s_pixel_enable,
            ou9_horizontal_position => open,
            ou9_vertical_position => open,
            ou9_pixel_x => open,
            ou8_pixel_y => open,
            o_active => open,
            o_hsync => open,
            o_vsync => open,
            o_hblank => open,
            o_vblank => open,
            o_line_start => open,
            o_visible_line_start => open,
            o_frame_start => open,
            o_vblank_start => o_vblank_start,
            o_half_frame => o_half_frame,
            i_state_hold => i_hold,
            i_state_load => i_load,
            iu18_state => iu18_beam,
            ou18_state => su18_beam
        );
end architecture;
