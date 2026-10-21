-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;

entity state_semantics_tb is
end entity;

architecture test of state_semantics_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_abort, s_byte, s_finish : std_logic := '0';
    signal s_ready, s_active, s_finished, s_valid : std_logic;
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal su4_error : unsigned(3 downto 0);
    function F_BYTE(vint_address, vint_case : natural) return unsigned is
        variable vint_word, vint_lane : natural;
        variable vu32_word : unsigned(31 downto 0);
        variable vu256_t80 : unsigned(255 downto 0) := (others => '0');
        variable vu512_board : unsigned(511 downto 0) := (others => '0');
    begin
        if (vint_address < CINT_M68K_BASE) then
            return to_unsigned(vint_address mod 256, 8);
        elsif (vint_address < CINT_T80_BASE) then
            vint_word := (vint_address - CINT_M68K_BASE)/4;
            vint_lane := (vint_address - CINT_M68K_BASE) mod 4;
            vu32_word := (others => '0');
            case vint_word is
                when 18 => vu32_word := x"000FF7FA";
                when 19 => vu32_word := x"00002000";
                when 20 => vu32_word := x"00000400";
                when others => null;
            end case;
            if (vint_case = 1 and vint_word = 19) then
                vu32_word := x"00002800";
            elsif (vint_case = 2 and vint_word = 20) then
                vu32_word := x"00000401";
            elsif (vint_case = 3 and vint_word = 18) then
                vu32_word := x"000BFFFC";
            elsif (vint_case = 4 and vint_word = 18) then
                vu32_word := x"000FF7FB";
            elsif (vint_case = 5 and vint_word = 16) then
                vu32_word := x"00000001";
            elsif (vint_case = 6 and vint_word = 22) then
                vu32_word := x"00000002";
            elsif (vint_case = 25) then
                case vint_word is
                    when 18 => vu32_word := x"AB0FC002";
                    when 19 => vu32_word := x"0000A71F";
                    when 20 => vu32_word := x"FFFFFFFE";
                    when 22 => vu32_word := x"00000001";
                    when others => null;
                end case;
            end if;
            return vu32_word(8*vint_lane + 7 downto 8*vint_lane);
        elsif (vint_address < CINT_BOARD_BASE) then
            if (vint_case = 7) then
                vu256_t80(209 downto 208) := "11";
            elsif (vint_case = 8) then
                vu256_t80(255) := '1';
            elsif (vint_case = 25) then
                vu256_t80(237 downto 0) := (others => '1');
                vu256_t80(209 downto 208) := "10";
            end if;
            vint_lane := vint_address - CINT_T80_BASE;
            return vu256_t80(8*vint_lane + 7 downto 8*vint_lane);
        elsif (vint_address < CINT_FM_BASE) then
            case vint_case is
                when 9 => vu512_board(206) := '1';
                when 10 => vu512_board(228) := '1';
                when 11 => vu512_board(258 downto 256) := to_unsigned(7, 3);
                when 12 => vu512_board(264 downto 259) := to_unsigned(35, 6);
                when 13 => vu512_board(270 downto 265) := to_unsigned(35, 6);
                when 14 => vu512_board(280 downto 271) := to_unsigned(875, 10);
                when 15 => vu512_board(282) := '1';
                when 16 => vu512_board(296 downto 288) := to_unsigned(432, 9);
                when 17 => vu512_board(305 downto 297) := to_unsigned(256, 9);
                when 18 => vu512_board(321 downto 320) := "11";
                when 19 => vu512_board(333) := '1';
                when 20 => vu512_board(511) := '1';
                when 26 => vu512_board(306) := '1';
                when 28 => vu512_board(354 downto 352) := "111";
                when 29 => vu512_board(353) := '1';
                when 30 => vu512_board(355) := '1';
                when 31 => vu512_board(354) := '1';
                when 25 =>
                    vu512_board(205 downto 0) := (others => '1');
                    vu512_board(227 downto 224) := (others => '1');
                    vu512_board(258 downto 256) := to_unsigned(6, 3);
                    vu512_board(264 downto 259) := to_unsigned(34, 6);
                    vu512_board(270 downto 265) := to_unsigned(34, 6);
                    vu512_board(280 downto 271) := to_unsigned(874, 10);
                    vu512_board(281) := '1';
                    vu512_board(296 downto 288) := to_unsigned(431, 9);
                    vu512_board(305 downto 297) := to_unsigned(255, 9);
                    vu512_board(332 downto 320) := (others => '1');
                    vu512_board(321 downto 320) := "10";
                    vu512_board(351 downto 336) := (others => '1');
                when others => null;
            end case;
            vint_lane := vint_address - CINT_BOARD_BASE;
            return vu512_board(8*vint_lane + 7 downto 8*vint_lane);
        elsif (vint_case = 21 and vint_address = CINT_ADPCM_BASE - 2) then
            return x"01";
        elsif (vint_case = 32 and vint_address = CINT_BODY_BYTES - 1) then
            return x"20";
        elsif (vint_case = 33 and vint_address = CINT_BODY_BYTES - 1) then
            return x"1F";
        end if;
        return x"00";
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    validator : entity work.rabbitpunch_state_semantics
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_abort => s_abort,
            i_byte_valid => s_byte,
            o_byte_ready => s_ready,
            iu8_byte_data => su8_data,
            i_finish => s_finish,
            o_active => s_active,
            o_finished => s_finished,
            o_valid => s_valid,
            ou4_error => su4_error
        );
    stimulus : process
        variable vint_length : positive;
        variable vu4_expected : unsigned(3 downto 0);
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        assert (CINT_BODY_BYTES = 107216 and CINT_IMAGE_BYTES = 107280) severity failure;
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        for vint_case in 0 to 33 loop
            s_start <= '1';
            cycles;
            s_start <= '0';
            vint_length := CINT_BODY_BYTES;
            if (vint_case = 22) then
                vint_length := CINT_BODY_BYTES - 1;
            elsif (vint_case = 24) then
                vint_length := 128;
            end if;
            for vint_byte in 0 to vint_length - 1 loop
                if (vint_byte mod 251 = 0) then
                    s_byte <= '0';
                    cycles(2);
                end if;
                assert (s_ready = '1') severity failure;
                su8_data <= F_BYTE(vint_byte, vint_case);
                s_byte <= '1';
                if (vint_byte = vint_length - 1) then
                    if (vint_case = 24) then
                        s_abort <= '1';
                    elsif (vint_case /= 23) then
                        s_finish <= '1';
                    end if;
                end if;
                cycles;
            end loop;
            if (vint_case = 23) then
                s_finish <= '1';
                cycles;
            end if;
            s_byte <= '0';
            s_finish <= '0';
            s_abort <= '0';
            vu4_expected := (others => '0');
            case vint_case is
                when 1 to 6 => vu4_expected := to_unsigned(2, 4);
                when 7 to 8 => vu4_expected := to_unsigned(3, 4);
                when 9 to 20 | 26 | 29 | 30 => vu4_expected := to_unsigned(4, 4);
                when 21 => vu4_expected := to_unsigned(5, 4);
                when 22 => vu4_expected := to_unsigned(7, 4);
                when 23 => vu4_expected := to_unsigned(8, 4);
                when 24 => vu4_expected := to_unsigned(6, 4);
                when 32 => vu4_expected := to_unsigned(9, 4);
                when others => null;
            end case;
            assert (s_finished = '1' and s_active = '0' and su4_error = vu4_expected)
                report "Wrong body semantics result case=" & integer'image(vint_case) &
                " error=" & to_hstring(su4_error) severity failure;
            assert ((s_valid = '1') = (vu4_expected = 0)) severity failure;
            if (vint_case = 24) then
                s_byte <= '1';
                cycles(10);
                s_byte <= '0';
                assert (s_ready = '0' and s_valid = '0' and su4_error = 6) severity failure;
            end if;
            cycles;
        end loop;
        report "STATE_SEMANTICS_PASS 34complete-body cases,SR/PC/SSP,IM,padding,cadence,beam,ADPCM enum,FM tail,startup,score readiness,189-bit ADPCM tail,boundaries,abort,length,retry" severity note;
        stop;
        wait;
    end process;
end architecture;
