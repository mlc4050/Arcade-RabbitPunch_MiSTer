-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rabbitpunch_state_crc is
    constant CU32_CRC_SEED : unsigned(31 downto 0) := x"FFFFFFFF";
    -- Reflected IEEE CRC-32. Finalize with NOT after the last byte.
    function F_CRC32_BYTE(vu32_crc : unsigned(31 downto 0);
        vu8_data : unsigned(7 downto 0)) return unsigned;
    -- Download words contain the lower-address byte in bits 7..0.
    function F_CRC32_WORD(vu32_crc : unsigned(31 downto 0);
        vu16_data : unsigned(15 downto 0)) return unsigned;
end package;

package body rabbitpunch_state_crc is
    function F_CRC32_BYTE(vu32_crc : unsigned(31 downto 0);
        vu8_data : unsigned(7 downto 0)) return unsigned is
        variable vu32_next : unsigned(31 downto 0);
    begin
        vu32_next := vu32_crc xor resize(vu8_data, 32);
        for vint_bit in 0 to 7 loop
            if (vu32_next(0) = '1') then
                vu32_next := shift_right(vu32_next, 1) xor x"EDB88320";
            else
                vu32_next := shift_right(vu32_next, 1);
            end if;
        end loop;
        return vu32_next;
    end function;

    function F_CRC32_WORD(vu32_crc : unsigned(31 downto 0);
        vu16_data : unsigned(15 downto 0)) return unsigned is
    begin
        return F_CRC32_BYTE(F_CRC32_BYTE(vu32_crc, vu16_data(7 downto 0)),
            vu16_data(15 downto 8));
    end function;
end package body;
