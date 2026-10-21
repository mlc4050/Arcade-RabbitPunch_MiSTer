-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_config.all;

-- Selecting this configuration is an explicit integration gate. Normal cores
-- retain their exact configuration string and advertise no state storage.
package rabbitpunch_state_config is
    constant CINT_SLOT_INFO_BASE : natural := 2;
    function F_STATE_CONFIG(vbool_enable : boolean) return string;
    function F_STATE_GAME_ACTIONS(vu32_actions : unsigned(31 downto 0); vbool_enable : boolean) return unsigned;
end package;

package body rabbitpunch_state_config is
    function F_STATE_GAME_ACTIONS(vu32_actions : unsigned(31 downto 0); vbool_enable : boolean) return unsigned is
    begin
        if (vbool_enable and vu32_actions(15) = '1') then
            return to_unsigned(0, 32);
        end if;
        return vu32_actions;
    end function;

    function F_STATE_BUTTON_CONFIG(vstr_config : string) return string is
        constant CSTR_BUTTON_END : string := ",Pause,Service,Test;";
    begin
        for vint_index in vstr_config'low to vstr_config'high - CSTR_BUTTON_END'length + 1 loop
            if (vstr_config(vint_index to vint_index + CSTR_BUTTON_END'length - 1) = CSTR_BUTTON_END) then
                return vstr_config(vstr_config'low to vint_index + CSTR_BUTTON_END'length - 2) &
                    ",Savestate (SS);" & vstr_config(vint_index + CSTR_BUTTON_END'length to vstr_config'high);
            end if;
        end loop;
        assert (false) report "State configuration has no controller button insertion point" severity failure;
        return vstr_config;
    end function;

    function F_STATE_CONFIG(vbool_enable : boolean) return string is
        constant CSTR_HEAD : string := "RabbitPunch;;";
        constant CSTR_SAVE : string := "H3T4,Save NVRAM;";
        constant CSTR_STATE_HEAD : string := "RabbitPunch;SS3E000000:40000;";
        -- Native Main info messages are one-based; entry 1 is chord help.
        -- Keep the info list after all menu entries to preserve their indexes.
        constant CSTR_SLOT_INFO : string :=
            "I,Slot=SS+LR|Save/Load=SS+DU," &
            "Savestate slot 1,Savestate slot 2,Savestate slot 3,Savestate slot 4;";
        constant CSTR_CONTROLS : string :=
            "-;" &
            "O[6:5],Savestate slot,1,2,3,4;" &
            "O7,Autoincrement slot,Off,On;" &
            "H9T8,Save state;" &
            "H8T9,Restore state;";
    begin
        if (not vbool_enable) then
            return CSTR_DEFAULT_CONFIG_STRING;
        end if;
        assert (CSTR_DEFAULT_CONFIG_STRING(1 to CSTR_HEAD'length) = CSTR_HEAD)
            report "State configuration requires the expected host header" severity failure;
        for vint_index in CSTR_HEAD'length + 1 to CSTR_DEFAULT_CONFIG_STRING'length - CSTR_SAVE'length + 1 loop
            if (CSTR_DEFAULT_CONFIG_STRING(vint_index to vint_index + CSTR_SAVE'length - 1) = CSTR_SAVE) then
                return F_STATE_BUTTON_CONFIG(CSTR_STATE_HEAD &
                    CSTR_DEFAULT_CONFIG_STRING(CSTR_HEAD'length + 1 to vint_index + CSTR_SAVE'length - 1) &
                    CSTR_CONTROLS &
                    CSTR_DEFAULT_CONFIG_STRING(vint_index + CSTR_SAVE'length to CSTR_DEFAULT_CONFIG_STRING'length)) & CSTR_SLOT_INFO;
            end if;
        end loop;
        assert (false) report "State configuration has no Save NVRAM insertion point" severity failure;
        return CSTR_DEFAULT_CONFIG_STRING;
    end function;
end package body;
