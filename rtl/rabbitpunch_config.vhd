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
        "DIP;" &
        "R0,Reset;" &
        "O1,Pause,Off,On;" &
        "O2,Pause when OSD is open,Off,On;" &
        "H3O3,Autosave high scores,Off,On;" &
        "O[65],Flip Screen,Off,On;" &
        "O[94],CRT Adjust,Off,On;" &
        "H7O[99:95],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;" &
        "H6O[106:100],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;" &
        "H6O[112:107],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;" &
        "H5O[46:44],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;" &
        "H5O[114:113],HDMI Rotate,None,CW,CCW;" &
        "H5O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];" &
        "H5O[68:66],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;" &
        "O[124:123],Audio mix,Mono,None,25%,50%;" &
        "J1,Fire/Punch,Missile,-,-,-,-,Start,Coin,Pause,Service,Test;" &
        "V,v0.1-dev;";
end package;
