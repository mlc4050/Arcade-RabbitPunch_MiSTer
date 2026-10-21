-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Staged builds replace these constants from the selected QSF and HEAD.
-- Direct editor builds retain a visible zero identity and no debug probe.
package rabbitpunch_state_build is
    constant CBOOL_DEBUG_ENABLE : boolean := false;
    constant CU32_BUILD_ID : unsigned(31 downto 0) := x"00000000";
end package;
