-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity scanline_scheduler_tb is
end entity;

architecture test of scanline_scheduler_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_frame_prepare, s_line_start, s_handoff, s_next_visible : std_logic := '0';
    signal su8_y, su8_next_y : unsigned(7 downto 0) := (others => '0');
    signal s_render_valid, s_render_ready, s_render_bank, s_render_done : std_logic;
    signal su9_render_y : unsigned(8 downto 0);
    signal s_display_bank, s_display_valid, s_armed, s_underflow : std_logic;
    signal s_mock_busy, s_block_ready : std_logic := '0';
    signal sint_render_delay : natural := 8;
    type t_bank_tags is array (0 to 1) of unsigned(8 downto 0);
    signal su9_bank_tags : t_bank_tags := (others => (others => '1'));
    signal sint_accepted : natural := 0;
    function bank_index(v_bank : std_logic) return natural is
    begin
        if (v_bank = '1') then
            return 1;
        end if;
        return 0;
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_render_ready <= not s_mock_busy and not s_block_ready;
    dut : entity work.rabbitpunch_scanline_scheduler
        generic map (
            sint_VISIBLE_LINES => 4
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_frame_prepare => s_frame_prepare,
            i_visible_line_start => s_line_start,
            iu8_visible_line_y => su8_y,
            i_line_handoff => s_handoff,
            i_next_line_visible => s_next_visible,
            iu8_next_line_y => su8_next_y,
            o_render_valid => s_render_valid,
            i_render_ready => s_render_ready,
            o_render_bank => s_render_bank,
            ou9_render_y => su9_render_y,
            i_render_done => s_render_done,
            o_display_bank => s_display_bank,
            o_display_valid => s_display_valid,
            o_armed => s_armed,
            o_underflow => s_underflow
        );
    renderer : process(s_clk)
        variable vint_remaining : natural := 0;
        variable v_bank : std_logic;
        variable vu9_y : unsigned(8 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_render_done <= '0';
            if (s_initialize = '1') then
                s_mock_busy <= '0';
                su9_bank_tags <= (others => (others => '1'));
            elsif (s_mock_busy = '1') then
                if (vint_remaining = 0) then
                    su9_bank_tags(bank_index(v_bank)) <= vu9_y;
                    s_render_done <= '1';
                    s_mock_busy <= '0';
                else
                    vint_remaining := vint_remaining - 1;
                end if;
            elsif (s_render_valid = '1' and s_render_ready = '1') then
                assert (s_display_valid = '0' or s_render_bank /= s_display_bank)
                    report "Renderer wrote the currently displayed bank" severity failure;
                v_bank := s_render_bank;
                vu9_y := su9_render_y;
                vint_remaining := sint_render_delay;
                s_mock_busy <= '1';
                sint_accepted <= sint_accepted + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable v_previous_bank, v_held_bank : std_logic := '0';
        variable vu9_held_y : unsigned(8 downto 0);
        procedure pulse(signal s_event : out std_logic) is
        begin
            wait until falling_edge(s_clk);
            s_event <= '1';
            wait until falling_edge(s_clk);
            s_event <= '0';
        end procedure;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure handoff(v_visible : std_logic; vint_y : natural) is
        begin
            wait until falling_edge(s_clk);
            s_next_visible <= v_visible;
            su8_next_y <= to_unsigned(vint_y, 8);
            s_handoff <= '1';
            wait until falling_edge(s_clk);
            s_handoff <= '0';
            wait for 1 ns;
        end procedure;
    begin
        cycles(2);
        wait until falling_edge(s_clk);
        s_initialize <= '0';
        handoff('1', 0);
        assert (s_armed = '0' and s_display_valid = '0' and s_underflow = '0')
            report "Unarmed startup falsely displayed a bank or flagged underflow" severity failure;
        for vint_frame in 0 to 1 loop
            handoff('0', 0);
            if (vint_frame = 0) then
                s_block_ready <= '1';
            end if;
            pulse(s_frame_prepare);
            if (vint_frame = 0) then
                v_held_bank := s_render_bank;
                vu9_held_y := su9_render_y;
                for vint_cycle in 1 to 7 loop
                    cycles(1);
                    assert (s_render_valid = '1' and s_render_bank = v_held_bank and su9_render_y = vu9_held_y)
                        report "Render request changed while backpressured" severity failure;
                end loop;
                wait until falling_edge(s_clk);
                s_block_ready <= '0';
            end if;
            cycles(24);
            for vint_y in 0 to 3 loop
                handoff('1', vint_y);
                assert (s_display_valid = '1' and su9_bank_tags(bank_index(s_display_bank)) = vint_y)
                    report "Handoff selected an incomplete or wrong row" severity failure;
                assert (s_display_bank /= v_previous_bank)
                    report "Sequential rows did not alternate banks" severity failure;
                v_previous_bank := s_display_bank;
                su8_y <= to_unsigned(vint_y, 8);
                pulse(s_line_start);
                cycles(40);
                assert (s_display_valid = '1' and s_display_bank = v_previous_bank and s_underflow = '0')
                    report "Active display bank changed during rendering" severity failure;
            end loop;
        end loop;
        assert (sint_accepted = 8) report "Last visible row queued an unnecessary render" severity failure;
        -- Deliberately miss row zero. Late completion cannot switch mid-line.
        handoff('0', 0);
        sint_render_delay <= 200;
        pulse(s_frame_prepare);
        cycles(20);
        handoff('1', 0);
        assert (s_display_valid = '0' and s_underflow = '1')
            report "Missed row deadline reused stale pixels" severity failure;
        cycles(240);
        assert (s_display_valid = '0') report "Late render switched the displayed row mid-line" severity failure;
        sint_render_delay <= 8;
        handoff('0', 0);
        pulse(s_frame_prepare);
        cycles(24);
        handoff('1', 0);
        assert (s_display_valid = '1' and su9_bank_tags(bank_index(s_display_bank)) = 0 and s_underflow = '1')
            report "Rendering did not recover or erased the sticky underflow" severity failure;
        pulse(s_initialize);
        cycles(1);
        assert (s_armed = '0' and s_render_valid = '0' and s_display_valid = '0' and s_underflow = '0')
            report "Initialization did not flush line ownership" severity failure;
        -- Completion arriving on the handoff edge must be eligible immediately.
        pulse(s_frame_prepare);
        wait until s_render_done = '1';
        handoff('1', 0);
        assert (s_display_valid = '1' and su9_bank_tags(bank_index(s_display_bank)) = 0 and s_underflow = '0')
            report "Same-edge completion was lost at handoff" severity failure;
        -- Flush a queued request without letting it reach the renderer.
        s_block_ready <= '1';
        pulse(s_frame_prepare);
        cycles(3);
        assert (s_render_valid = '1') report "Queued initialization case was not exercised" severity failure;
        pulse(s_initialize);
        cycles(1);
        assert (s_render_valid = '0' and s_display_valid = '0' and s_armed = '0')
            report "Initialization retained queued ownership" severity failure;
        s_block_ready <= '0';
        pulse(s_frame_prepare);
        cycles(3);
        assert (s_mock_busy = '1') report "Active initialization case was not exercised" severity failure;
        pulse(s_initialize);
        cycles(16);
        assert (s_render_valid = '0' and s_display_valid = '0' and s_armed = '0' and s_underflow = '0')
            report "Initialization retained a rendering bank or accepted late completion" severity failure;
        report "SCANLINE_SCHEDULER_PASS: one-row-ahead banks, backpressure, blank startup, missed-deadline blanking and recovery";
        std.env.finish;
        wait;
    end process;
    process
    begin
        wait for 100 us;
        assert false report "Scanline scheduler test timeout" severity failure;
    end process;
end architecture;
