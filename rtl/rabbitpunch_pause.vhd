-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;

-- Pause changes CPU enables through the board adapters; it is not the unused
-- original SERVICE freeze pin and does not gate a clock or chip sample enables.
entity rabbitpunch_pause is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_pause_pressed : in std_logic;
        i_osd_open : in std_logic;
        i_pause_on_osd : in std_logic;
        i_debug_pause : in std_logic;
        i_state_pause : in std_logic;
        o_pause_request : out std_logic;
        o_user_paused : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_pause is
    signal s_user_paused, s_previous_pressed : std_logic := '0';
begin
    o_user_paused <= s_user_paused;
    o_pause_request <= s_user_paused or (i_osd_open and i_pause_on_osd) or i_debug_pause or i_state_pause;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_previous_pressed <= i_pause_pressed;
            if (i_reset = '1') then
                s_user_paused <= '0';
            elsif (i_pause_pressed = '1' and s_previous_pressed = '0') then
                s_user_paused <= not s_user_paused;
            end if;
        end if;
    end process;
end architecture;
