-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity view_flip_tb is
end entity;

architecture test of view_flip_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_game_ready : std_logic := '0';
    signal s_request_flip, s_frame_prepare : std_logic := '0';
    signal s_line_valid, s_line_ready, s_line_done : std_logic := '0';
    signal s_pixel_valid, s_pixel_ready, s_rgb_valid : std_logic := '0';
    signal s_applied_flip : std_logic;
    signal su9_line_y, su9_pixel_x, su9_source_rgb_x : unsigned(8 downto 0) := (others => '0');
    signal su8_pixel_y, su8_source_rgb_y : unsigned(7 downto 0) := (others => '0');
    signal su9_source_line_y, su9_source_pixel_x, su9_rgb_x : unsigned(8 downto 0);
    signal su8_source_pixel_y, su8_rgb_y : unsigned(7 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_view_flip
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_ready => s_game_ready,
            i_request_flip => s_request_flip,
            i_frame_prepare => s_frame_prepare,
            i_line_valid => s_line_valid,
            i_line_ready => s_line_ready,
            i_line_done => s_line_done,
            i_pixel_valid => s_pixel_valid,
            i_pixel_ready => s_pixel_ready,
            i_rgb_valid => s_rgb_valid,
            iu9_line_y => su9_line_y,
            ou9_source_line_y => su9_source_line_y,
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            ou9_source_pixel_x => su9_source_pixel_x,
            ou8_source_pixel_y => su8_source_pixel_y,
            iu9_source_rgb_x => su9_source_rgb_x,
            iu8_source_rgb_y => su8_source_rgb_y,
            ou9_rgb_x => su9_rgb_x,
            ou8_rgb_y => su8_rgb_y,
            o_applied_flip => s_applied_flip
        );
    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure frame_prepare is
        begin
            s_frame_prepare <= '1';
            tick;
            s_frame_prepare <= '0';
            tick;
        end procedure;
        procedure check_coordinates(constant CBOOL_FLIP : boolean) is
            variable vint_source_x, vint_source_y : natural;
        begin
            for vint_y in 0 to 215 loop
                for vint_x in 8 to 295 loop
                    if (CBOOL_FLIP) then
                        vint_source_x := 303 - vint_x;
                        vint_source_y := 215 - vint_y;
                    else
                        vint_source_x := vint_x;
                        vint_source_y := vint_y;
                    end if;
                    su9_line_y <= to_unsigned(vint_y, 9);
                    su9_pixel_x <= to_unsigned(vint_x, 9);
                    su8_pixel_y <= to_unsigned(vint_y, 8);
                    su9_source_rgb_x <= to_unsigned(vint_source_x, 9);
                    su8_source_rgb_y <= to_unsigned(vint_source_y, 8);
                    wait for 1 ns;
                    assert (su9_source_line_y = vint_source_y and
                        su9_source_pixel_x = vint_source_x and su8_source_pixel_y = vint_source_y)
                        report "Wrong source coordinate transform" severity failure;
                    assert (su9_rgb_x = vint_x and su8_rgb_y = vint_y)
                        report "Wrong inverse RGB tag transform" severity failure;
                end loop;
            end loop;
        end procedure;
    begin
        tick;
        assert (s_applied_flip = '0') severity failure;
        s_initialize <= '0';
        s_game_ready <= '1';
        tick;
        check_coordinates(false);
        s_request_flip <= '1';
        tick;
        assert (s_applied_flip = '0') report "Changed within a frame" severity failure;
        frame_prepare;
        assert (s_applied_flip = '1') severity failure;
        check_coordinates(true);

        s_request_flip <= '0';
        s_line_valid <= '1';
        frame_prepare;
        assert (s_applied_flip = '1') report "Changed with a pending render" severity failure;
        s_line_ready <= '1';
        tick;
        s_line_valid <= '0';
        s_line_ready <= '0';
        frame_prepare;
        assert (s_applied_flip = '1') report "Changed during rendering" severity failure;
        s_line_done <= '1';
        tick;
        s_line_done <= '0';
        frame_prepare;
        assert (s_applied_flip = '0') severity failure;

        s_request_flip <= '1';
        s_pixel_valid <= '1';
        frame_prepare;
        assert (s_applied_flip = '0') report "Changed with a pending pixel" severity failure;
        s_pixel_ready <= '1';
        tick;
        s_pixel_valid <= '0';
        s_pixel_ready <= '0';
        frame_prepare;
        assert (s_applied_flip = '0') report "Changed with an outstanding RGB response" severity failure;
        -- A response and new acceptance on one edge must retain the busy state.
        s_rgb_valid <= '1';
        s_pixel_valid <= '1';
        s_pixel_ready <= '1';
        tick;
        s_rgb_valid <= '0';
        s_pixel_valid <= '0';
        s_pixel_ready <= '0';
        frame_prepare;
        assert (s_applied_flip = '0') report "Lost back-to-back pixel transaction" severity failure;
        s_rgb_valid <= '1';
        s_frame_prepare <= '1';
        tick;
        assert (s_applied_flip = '0') report "Changed on the final old-orientation RGB response" severity failure;
        s_rgb_valid <= '0';
        s_frame_prepare <= '0';
        frame_prepare;
        assert (s_applied_flip = '1') severity failure;

        s_line_valid <= '1';
        s_line_ready <= '1';
        tick;
        s_line_done <= '1';
        tick;
        s_line_valid <= '0';
        s_line_ready <= '0';
        s_line_done <= '0';
        s_request_flip <= '0';
        frame_prepare;
        assert (s_applied_flip = '1') report "Lost back-to-back render transaction" severity failure;
        -- A game reload can abandon transactions; it must clear both busy flags.
        s_game_ready <= '0';
        tick;
        assert (s_applied_flip = '0') report "Reload retained old orientation" severity failure;
        s_game_ready <= '1';
        s_request_flip <= '1';
        frame_prepare;
        assert (s_applied_flip = '1') severity failure;
        s_initialize <= '1';
        tick;
        assert (s_applied_flip = '0') report "Initialization did not clear orientation" severity failure;
        report "VIEW_FLIP_PASS coordinates=124416 pending/render/pixel/back-to-back/reload guards";
        std.env.finish;
        wait;
    end process;
end architecture;
