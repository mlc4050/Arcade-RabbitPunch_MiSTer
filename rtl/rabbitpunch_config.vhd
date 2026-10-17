-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Development host contract: expose only controls implemented by the logical
-- platform. Physical video/scaler/audio options belong to later shell wiring.
package rabbitpunch_config is
    constant STATUS_RESET_BIT : natural := 0;
    constant STATUS_PAUSE_BIT : natural := 1;
    constant STATUS_OSD_PAUSE_BIT : natural := 2;
    constant STATUS_HISCORE_AUTOSAVE_BIT : natural := 3;
    constant DEFAULT_CONFIG_STRING : string :=
        "RabbitPunch;;" &
        "R0,Reset;" &
        "O1,Pause,Off,On;" &
        "O2,Pause when OSD is open,Off,On;" &
        "H3O3,Autosave high scores,Off,On;" &
        "J1,Missile,Shoot,-,-,-,-,Start,Coin,Pause,Service,Test;" &
        "V,v0.1-dev;";
end package;
