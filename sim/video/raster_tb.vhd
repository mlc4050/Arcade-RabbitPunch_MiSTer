-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity raster_tb is
    generic (GBOOL_SMALL_MODE : boolean := false);
end entity;

architecture test of raster_tb is
    function choose(vint_nominal, vint_small : natural) return natural is
    begin
        if (GBOOL_SMALL_MODE) then
            return vint_small;
        end if;
        return vint_nominal;
    end function;
    function sync_active return std_logic is
    begin
        if (GBOOL_SMALL_MODE) then
            return '1';
        end if;
        return '0';
    end function;
    function logic(v_condition : boolean) return std_logic is
    begin
        if (v_condition) then
            return '1';
        end if;
        return '0';
    end function;
    constant CINT_HTOTAL : positive := choose(432, 19);
    constant CINT_HSTART : natural := choose(0, 2);
    constant CINT_HWIDTH : positive := choose(288, 7);
    constant CINT_HSYNC_START : natural := choose(352, 12);
    constant CINT_HSYNC_END : positive := choose(392, 16);
    constant CINT_VTOTAL : positive := choose(256, 9);
    constant CINT_VSTART : natural := choose(0, 1);
    constant CINT_VHEIGHT : positive := choose(216, 4);
    constant CINT_VSYNC_START : natural := choose(232, 6);
    constant CINT_VSYNC_END : positive := choose(240, 8);
    constant CINT_XOFFSET : natural := choose(8, 3);
    constant CINT_YOFFSET : natural := choose(0, 2);
    constant C_SYNC_ACTIVE : std_logic := sync_active;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_clock_enable, s_pixel_enable, s_hold : std_logic := '0';
    signal su9_horizontal, su9_vertical, su9_x : unsigned(8 downto 0);
    signal su8_y : unsigned(7 downto 0);
    signal s_active, s_hsync, s_vsync, s_hblank, s_vblank : std_logic;
    signal s_line_start, s_visible_line_start, s_frame_start, s_vblank_start, s_half_frame : std_logic;
