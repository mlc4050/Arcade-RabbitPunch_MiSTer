-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MAME GGA register 0b arms the next vblank, then one or two events per frame.
-- Raster pulses are supplied externally; this block invents no physical timing.
entity rabbitpunch_irq is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_configure : in std_logic;
        i_twice_per_frame : in std_logic;
        i_vblank_start : in std_logic;
        i_half_frame : in std_logic;
        i_acknowledge : in std_logic;
        o_level1_pending : out std_logic;
        i_state_hold : in std_logic := '0';
        i_state_load : in std_logic := '0';
        iu4_state : in unsigned(3 downto 0) := (others => '0');
        ou4_state : out unsigned(3 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_irq is
    signal s_enabled, s_started, s_twice, s_pending : std_logic := '0';
begin
    o_level1_pending <= s_pending;
    -- Configuration and first-event history cannot be reconstructed from pending.
    ou4_state <= unsigned'(s_enabled & s_started & s_twice & s_pending);
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                s_enabled <= '0';
                s_started <= '0';
                s_twice <= '0';
                s_pending <= '0';
            elsif (i_state_hold = '1') then
                if (i_state_load = '1') then
                    s_enabled <= iu4_state(3);
                    s_started <= iu4_state(2);
                    s_twice <= iu4_state(1);
                    s_pending <= iu4_state(0);
                end if;
            else
                if (i_acknowledge = '1') then
                    s_pending <= '0';
                end if;
                if (i_configure = '1') then
                    s_enabled <= '1';
                    s_started <= '0';
                    s_twice <= i_twice_per_frame;
                elsif (i_vblank_start = '1' and s_enabled = '1') then
                    s_started <= '1';
                    s_pending <= '1';
                elsif (i_half_frame = '1' and s_started = '1' and s_twice = '1') then
                    s_pending <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
