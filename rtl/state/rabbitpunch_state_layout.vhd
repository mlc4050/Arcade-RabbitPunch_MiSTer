-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rabbitpunch_state_layout is
    constant CINT_RAM_BYTES : positive := 106496;
    constant CINT_M68K_BYTES : positive := 96;
    constant CINT_T80_BYTES : positive := 32;
    constant CINT_BOARD_BYTES : positive := 64;
    constant CINT_FM_BYTES : positive := 504;
    constant CINT_ADPCM_BYTES : positive := 24;
    -- Corrected ea4c83e controller plus unchanged JT7759 shell inventory.
    constant CINT_ADPCM_STATE_BITS : positive := 189;
    constant CINT_M68K_BASE : natural := CINT_RAM_BYTES;
    constant CINT_T80_BASE : natural := CINT_M68K_BASE + CINT_M68K_BYTES;
    constant CINT_BOARD_BASE : natural := CINT_T80_BASE + CINT_T80_BYTES;
    constant CINT_FM_BASE : natural := CINT_BOARD_BASE + CINT_BOARD_BYTES;
    constant CINT_ADPCM_BASE : natural := CINT_FM_BASE + CINT_FM_BYTES;
    constant CINT_BODY_BYTES : positive := CINT_ADPCM_BASE + CINT_ADPCM_BYTES;
    constant CINT_IMAGE_BYTES : positive := 64 + CINT_BODY_BYTES;
    constant CU192_SECTION_BYTES : unsigned(191 downto 0) :=
        to_unsigned(CINT_ADPCM_BYTES, 32) & to_unsigned(CINT_FM_BYTES, 32) &
        to_unsigned(CINT_BOARD_BYTES, 32) & to_unsigned(CINT_T80_BYTES, 32) &
        to_unsigned(CINT_M68K_BYTES, 32) & to_unsigned(CINT_RAM_BYTES, 32);
    function F_M68K_WORD_VALID(vint_word : natural; vu32_data : unsigned(31 downto 0)) return boolean;
    function F_T80_VALID(vu256_data : unsigned(255 downto 0)) return boolean;
    function F_BOARD_VALID(vu512_data : unsigned(511 downto 0);
        vint_horizontal_total, vint_vertical_total : positive) return boolean;
end package;

package body rabbitpunch_state_layout is
    function F_M68K_WORD_VALID(vint_word : natural; vu32_data : unsigned(31 downto 0)) return boolean is
        variable vu24_stack_word : unsigned(23 downto 0);
        variable vu20_address : unsigned(19 downto 0);
    begin
        case vint_word is
            when 16 | 17 | 21 | 23 =>
                -- 68000 VBR/CACR/frame placeholders and final alignment word.
                return vu32_data = 0;
            when 18 =>
                -- Bank18 stores SSP-6; the pre-IACK word was at SSP-2.
                vu24_stack_word := vu32_data(23 downto 0) + 4;
                vu20_address := vu24_stack_word(19 downto 0);
                return vu24_stack_word(0) = '0' and (
                    (vu20_address >= x"40000" and vu20_address <= x"4FFFE") or
                    (vu20_address >= x"60000" and vu20_address <= x"60FFE") or
                    (vu20_address >= x"80000" and vu20_address <= x"83FFE") or
                    (vu20_address >= x"A0000" and vu20_address <= x"A07FE") or
                    vu20_address >= x"FC000");
            when 19 =>
                -- Only T,S,IPL and the five CCR bits exist on the 68000.
                return (vu32_data and x"FFFF58E0") = 0;
            when 20 =>
                return vu32_data(0) = '0';
            when 22 =>
                return vu32_data <= 1;
            when others =>
                return vint_word < 24;
        end case;
    end function;
    function F_T80_VALID(vu256_data : unsigned(255 downto 0)) return boolean is
    begin
        return vu256_data(255 downto 238) = 0 and vu256_data(209 downto 208) < 3;
    end function;
    function F_BOARD_VALID(vu512_data : unsigned(511 downto 0);
        vint_horizontal_total, vint_vertical_total : positive) return boolean is
        variable vu32_cadence, vu32_beam : unsigned(31 downto 0);
        variable vu16_adpcm : unsigned(15 downto 0);
    begin
        vu32_cadence := vu512_data(287 downto 256);
        vu32_beam := vu512_data(319 downto 288);
        vu16_adpcm := vu512_data(335 downto 320);
        -- Bytes0..27 IO;28 IRQ;29..31 padding;32..35 cadence;36..39
        -- beam;40..41 ADPCM wrapper;42..43 mono mixer;44 bits0/1 FM
        -- primed/valid, bit2 captured score readiness;remaining bits padding.
        return vu512_data(223 downto 206) = 0 and vu512_data(255 downto 228) = 0 and
            vu32_cadence(2 downto 0) < 7 and vu32_cadence(8 downto 3) < 35 and
            vu32_cadence(14 downto 9) < 35 and vu32_cadence(24 downto 15) < 875 and
            vu32_cadence(31 downto 26) = 0 and vu32_beam(31 downto 18) = 0 and
            vu32_beam(8 downto 0) < vint_horizontal_total and
            vu32_beam(17 downto 9) < vint_vertical_total and
            vu16_adpcm(15 downto 13) = 0 and vu16_adpcm(1 downto 0) < 3 and
            (vu512_data(353) = '0' or vu512_data(352) = '1') and
            vu512_data(511 downto 355) = 0;
    end function;
end package body;
