-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity scanout_tb is
end entity;

architecture test of scanout_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_game_ready : std_logic := '0';
    signal s_line_valid, s_line_ready, s_render_bank, s_line_done : std_logic;
    signal su9_line_y : unsigned(8 downto 0);
    signal s_pixel_valid, s_pixel_bank, s_rgb_valid : std_logic;
    signal su9_pixel_x, su9_rgb_x, su9_output_x, su9_horizontal, su9_vertical : unsigned(8 downto 0);
    signal su8_pixel_y, su8_rgb_y, su8_output_y : unsigned(7 downto 0);
    signal su8_red, su8_green, su8_blue, su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0);
    signal s_output_enable, s_active, s_hsync, s_vsync, s_hblank, s_vblank, s_armed, s_underflow : std_logic;
    signal s_render_busy : std_logic := '0';
    signal sint_render_delay : natural := 2557;
    signal sint_phase, sint_clean_pixels, sint_recovered_pixels : natural := 0;
    type t_bank_tags is array (0 to 1) of unsigned(8 downto 0);
    signal su9_bank_tags : t_bank_tags := (others => (others => '1'));
    type t_reply is record
        valid : std_logic;
        x : unsigned(8 downto 0);
        y : unsigned(7 downto 0);
    end record;
    type t_replies is array (0 to 3) of t_reply;
    constant C_EMPTY_REPLY : t_reply := ('0', (others => '0'), (others => '0'));
    function bank_index(v_bank : std_logic) return natural is
    begin
        if (v_bank = '1') then
            return 1;
        end if;
        return 0;
    end function;
    function logic(v_condition : boolean) return std_logic is
    begin
        if (v_condition) then
            return '1';
        end if;
        return '0';
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_line_ready <= not s_render_busy;
    dut : entity work.rabbitpunch_scanout
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_ready => s_game_ready,
            o_main_phase_enable => open,
            o_sound_cpu_enable => open,
            o_ym_enable => open,
            o_ym_half_enable => open,
            o_adpcm_enable => open,
            o_vblank_start => open,
            o_half_frame => open,
            o_line_valid => s_line_valid,
            i_line_ready => s_line_ready,
            o_render_bank => s_render_bank,
            ou9_line_y => su9_line_y,
            i_line_done => s_line_done,
            o_pixel_valid => s_pixel_valid,
            i_pixel_ready => '1',
            o_pixel_bank => s_pixel_bank,
            ou9_pixel_x => su9_pixel_x,
            ou8_pixel_y => su8_pixel_y,
            i_rgb_valid => s_rgb_valid,
            i_rgb_error => '0',
            iu9_rgb_x => su9_rgb_x,
            iu8_rgb_y => su8_rgb_y,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            o_pixel_enable => s_output_enable,
            o_active => s_active,
            o_hsync => s_hsync,
            o_vsync => s_vsync,
            o_hblank => s_hblank,
            o_vblank => s_vblank,
            ou9_output_x => su9_output_x,
            ou8_output_y => su8_output_y,
            ou8_red => su8_output_red,
            ou8_green => su8_output_green,
            ou8_blue => su8_output_blue,
            ou9_horizontal_position => su9_horizontal,
            ou9_vertical_position => su9_vertical,
            o_armed => s_armed,
            o_underflow => s_underflow
        );
    row_renderer : process(s_clk)
        variable vint_remaining : natural := 0;
        variable v_bank : std_logic;
        variable vu9_y : unsigned(8 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_line_done <= '0';
            if (s_initialize = '1' or s_game_ready = '0') then
                s_render_busy <= '0';
                su9_bank_tags <= (others => (others => '1'));
            elsif (s_render_busy = '1') then
                if (vint_remaining = 0) then
                    su9_bank_tags(bank_index(v_bank)) <= vu9_y;
                    s_line_done <= '1';
                    s_render_busy <= '0';
                else
                    vint_remaining := vint_remaining - 1;
                end if;
            elsif (s_line_valid = '1' and s_line_ready = '1') then
                assert (s_render_bank /= s_pixel_bank)
                    report "Scanout renderer targeted the selected display bank" severity failure;
                v_bank := s_render_bank;
                vu9_y := su9_line_y;
                vint_remaining := sint_render_delay;
                s_render_busy <= '1';
            end if;
        end if;
    end process;
    rgb_source : process(s_clk)
        variable v_replies : t_replies := (others => C_EMPTY_REPLY);
        variable v_reply : t_reply;
    begin
        if (rising_edge(s_clk)) then
            v_reply := v_replies(3);
            for vint_stage in 3 downto 1 loop
                v_replies(vint_stage) := v_replies(vint_stage - 1);
            end loop;
            v_replies(0) := (s_pixel_valid, su9_pixel_x, su8_pixel_y);
            if (s_pixel_valid = '1') then
                assert (su9_bank_tags(bank_index(s_pixel_bank)) = resize(su8_pixel_y, 9))
                    report "First pixel or scanline used an incomplete/wrong render bank" severity failure;
            end if;
            s_rgb_valid <= v_reply.valid;
            su9_rgb_x <= v_reply.x;
            su8_rgb_y <= v_reply.y;
            su8_red <= v_reply.x(7 downto 0);
            su8_green <= v_reply.y;
            su8_blue <= not v_reply.x(7 downto 0);
            if (s_initialize = '1' or s_game_ready = '0') then
                v_replies := (others => C_EMPTY_REPLY);
                s_rgb_valid <= '0';
            end if;
        end if;
    end process;
    monitor : process
        type t_metadata is record
            enable, active, hsync, vsync, hblank, vblank : std_logic;
            x, y : natural;
        end record;
        type t_pipeline is array (0 to 4) of t_metadata;
        constant C_EMPTY : t_metadata := ('0', '0', '0', '0', '1', '1', 0, 0);
        variable v_pipeline : t_pipeline := (others => C_EMPTY);
        variable v_expected, v_new : t_metadata;
        variable vint_x, vint_y, vint_divider : natural := 0;
    begin
        wait until rising_edge(s_clk);
        if (s_initialize = '1') then
            vint_x := 0;
            vint_y := 0;
            vint_divider := 0;
            v_pipeline := (others => C_EMPTY);
        else
            assert (su9_horizontal = vint_x and su9_vertical = vint_y)
                report "Game readiness restarted or stalled the physical beam" severity failure;
            v_expected := v_pipeline(4);
            for vint_stage in 4 downto 1 loop
                v_pipeline(vint_stage) := v_pipeline(vint_stage - 1);
            end loop;
            v_new := (logic(vint_divider = 6), logic(vint_x < 288 and vint_y < 216 and s_armed = '1' and s_game_ready = '1'),
                logic(vint_x < 352 or vint_x >= 392), logic(vint_y < 232 or vint_y >= 240),
                logic(vint_x >= 288), logic(vint_y >= 216), 0, 0);
            if (vint_x < 288) then
                v_new.x := vint_x + 8;
            end if;
            if (vint_y < 216) then
                v_new.y := vint_y;
            end if;
            v_pipeline(0) := v_new;
            if (vint_divider = 6) then
                vint_divider := 0;
                if (vint_x = 431) then
                    vint_x := 0;
                    if (vint_y = 255) then
                        vint_y := 0;
                    else
                        vint_y := vint_y + 1;
                    end if;
                else
                    vint_x := vint_x + 1;
                end if;
            else
                vint_divider := vint_divider + 1;
            end if;
            wait for 1 ns;
            assert (s_output_enable = v_expected.enable)
                report "Scanout output stalled or changed its five-clock latency" severity failure;
            if (v_expected.enable = '1') then
                assert (s_active = v_expected.active and s_hsync = v_expected.hsync and s_vsync = v_expected.vsync and
                    s_hblank = v_expected.hblank and s_vblank = v_expected.vblank and
                    su9_output_x = v_expected.x and su8_output_y = v_expected.y)
                    report "Continuous sync/blanking/coordinates changed during reset or late rendering" severity failure;
                if (sint_phase = 0 or sint_phase = 3) then
                    if (v_expected.active = '1') then
                        assert (su8_output_red = v_expected.x mod 256 and su8_output_green = v_expected.y and
                            su8_output_blue = 255 - v_expected.x mod 256 and s_underflow = '0')
                            report "Clean scanout RGB, row ownership or deadline mismatch" severity failure;
                        if (sint_phase = 0) then
                            sint_clean_pixels <= sint_clean_pixels + 1;
                        else
                            sint_recovered_pixels <= sint_recovered_pixels + 1;
                        end if;
                    else
                        assert (su8_output_red = 0 and su8_output_green = 0 and su8_output_blue = 0)
                            report "Blank scanout pixel was not black" severity failure;
                    end if;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
    begin
        cycles(3);
        s_initialize <= '0';
        s_game_ready <= '1';
        wait until sint_clean_pixels = 62208 for 30 ms;
        assert (sint_clean_pixels = 62208 and s_underflow = '0')
            report "A complete clean frame did not scan out" severity failure;
        wait until falling_edge(s_clk);
        sint_phase <= 1;
        sint_render_delay <= 4000;
        wait until s_underflow = '1' for 15 ms;
        assert (s_underflow = '1') report "Over-budget rendering did not flag a missed line" severity failure;
        cycles(14);
        assert (su8_output_red = 0 and su8_output_green = 0 and su8_output_blue = 0)
            report "Late row displayed stale pixels" severity failure;
        sint_phase <= 2;
        s_game_ready <= '0';
        cycles(8);
        assert (s_underflow = '0' and s_armed = '0') report "Game reset did not flush ownership/faults" severity failure;
        cycles(600);
        sint_render_delay <= 2557;
        s_game_ready <= '1';
        sint_phase <= 3;
        wait until sint_recovered_pixels = 62208 for 30 ms;
        assert (sint_recovered_pixels = 62208 and s_underflow = '0')
            report "Scanout failed to recover after game readiness returned" severity failure;
        report "SCANOUT_PASS: 124416 RGB pixels, 2557-cycle rows, deliberate deadline miss, continuous sync and reset/recovery";
        std.env.finish;
        wait;
    end process;
    process
    begin
        wait for 50 ms;
        assert false report "Continuous scanout test timeout" severity failure;
    end process;
end architecture;
