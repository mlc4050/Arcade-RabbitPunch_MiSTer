-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Development host contract: expose only controls implemented by the logical
-- platform plus the optional framework presentation path.
package rabbitpunch_config is
    constant CINT_STATUS_RESET_BIT : natural := 0;
    constant CINT_STATUS_PAUSE_BIT : natural := 1;
    constant CINT_STATUS_OSD_PAUSE_BIT : natural := 2;
    constant CINT_STATUS_HISCORE_AUTOSAVE_BIT : natural := 3;
    constant CSTR_DEFAULT_CONFIG_STRING : string :=
        "RabbitPunch;;" &
        "R0,Reset;" &
        "O1,Pause,Off,On;" &
        "O2,Pause when OSD is open,Off,On;" &
        "H3O3,Autosave high scores,Off,On;" &
        "O[65],Flip Screen,Off,On;" &
        "H5O[46:44],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;" &
        "H5O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];" &
        "H5O[68:66],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;" &
        "J1,Missile,Shoot,-,-,-,-,Start,Coin,Pause,Service,Test;" &
        "V,v0.1-dev;";
end package;
