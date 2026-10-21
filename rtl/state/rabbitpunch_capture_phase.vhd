-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- STOP-aware 68000 capture leaves the core waiting on a private bank read.
-- Keep that stalled core clocked through two E falling edges, then stop at
-- the known E-counter-zero/next-phi1 boundary. Both save continuation and
-- restore continuation must use this same normalization. The parent owns
-- private RTE clocks, IRQ masking and physical display synchronization.
entity rabbitpunch_capture_phase is
    generic (
        GINT_PHASE_DIVIDER : positive := 3;
        GBOOL_EXTERNAL_PHASE_ENABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_phase_enable : in std_logic;
        i_user_pause : in std_logic;
        i_bus_inactive : in std_logic;
        i_capture_active : in std_logic;
        i_monitor_held : in std_logic;
        i_peripheral_clock : in std_logic;
        i_resume : in std_logic;
        o_enable_phase1 : out std_logic;
        o_enable_phase2 : out std_logic;
        o_paused : out std_logic;
        o_capture_held : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_capture_phase is
    signal sint_phase_count : natural range 0 to GINT_PHASE_DIVIDER - 1 := 0;
    signal s_phase, s_previous_e, s_first_fall, s_parked : std_logic := '0';
    signal s_advance, s_pause, s_stop_now, s_freeze : std_logic;
begin
    s_advance <= i_phase_enable when GBOOL_EXTERNAL_PHASE_ENABLE else
        '1' when sint_phase_count = GINT_PHASE_DIVIDER - 1 else '0';
    s_pause <= i_user_pause and i_bus_inactive and not i_capture_active and not i_initialize;
    s_stop_now <= i_monitor_held and s_first_fall and s_previous_e and not i_peripheral_clock;
    -- Match the original wrapper: phases continue through CPU reset, and
    -- user pause is ignored during reset. Only capture metadata is cleared.
    s_freeze <= '0' when i_initialize = '1' else s_pause or s_parked or s_stop_now;
    o_enable_phase1 <= s_advance and not s_phase and not s_freeze;
    o_enable_phase2 <= s_advance and s_phase and not s_freeze;
    o_paused <= (s_pause or s_parked) and not i_initialize;
    o_capture_held <= s_parked and not i_initialize;
    phases : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_previous_e <= i_peripheral_clock;
            if (i_initialize = '1') then
                s_first_fall <= '0';
                s_parked <= '0';
                s_previous_e <= '0';
            else
                if (i_resume = '1') then
                    s_first_fall <= '0';
                    s_parked <= '0';
                elsif (i_monitor_held = '0') then
                    s_first_fall <= '0';
                elsif (s_previous_e = '1' and i_peripheral_clock = '0') then
                    if (s_first_fall = '1') then
                        s_parked <= '1';
                        assert (s_phase = '0') report "68000 E boundary is not next-phi1" severity failure;
                    else
                        s_first_fall <= '1';
                    end if;
                end if;
            end if;
            if (s_freeze = '0') then
                if (GBOOL_EXTERNAL_PHASE_ENABLE) then
                    if (i_phase_enable = '1') then
                        s_phase <= not s_phase;
                    end if;
                elsif (sint_phase_count = GINT_PHASE_DIVIDER - 1) then
                    sint_phase_count <= 0;
                    s_phase <= not s_phase;
                else
                    sint_phase_count <= sint_phase_count + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
