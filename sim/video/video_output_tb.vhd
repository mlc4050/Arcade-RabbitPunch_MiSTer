-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity video_output_tb is
end entity;

architecture test of video_output_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_clear_underflow : std_logic := '0';
    signal s_enable, s_active, s_hsync, s_vsync, s_hblank, s_vblank : std_logic := '0';
    signal s_request, s_ready, s_valid, s_error : std_logic := '0';
    signal su9_x, su9_rgb_x, su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_y, su8_rgb_y, su8_output_y : unsigned(7 downto 0) := (others => '0');
    signal su8_red, su8_green, su8_blue, su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0);
    signal s_output_enable, s_output_active, s_output_hsync, s_output_vsync, s_output_hblank, s_output_vblank, s_underflow : std_logic;
    type t_reply is record
        valid, error : std_logic;
        x : unsigned(8 downto 0);
        y : unsigned(7 downto 0);
    end record;
    type t_replies is array (natural range <>) of t_reply;
    constant EMPTY_REPLY : t_reply := ('0', '0', (others => '0'), (others => '0'));
begin
    s_clk <= not s_clk after 5 ns;
    s_ready <= '0' when su8_y = 1 and su9_x = 5 else '1';
    dut : entity work.rabbitpunch_video_output
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_clear_underflow => s_clear_underflow,
            i_pixel_enable => s_enable,
            i_active => s_active,
            i_hsync => s_hsync,
            i_vsync => s_vsync,
            i_hblank => s_hblank,
            i_vblank => s_vblank,
            iu9_pixel_x => su9_x,
            iu8_pixel_y => su8_y,
            o_pixel_request => s_request,
            i_pixel_ready => s_ready,
            i_rgb_valid => s_valid,
            i_rgb_error => s_error,
            iu9_rgb_x => su9_rgb_x,
            iu8_rgb_y => su8_rgb_y,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            o_pixel_enable => s_output_enable,
            o_active => s_output_active,
            o_hsync => s_output_hsync,
            o_vsync => s_output_vsync,
            o_hblank => s_output_hblank,
            o_vblank => s_output_vblank,
            ou9_pixel_x => su9_output_x,
            ou8_pixel_y => su8_output_y,
            ou8_red => su8_output_red,
            ou8_green => su8_output_green,
            ou8_blue => su8_output_blue,
            o_underflow => s_underflow
        );
    -- Behavioral renderer contract: each accepted coordinate returns after
    -- exactly four edges, with independently injected missing/tag/error faults.
    renderer : process(s_clk)
        variable v_replies : t_replies(0 to 3) := (others => EMPTY_REPLY);
        variable v_new, v_reply : t_reply;
    begin
        if (rising_edge(s_clk)) then
            v_reply := v_replies(3);
            for vint_stage in 3 downto 1 loop
                v_replies(vint_stage) := v_replies(vint_stage - 1);
            end loop;
            v_new := (s_request and s_ready, '0', su9_x, su8_y);
            if (su8_y = 1) then
                case to_integer(su9_x) is
                    when 7 => v_new.valid := '0';
                    when 10 => v_new.x := su9_x + 1;
                    when 17 => v_new.error := v_new.valid;
                    when others => null;
                end case;
            end if;
            v_replies(0) := v_new;
            s_valid <= v_reply.valid;
            s_error <= v_reply.error;
            su9_rgb_x <= v_reply.x;
            su8_rgb_y <= v_reply.y;
            su8_red <= v_reply.x(7 downto 0);
            su8_green <= v_reply.y;
            su8_blue <= not v_reply.x(7 downto 0);
            if (s_reset = '1') then
                v_replies := (others => EMPTY_REPLY);
                s_valid <= '0';
                s_error <= '0';
            end if;
        end if;
    end process;
    stimulus : process
        type t_expected is record
            enable, active, hsync, vsync, hblank, vblank : std_logic;
            x, y : natural;
        end record;
        type t_expectations is array (0 to 209) of t_expected;
        variable v_expected : t_expectations;
        variable v_item : t_expected;
        variable v_fault, v_seen_fault : boolean;
        procedure reset_output is
        begin
            wait until falling_edge(s_clk);
            s_reset <= '1';
            s_enable <= '0';
            for vint_cycle in 1 to 3 loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
                assert (s_output_enable = '0' and s_output_active = '0' and s_output_hblank = '1' and
                    s_output_vblank = '1' and s_underflow = '0' and su8_output_red = 0)
                    report "Video output reset did not flush pixel/sync/fault state" severity failure;
            end loop;
            wait until falling_edge(s_clk);
            s_reset <= '0';
        end procedure;
    begin
        for vint_phase in 0 to 1 loop
            reset_output;
            v_seen_fault := false;
            for vint_step in 0 to 209 loop
                wait until falling_edge(s_clk);
                v_item := ('0', '0', '0', '0', '0', '0', vint_step, vint_phase);
                if (vint_step < 200 and vint_step mod 3 /= 0) then
                    v_item.enable := '1';
                end if;
                if (vint_step mod 16 < 12) then
                    v_item.active := '1';
                end if;
                if (vint_step mod 8 < 3) then
                    v_item.hsync := '1';
                end if;
                if (vint_step mod 37 < 13) then
                    v_item.vsync := '1';
                end if;
                v_item.hblank := not v_item.active;
                v_item.vblank := v_item.vsync;
                v_expected(vint_step) := v_item;
                s_enable <= v_item.enable;
                s_active <= v_item.active;
                s_hsync <= v_item.hsync;
                s_vsync <= v_item.vsync;
                s_hblank <= v_item.hblank;
                s_vblank <= v_item.vblank;
                su9_x <= to_unsigned(v_item.x, 9);
                su8_y <= to_unsigned(v_item.y, 8);
                wait for 1 ns;
                assert (s_request = (v_item.enable and v_item.active)) report "Blank pixels generated RGB reads" severity failure;
                wait until rising_edge(s_clk);
                wait for 1 ns;
                if (vint_step < 5) then
                    assert (s_output_enable = '0') report "Output pixel arrived before fixed delay" severity failure;
                else
                    v_item := v_expected(vint_step - 5);
                    assert (s_output_enable = v_item.enable) report "Pixel-enable cadence/latency changed" severity failure;
                    if (v_item.enable = '1') then
                        assert (s_output_active = v_item.active and s_output_hsync = v_item.hsync and s_output_vsync = v_item.vsync and
                            s_output_hblank = v_item.hblank and s_output_vblank = v_item.vblank and
                            su9_output_x = v_item.x and su8_output_y = v_item.y)
                            report "Sync/blanking/coordinate alignment mismatch" severity failure;
                        v_fault := vint_phase = 1 and (v_item.x = 5 or v_item.x = 7 or v_item.x = 10 or v_item.x = 17);
                        if (v_item.active = '1' and not v_fault) then
                            assert (su8_output_red = v_item.x and su8_output_green = v_item.y and su8_output_blue = 255 - v_item.x)
                                report "Valid RGB changed at output" severity failure;
                        else
                            assert (su8_output_red = 0 and su8_output_green = 0 and su8_output_blue = 0)
                                report "Missing/invalid/blank pixel did not go black" severity failure;
                        end if;
                        v_seen_fault := v_seen_fault or (v_fault and v_item.active = '1');
                    end if;
                    if (v_seen_fault) then
                        assert (s_underflow = '1') report "Missing/tag/backpressure fault was not retained" severity failure;
                    else
                        assert (s_underflow = '0') report "Clean pixel stream raised underflow" severity failure;
                    end if;
                end if;
            end loop;
        end loop;
        wait until falling_edge(s_clk);
        s_clear_underflow <= '1';
        s_enable <= '1';
        s_active <= '0';
        s_hsync <= '1';
        s_vsync <= '0';
        s_hblank <= '1';
        s_vblank <= '0';
        wait until rising_edge(s_clk);
        wait for 1 ns;
        assert (s_underflow = '0') report "Fault-only clear did not clear sticky underflow" severity failure;
        wait until falling_edge(s_clk);
        s_clear_underflow <= '0';
        for vint_cycle in 1 to 8 loop
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end loop;
        assert (s_output_enable = '1' and s_output_hsync = '1' and s_output_vsync = '0' and
            s_output_hblank = '1' and s_output_vblank = '0' and s_underflow = '0')
            report "Fault clear disturbed the running raster metadata" severity failure;
        reset_output;
        report "VIDEO_OUTPUT_PASS slots=420 fixed_delay=5 sync_blanking=checked missing_tag_error_backpressure=checked reset_flush=checked";
        finish;
        wait;
    end process;
end architecture;