begin
    s_clk <= not s_clk after 5 ns;
    s_pixel_enable <= s_clock_enable and not s_hold;
    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            o_pixel_enable => s_clock_enable,
            o_main_phase_enable => open,
            o_sound_cpu_enable => open,
            o_ym_enable => open,
            o_ym_half_enable => open,
            o_adpcm_enable => open
        );
    dut : entity work.rabbitpunch_raster
        generic map (
            GINT_HORIZONTAL_TOTAL => CINT_HTOTAL,
            GINT_HORIZONTAL_VISIBLE_START => CINT_HSTART,
            GINT_HORIZONTAL_VISIBLE_WIDTH => CINT_HWIDTH,
            GINT_HORIZONTAL_SYNC_START => CINT_HSYNC_START,
            GINT_HORIZONTAL_SYNC_END => CINT_HSYNC_END,
            GINT_VERTICAL_TOTAL => CINT_VTOTAL,
            GINT_VERTICAL_VISIBLE_START => CINT_VSTART,
            GINT_VERTICAL_VISIBLE_HEIGHT => CINT_VHEIGHT,
            GINT_VERTICAL_SYNC_START => CINT_VSYNC_START,
            GINT_VERTICAL_SYNC_END => CINT_VSYNC_END,
            GINT_RENDER_X_OFFSET => CINT_XOFFSET,
            GINT_RENDER_Y_OFFSET => CINT_YOFFSET,
            G_HORIZONTAL_SYNC_ACTIVE => C_SYNC_ACTIVE,
            G_VERTICAL_SYNC_ACTIVE => C_SYNC_ACTIVE
        )
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pixel_enable => s_pixel_enable,
            ou9_horizontal_position => su9_horizontal,
            ou9_vertical_position => su9_vertical,
            ou9_pixel_x => su9_x,
            ou8_pixel_y => su8_y,
            o_active => s_active,
            o_hsync => s_hsync,
            o_vsync => s_vsync,
            o_hblank => s_hblank,
            o_vblank => s_vblank,
            o_line_start => s_line_start,
            o_visible_line_start => s_visible_line_start,
            o_frame_start => s_frame_start,
            o_vblank_start => s_vblank_start,
            o_half_frame => s_half_frame
        );
    stimulus : process
        variable vint_x, vint_y, vint_frames, vint_cycles : natural := 0;
        variable vint_pixels, vint_active_pixels, vint_lines, vint_visible_lines : natural := 0;
        variable vint_frame_events, vint_vblank_events, vint_half_events : natural := 0;
        variable v_horizontal_active, v_vertical_active, v_hsync_active, v_vsync_active : boolean;
        procedure check_beam is
        begin
            v_horizontal_active := vint_x >= CINT_HSTART and vint_x < CINT_HSTART + CINT_HWIDTH;
            v_vertical_active := vint_y >= CINT_VSTART and vint_y < CINT_VSTART + CINT_VHEIGHT;
            v_hsync_active := vint_x >= CINT_HSYNC_START and vint_x < CINT_HSYNC_END;
            v_vsync_active := vint_y >= CINT_VSYNC_START and vint_y < CINT_VSYNC_END;
            assert (su9_horizontal = vint_x and su9_vertical = vint_y)
                report "Beam counter changed without enable or wrapped incorrectly" severity failure;
            assert (s_active = logic(v_horizontal_active and v_vertical_active) and
                s_hblank = logic(not v_horizontal_active) and s_vblank = logic(not v_vertical_active))
                report "Raster active/blanking mismatch" severity failure;
            assert ((s_hsync = C_SYNC_ACTIVE) = v_hsync_active and (s_vsync = C_SYNC_ACTIVE) = v_vsync_active)
                report "Raster sync window or polarity mismatch" severity failure;
            if (v_horizontal_active) then
                assert (su9_x = vint_x - CINT_HSTART + CINT_XOFFSET)
                    report "Horizontal render coordinate mismatch" severity failure;
            else
                assert (su9_x = 0) report "Blank horizontal coordinate not cleared" severity failure;
            end if;
            if (v_vertical_active) then
                assert (su8_y = vint_y - CINT_VSTART + CINT_YOFFSET)
                    report "Vertical render coordinate mismatch" severity failure;
            else
                assert (su8_y = 0) report "Blank vertical coordinate not cleared" severity failure;
            end if;
            assert (s_line_start = logic(s_pixel_enable = '1' and vint_x = 0) and
                s_visible_line_start = logic(s_pixel_enable = '1' and vint_x = 0 and v_vertical_active) and
                s_frame_start = logic(s_pixel_enable = '1' and vint_x = 0 and vint_y = 0) and
                s_vblank_start = logic(s_pixel_enable = '1' and vint_x = 0 and vint_y = (CINT_VSTART + CINT_VHEIGHT) mod CINT_VTOTAL) and
                s_half_frame = logic(s_pixel_enable = '1' and vint_x = 0 and vint_y =
                    (CINT_VSTART + CINT_VHEIGHT + CINT_VTOTAL / 2) mod CINT_VTOTAL))
                report "Raster event repeated between enables or used wrong line" severity failure;
        end procedure;
        procedure advance_beam is
        begin
            if (vint_x = CINT_HTOTAL - 1) then
                vint_x := 0;
                if (vint_y = CINT_VTOTAL - 1) then
                    vint_y := 0;
                    vint_frames := vint_frames + 1;
                else
                    vint_y := vint_y + 1;
                end if;
            else
                vint_x := vint_x + 1;
            end if;
        end procedure;
    begin
        wait until rising_edge(s_clk);
        wait until falling_edge(s_clk);
        s_reset <= '0';
        while (vint_frames < 2) loop
            wait until falling_edge(s_clk);
            s_hold <= logic(vint_cycles mod 97 >= 10 and vint_cycles mod 97 <= 13);
            wait until rising_edge(s_clk);
            check_beam;
            if (s_pixel_enable = '1') then
                vint_pixels := vint_pixels + 1;
                if (s_active = '1') then
                    vint_active_pixels := vint_active_pixels + 1;
                end if;
                vint_lines := vint_lines + boolean'pos(s_line_start = '1');
                vint_visible_lines := vint_visible_lines + boolean'pos(s_visible_line_start = '1');
                vint_frame_events := vint_frame_events + boolean'pos(s_frame_start = '1');
                vint_vblank_events := vint_vblank_events + boolean'pos(s_vblank_start = '1');
                vint_half_events := vint_half_events + boolean'pos(s_half_frame = '1');
                advance_beam;
            end if;
            vint_cycles := vint_cycles + 1;
        end loop;
        assert (vint_pixels = 2 * CINT_HTOTAL * CINT_VTOTAL and vint_active_pixels = 2 * CINT_HWIDTH * CINT_VHEIGHT and
            vint_lines = 2 * CINT_VTOTAL and vint_visible_lines = 2 * CINT_VHEIGHT and
            vint_frame_events = 2 and vint_vblank_events = 2 and vint_half_events = 2)
            report "Raster frame totals or interrupt cadence mismatch" severity failure;
        -- Stop mid-line, then reset while the pixel enable is held off.
        for vint_cycle in 1 to 503 loop
            wait until rising_edge(s_clk);
        end loop;
        wait until falling_edge(s_clk);
        s_hold <= '1';
        s_reset <= '1';
        wait until rising_edge(s_clk);
        wait for 1 ns;
        assert (su9_horizontal = 0 and su9_vertical = 0 and s_active = '0' and
            s_hblank = '1' and s_vblank = '1' and s_hsync /= C_SYNC_ACTIVE and s_vsync /= C_SYNC_ACTIVE and
            s_line_start = '0' and s_visible_line_start = '0' and s_frame_start = '0' and
            s_vblank_start = '0' and s_half_frame = '0')
            report "Raster reset required a pixel enable or leaked events" severity failure;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        vint_x := 0;
        vint_y := 0;
        for vint_cycle in 1 to 11 loop
            wait until rising_edge(s_clk);
            check_beam;
        end loop;
        wait until falling_edge(s_clk);
        s_hold <= '0';
        for vint_cycle in 1 to 211 loop
            wait until rising_edge(s_clk);
            check_beam;
            if (s_pixel_enable = '1') then
                advance_beam;
            end if;
        end loop;
        report "RASTER_PASS: two complete frames, gaps, sync polarity/windows, render coordinates and reset; pixel_checks=" &
            integer'image(vint_pixels) & "; cycles=" & integer'image(vint_cycles);
        std.env.finish;
        wait;
    end process;
    process
    begin
        wait for 30 ms;
        assert false report "Raster test timeout" severity failure;
    end process;
end architecture;
