-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One-row-ahead ownership for the existing two tile/sprite line banks.
-- Handoff is at the final pixel of the preceding physical line, so bank
-- selection settles before the next visible pixel. No pixel memory is added.
entity rabbitpunch_scanline_scheduler is
    generic (
        GINT_VISIBLE_LINES : positive := 216
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_frame_prepare : in std_logic;
        i_visible_line_start : in std_logic;
        iu8_visible_line_y : in unsigned(7 downto 0);
        i_line_handoff : in std_logic;
        i_next_line_visible : in std_logic;
        iu8_next_line_y : in unsigned(7 downto 0);
        o_render_valid : out std_logic;
        i_render_ready : in std_logic;
        o_render_bank : out std_logic;
        ou9_render_y : out unsigned(8 downto 0);
        i_render_done : in std_logic;
        o_display_bank : out std_logic;
        o_display_valid : out std_logic;
        o_armed : out std_logic;
        o_underflow : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_scanline_scheduler is
    type t_state is (STATE_IDLE, STATE_REQUEST, STATE_RENDER);
    signal styp_state : t_state := STATE_IDLE;
    type t_line_tags is array (0 to 1) of unsigned(7 downto 0);
    signal su8_ready_y : t_line_tags := (others => (others => '0'));
    signal su2_ready_banks : unsigned(1 downto 0) := "00";
    signal su8_render_y : unsigned(7 downto 0) := (others => '0');
    signal s_render_bank, s_display_bank, s_display_valid, s_armed, s_underflow : std_logic := '0';
    function bank_index(v_bank : std_logic) return natural is
    begin
        if (v_bank = '1') then
            return 1;
        end if;
        return 0;
    end function;
begin
    assert (GINT_VISIBLE_LINES <= 256) report "Visible line count exceeds render coordinate width" severity failure;
    o_render_valid <= '1' when styp_state = STATE_REQUEST and i_initialize = '0' else '0';
    o_render_bank <= s_render_bank;
    ou9_render_y <= resize(su8_render_y, 9);
    o_display_bank <= s_display_bank;
    o_display_valid <= s_display_valid and not i_initialize;
    o_armed <= s_armed and not i_initialize;
    o_underflow <= s_underflow;

    ownership : process(i_clk)
        variable vu2_ready_banks : unsigned(1 downto 0);
        variable vu8_ready_y : t_line_tags;
        variable v_display_bank, v_display_valid : std_logic;
        variable v_available, v_found, v_prepare : boolean;
        variable vu8_prepare_y : unsigned(7 downto 0);
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                styp_state <= STATE_IDLE;
                su2_ready_banks <= "00";
                su8_ready_y <= (others => (others => '0'));
                su8_render_y <= (others => '0');
                s_render_bank <= '0';
                s_display_bank <= '0';
                s_display_valid <= '0';
                s_armed <= '0';
                s_underflow <= '0';
            else
                vu2_ready_banks := su2_ready_banks;
                vu8_ready_y := su8_ready_y;
                v_display_bank := s_display_bank;
                v_display_valid := s_display_valid;
                v_available := styp_state = STATE_IDLE;
                case styp_state is
                    when STATE_IDLE =>
                        null;
                    when STATE_REQUEST =>
                        if (i_render_ready = '1') then
                            assert (s_display_valid = '0' or s_render_bank /= s_display_bank)
                                report "Renderer accepted the active display bank" severity failure;
                            styp_state <= STATE_RENDER;
                        end if;
                    when STATE_RENDER =>
                        if (i_render_done = '1') then
                            vu2_ready_banks(bank_index(s_render_bank)) := '1';
                            vu8_ready_y(bank_index(s_render_bank)) := su8_render_y;
                            styp_state <= STATE_IDLE;
                            v_available := true;
                        end if;
                end case;

                if (i_line_handoff = '1') then
                    v_display_valid := '0';
                    if (i_next_line_visible = '1' and s_armed = '1') then
                        v_found := false;
                        for vint_bank in 0 to 1 loop
                            if (not v_found and vu2_ready_banks(vint_bank) = '1' and
                                vu8_ready_y(vint_bank) = iu8_next_line_y and iu8_next_line_y < GINT_VISIBLE_LINES) then
                                v_found := true;
                                v_display_valid := '1';
                                if (vint_bank = 0) then
                                    v_display_bank := '0';
                                else
                                    v_display_bank := '1';
                                end if;
                                vu2_ready_banks(vint_bank) := '0';
                            end if;
                        end loop;
                        if (not v_found) then
                            s_underflow <= '1';
                        end if;
                    end if;
                end if;

                v_prepare := false;
                vu8_prepare_y := (others => '0');
                if (i_frame_prepare = '1') then
                    s_armed <= '1';
                    v_prepare := true;
                elsif (i_visible_line_start = '1' and s_armed = '1' and
                    iu8_visible_line_y < GINT_VISIBLE_LINES - 1) then
                    vu8_prepare_y := iu8_visible_line_y + 1;
                    v_prepare := true;
                end if;
                if (v_prepare) then
                    if (v_available) then
                        s_render_bank <= not v_display_bank;
                        su8_render_y <= vu8_prepare_y;
                        vu2_ready_banks(bank_index(not v_display_bank)) := '0';
                        styp_state <= STATE_REQUEST;
                    else
                        -- A missed deadline drops the row; it never stalls sync
                        -- or reuses an unverified bank as the requested row.
                        s_underflow <= '1';
                    end if;
                end if;
                su2_ready_banks <= vu2_ready_banks;
                su8_ready_y <= vu8_ready_y;
                s_display_bank <= v_display_bank;
                s_display_valid <= v_display_valid;
            end if;
        end if;
    end process;
end architecture;
