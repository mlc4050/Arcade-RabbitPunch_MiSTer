-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;

-- Keep the external status indicator behind one timed game-clock register.
-- Gameplay/debug flags remain unchanged; only their LED presentation is delayed.
entity rabbitpunch_status_led is
    port (
        i_clk : in std_logic;
        i_loading : in std_logic;
        i_downloading : in std_logic;
        i_error : in std_logic;
        i_underflow : in std_logic;
        o_led : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_status_led is
    signal s_led : std_logic := '0';
begin
    o_led <= s_led;
    status_register : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_led <= i_loading or i_downloading or i_error or i_underflow;
        end if;
    end process;
end architecture;
