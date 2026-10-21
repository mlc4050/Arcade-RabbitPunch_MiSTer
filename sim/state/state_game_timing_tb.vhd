-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_game_timing_tb is
    generic (
        GBOOL_FULL_SIZE : boolean := false;
        GINT_PHASE_CASES : positive := 7
    );
end entity;

architecture test of state_game_timing_tb is
    function F_SIZE(vint_full, vint_small : positive) return positive is
    begin
        if (GBOOL_FULL_SIZE) then
            return vint_full;
        end if;
        return vint_small;
    end function;
    constant CINT_HORIZONTAL_TOTAL : positive := F_SIZE(432, 72);
    constant CINT_VISIBLE_WIDTH : positive := F_SIZE(288, 48);
    constant CINT_HSYNC_START : positive := F_SIZE(352, 56);
    constant CINT_HSYNC_END : positive := F_SIZE(392, 64);
    constant CINT_VERTICAL_TOTAL : positive := F_SIZE(256, 16);
    constant CINT_VISIBLE_LINES : positive := F_SIZE(216, 12);
    constant CINT_VSYNC_START : positive := F_SIZE(232, 14);
    constant CINT_VSYNC_END : positive := F_SIZE(240, 15);
    constant CINT_HALF_FRAME : natural := (CINT_VISIBLE_LINES + CINT_VERTICAL_TOTAL/2) mod CINT_VERTICAL_TOTAL;
    constant CINT_FRAME_CLOCKS : positive := CINT_HORIZONTAL_TOTAL*CINT_VERTICAL_TOTAL*7;
    type t_metadata is array(0 to 1) of unsigned(5 downto 0);
    type t_events is array(0 to 1) of unsigned(6 downto 0);
    type t_cadences is array(0 to 1) of unsigned(31 downto 0);
    type t_beams is array(0 to 1) of unsigned(17 downto 0);
    type t_positions is array(0 to 1) of unsigned(16 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize, s_hold, s_load : std_logic := '0';
    signal su32_load_cadence, su32_cadence, su32_physical_cadence : unsigned(31 downto 0) := (others => '0');
    signal su18_load_beam, su18_beam, su18_physical_beam : unsigned(17 downto 0) := (others => '0');
    signal s_physical_pixel, s_hsync, s_vsync, s_aligned : std_logic;
    signal su7_phase_offset : unsigned(6 downto 0);
    signal su7_events : unsigned(6 downto 0);
    signal su5_physical_events : unsigned(4 downto 0);
    signal su6_scanout_metadata : t_metadata;
    signal su7_scanout_events : t_events;
    signal su32_scanout_cadence : t_cadences;
    signal su18_scanout_guest, su18_scanout_physical : t_beams;
    signal su17_scanout_position : t_positions;
    signal su2_scanout_aligned, su2_private_main : unsigned(1 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    physical_cadence : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => s_clk,
            i_reset => s_initialize,
            o_pixel_enable => s_physical_pixel,
            o_main_phase_enable => su5_physical_events(0),
            o_sound_cpu_enable => su5_physical_events(1),
            o_ym_enable => su5_physical_events(2),
            o_ym_half_enable => su5_physical_events(3),
            o_adpcm_enable => su5_physical_events(4),
            ou32_state => su32_physical_cadence
        );
    native_scanout : for vint_dut in 0 to 1 generate
        scanout : entity work.rabbitpunch_scanout
            generic map (
                GINT_HORIZONTAL_TOTAL => CINT_HORIZONTAL_TOTAL,
                GINT_VISIBLE_WIDTH => CINT_VISIBLE_WIDTH,
                GINT_HORIZONTAL_SYNC_START => CINT_HSYNC_START,
                GINT_HORIZONTAL_SYNC_END => CINT_HSYNC_END,
                GINT_VERTICAL_TOTAL => CINT_VERTICAL_TOTAL,
                GINT_VISIBLE_LINES => CINT_VISIBLE_LINES,
                GINT_VERTICAL_SYNC_START => CINT_VSYNC_START,
                GINT_VERTICAL_SYNC_END => CINT_VSYNC_END,
                GBOOL_STATE_CAPABLE => vint_dut = 1
            )
            port map (
                i_clk => s_clk,
                i_initialize => s_initialize,
                i_game_ready => '0',
                o_main_phase_enable => su7_scanout_events(vint_dut)(0),
                o_sound_cpu_enable => su7_scanout_events(vint_dut)(1),
                o_ym_enable => su7_scanout_events(vint_dut)(2),
                o_ym_half_enable => su7_scanout_events(vint_dut)(3),
                o_adpcm_enable => su7_scanout_events(vint_dut)(4),
                o_vblank_start => su7_scanout_events(vint_dut)(5),
                o_half_frame => su7_scanout_events(vint_dut)(6),
                o_line_valid => open,
                i_line_ready => '1',
                o_render_bank => open,
                ou9_line_y => open,
                i_line_done => '0',
                o_pixel_valid => open,
                i_pixel_ready => '1',
                o_pixel_bank => open,
                ou9_pixel_x => open,
                ou8_pixel_y => open,
                i_rgb_valid => '0',
                i_rgb_error => '0',
                iu9_rgb_x => (others => '0'),
                iu8_rgb_y => (others => '0'),
                iu8_red => (others => '0'),
                iu8_green => (others => '0'),
                iu8_blue => (others => '0'),
                o_pixel_enable => su6_scanout_metadata(vint_dut)(0),
                o_active => su6_scanout_metadata(vint_dut)(1),
                o_hsync => su6_scanout_metadata(vint_dut)(2),
                o_vsync => su6_scanout_metadata(vint_dut)(3),
                o_hblank => su6_scanout_metadata(vint_dut)(4),
                o_vblank => su6_scanout_metadata(vint_dut)(5),
                ou9_output_x => su17_scanout_position(vint_dut)(8 downto 0),
                ou8_output_y => su17_scanout_position(vint_dut)(16 downto 9),
                ou8_red => open,
                ou8_green => open,
                ou8_blue => open,
                ou9_horizontal_position => su18_scanout_physical(vint_dut)(8 downto 0),
                ou9_vertical_position => su18_scanout_physical(vint_dut)(17 downto 9),
                o_armed => open,
                o_underflow => open,
                i_state_hold => s_hold,
                i_state_load => s_load,
                iu32_state_cadence => su32_load_cadence,
                iu18_state_beam => su18_load_beam,
                ou32_state_cadence => su32_scanout_cadence(vint_dut),
                ou18_state_beam => su18_scanout_guest(vint_dut),
                o_state_aligned => su2_scanout_aligned(vint_dut),
                o_private_main_phase_enable => su2_private_main(vint_dut)
            );
    end generate;
    physical_beam : entity work.rabbitpunch_raster
        generic map (
            GINT_HORIZONTAL_TOTAL => CINT_HORIZONTAL_TOTAL,
            GINT_HORIZONTAL_VISIBLE_WIDTH => CINT_VISIBLE_WIDTH,
            GINT_HORIZONTAL_SYNC_START => CINT_HSYNC_START,
            GINT_HORIZONTAL_SYNC_END => CINT_HSYNC_END,
            GINT_VERTICAL_TOTAL => CINT_VERTICAL_TOTAL,
            GINT_VERTICAL_VISIBLE_HEIGHT => CINT_VISIBLE_LINES,
            GINT_VERTICAL_SYNC_START => CINT_VSYNC_START,
            GINT_VERTICAL_SYNC_END => CINT_VSYNC_END
        )
        port map (
            i_clk => s_clk,
            i_reset => s_initialize,
            i_pixel_enable => s_physical_pixel,
            ou9_horizontal_position => open,
            ou9_vertical_position => open,
            ou9_pixel_x => open,
            ou8_pixel_y => open,
            o_active => open,
            o_hsync => s_hsync,
            o_vsync => s_vsync,
            o_hblank => open,
            o_vblank => open,
            o_line_start => open,
            o_visible_line_start => open,
            o_frame_start => open,
            o_vblank_start => open,
            o_half_frame => open,
            ou18_state => su18_physical_beam
        );
    game_timing : entity work.rabbitpunch_state_game_timing
        generic map (
            GINT_HORIZONTAL_TOTAL => CINT_HORIZONTAL_TOTAL,
            GINT_VISIBLE_WIDTH => CINT_VISIBLE_WIDTH,
            GINT_HORIZONTAL_SYNC_START => CINT_HSYNC_START,
            GINT_HORIZONTAL_SYNC_END => CINT_HSYNC_END,
            GINT_VERTICAL_TOTAL => CINT_VERTICAL_TOTAL,
            GINT_VISIBLE_LINES => CINT_VISIBLE_LINES,
            GINT_VERTICAL_SYNC_START => CINT_VSYNC_START,
            GINT_VERTICAL_SYNC_END => CINT_VSYNC_END
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_hold => s_hold,
            i_load => s_load,
            iu32_cadence => su32_load_cadence,
            iu18_beam => su18_load_beam,
            ou32_cadence => su32_cadence,
            ou18_beam => su18_beam,
            iu3_physical_pixel_phase => su32_physical_cadence(2 downto 0),
            iu18_physical_beam => su18_physical_beam,
            o_aligned => s_aligned,
            o_main_phase_enable => su7_events(0),
            o_sound_cpu_enable => su7_events(1),
            o_ym_enable => su7_events(2),
            o_ym_half_enable => su7_events(3),
            o_adpcm_enable => su7_events(4),
            o_vblank_start => su7_events(5),
            o_half_frame => su7_events(6),
            ou7_phase_offset => su7_phase_offset
        );
    -- Independent integer recurrence for every guest enable, IRQ event and
    -- physical pixel/sync edge. Neither oracle calls an RTL packing function.
    oracle : process(s_clk)
        variable vint_pixel, vint_main, vint_sound, vint_adpcm, vint_h, vint_v : natural := 0;
        variable vint_physical_pixel, vint_physical_h, vint_physical_v : natural := 0;
        variable s_half : std_logic := '0';
        variable vu32_expected : unsigned(31 downto 0);
        variable vu7_events : unsigned(6 downto 0);
        variable s_expected_aligned : std_logic;
        variable vint_phase_offset : integer;
    begin
        if (rising_edge(s_clk)) then
            if (s_initialize = '1') then
                vint_pixel := 0;
                vint_main := 0;
                vint_sound := 0;
                vint_adpcm := 0;
                vint_h := 0;
                vint_v := 0;
                vint_physical_pixel := 0;
                vint_physical_h := 0;
                vint_physical_v := 0;
                s_half := '0';
            else
                vu32_expected := "000000" & s_half & to_unsigned(vint_adpcm, 10) &
                    to_unsigned(vint_sound, 6) & to_unsigned(vint_main, 6) & to_unsigned(vint_pixel, 3);
                assert (su32_cadence = vu32_expected and
                    su18_beam = to_unsigned(vint_v*512 + vint_h, 18))
                    report "Guest cadence/beam differs from independent recurrence" severity failure;
                assert (su18_physical_beam = to_unsigned(vint_physical_v*512 + vint_physical_h, 18) and
                    su32_physical_cadence(2 downto 0) = vint_physical_pixel)
                    report "Physical beam/pixel cadence changed during guest hold/load" severity failure;
                assert ((s_hsync = '0') = (vint_physical_h >= CINT_HSYNC_START and vint_physical_h < CINT_HSYNC_END))
                    report "Physical HSync discontinuity" severity failure;
                assert ((s_vsync = '0') = (vint_physical_v >= CINT_VSYNC_START and vint_physical_v < CINT_VSYNC_END))
                    report "Physical VSync discontinuity" severity failure;
                s_expected_aligned := '0';
                if (vint_h = vint_physical_h and vint_v = vint_physical_v and vint_pixel = vint_physical_pixel) then
                    s_expected_aligned := '1';
                end if;
                assert (s_aligned = s_expected_aligned) report "Incorrect physical release phase" severity failure;
                vint_phase_offset := (((vint_physical_v * CINT_HORIZONTAL_TOTAL + vint_physical_h) * 7 + vint_physical_pixel) -
                    ((vint_v * CINT_HORIZONTAL_TOTAL + vint_h) * 7 + vint_pixel)) mod 128;
                assert (su7_phase_offset = to_unsigned(vint_phase_offset, 7))
                    report "Physical/guest modulo128 phase differs from integer oracle" severity failure;
                vu7_events := (others => '0');
                if (s_hold = '0') then
                    if (vint_main >= 23) then
                        vu7_events(0) := '1';
                    end if;
                    if (vint_sound >= 32) then
                        vu7_events(1) := '1';
                        vu7_events(2) := '1';
                        vu7_events(3) := s_half;
                    end if;
                    if (vint_adpcm >= 863) then
                        vu7_events(4) := '1';
                    end if;
                    if (vint_pixel = 6 and vint_h = 0) then
                        if (vint_v = CINT_VISIBLE_LINES) then
                            vu7_events(5) := '1';
                        elsif (vint_v = CINT_HALF_FRAME) then
                            vu7_events(6) := '1';
                        end if;
                    end if;
                end if;
                assert (su7_events = vu7_events) report "Guest enable or IRQ continuation differs" severity failure;
                assert (su6_scanout_metadata(0) = su6_scanout_metadata(1) and
                    su17_scanout_position(0) = su17_scanout_position(1) and
                    su18_scanout_physical(0) = su18_physical_beam and
                    su18_scanout_physical(1) = su18_physical_beam)
                    report "State timing changed actual native scanout metadata" severity failure;
                assert (su32_scanout_cadence(1) = su32_cadence and su18_scanout_guest(1) = su18_beam and
                    su2_scanout_aligned(1) = s_aligned and su7_scanout_events(1)(4 downto 0) = su7_events(4 downto 0))
                    report "Actual scanout guest timing differs from qualified wrapper" severity failure;
                assert (su32_scanout_cadence(0) = su32_physical_cadence and
                    su18_scanout_guest(0) = su18_physical_beam and
                    su7_scanout_events(0)(4 downto 0) = su5_physical_events and
                    su2_private_main = (su5_physical_events(0) & su5_physical_events(0)))
                    report "Default scanout or private return clock changed" severity failure;
                if (s_hold = '1') then
                    if (s_load = '1') then
                        vint_pixel := to_integer(su32_load_cadence(2 downto 0));
                        vint_main := to_integer(su32_load_cadence(8 downto 3));
                        vint_sound := to_integer(su32_load_cadence(14 downto 9));
                        vint_adpcm := to_integer(su32_load_cadence(24 downto 15));
                        s_half := su32_load_cadence(25);
                        vint_h := to_integer(su18_load_beam(8 downto 0));
                        vint_v := to_integer(su18_load_beam(17 downto 9));
                    end if;
                else
                    if (vint_pixel = 6) then
                        vint_h := (vint_h + 1) mod CINT_HORIZONTAL_TOTAL;
                        if (vint_h = 0) then
                            vint_v := (vint_v + 1) mod CINT_VERTICAL_TOTAL;
                        end if;
                    end if;
                    vint_pixel := (vint_pixel + 1) mod 7;
                    vint_main := (vint_main + 12) mod 35;
                    if (vint_sound >= 32) then
                        s_half := not s_half;
                    end if;
                    vint_sound := (vint_sound + 3) mod 35;
                    vint_adpcm := (vint_adpcm + 12) mod 875;
                end if;
                if (vint_physical_pixel = 6) then
                    vint_physical_h := (vint_physical_h + 1) mod CINT_HORIZONTAL_TOTAL;
                    if (vint_physical_h = 0) then
                        vint_physical_v := (vint_physical_v + 1) mod CINT_VERTICAL_TOTAL;
                    end if;
                end if;
                vint_physical_pixel := (vint_physical_pixel + 1) mod 7;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu32_saved, vu32_other : unsigned(31 downto 0);
        variable vu18_saved : unsigned(17 downto 0);
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        s_initialize <= '1';
        cycles(3);
        s_initialize <= '0';
        cycles(45);
        for vint_phase in 0 to GINT_PHASE_CASES - 1 loop
            while (su32_cadence(2 downto 0) /= vint_phase) loop
                cycles;
            end loop;
            vu32_saved := su32_cadence;
            vu18_saved := su18_beam;
            for vint_repeat in 0 to 2 loop
                s_hold <= '1';
                cycles(1027);
                vu32_other := "000000" & not vu32_saved(25) &
                    to_unsigned(874 - to_integer(vu32_saved(24 downto 15)), 10) &
                    to_unsigned(34 - to_integer(vu32_saved(14 downto 9)), 6) &
                    to_unsigned(34 - to_integer(vu32_saved(8 downto 3)), 6) &
                    to_unsigned((vint_phase + 3) mod 7, 3);
                su32_load_cadence <= vu32_other;
                su18_load_beam <= to_unsigned(CINT_VERTICAL_TOTAL - 1 - to_integer(vu18_saved(17 downto 9)), 9) &
                    to_unsigned(CINT_HORIZONTAL_TOTAL - 1 - to_integer(vu18_saved(8 downto 0)), 9);
                s_load <= '1';
                cycles;
                assert (su32_cadence = vu32_other) severity failure;
                su32_load_cadence <= vu32_saved;
                su18_load_beam <= vu18_saved;
                cycles;
                s_load <= '0';
                assert (su32_cadence = vu32_saved and su18_beam = vu18_saved) severity failure;
            end loop;
            for vint_timeout in 0 to CINT_FRAME_CLOCKS loop
                exit when s_aligned = '1';
                cycles;
                assert (vint_timeout < CINT_FRAME_CLOCKS) report "Physical alignment timeout" severity failure;
            end loop;
            s_hold <= '0';
            for vint_clock in 1 to 12000 loop
                cycles;
                assert (su18_beam = su18_physical_beam and
                    su32_cadence(2 downto 0) = su32_physical_cadence(2 downto 0))
                    report "Guest and presentation pixel phase diverged after release" severity failure;
            end loop;
        end loop;
        report "STATE_GAME_TIMING_PASS phases=" & integer'image(GINT_PHASE_CASES) & ",continuous physical sync,all guest enables/IRQs,aligned release" severity note;
        stop;
        wait;
    end process;
end architecture;
