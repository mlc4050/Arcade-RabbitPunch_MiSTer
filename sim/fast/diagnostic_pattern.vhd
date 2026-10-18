-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
package diagnostic_program is
    function program_word(iint_address : natural) return unsigned;
end package;
package body diagnostic_program is
    function program_word(iint_address : natural) return unsigned is
        variable vu16_high : unsigned(15 downto 0);
    begin
        vu16_high := to_unsigned(iint_address / 65536, 16);
        return to_unsigned(iint_address mod 65536, 16) xor
            shift_left(vu16_high, 3) xor shift_left(vu16_high, 9) xor x"A55A";
    end function;
end package body;
