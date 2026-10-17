-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Assert initialization even when the PLL clock stops. Release only on three
-- system-clock edges; game reset and user pause do not belong on this input.
entity rabbitpunch_reset_release is
    port (
        i_clk : in std_logic;
        i_asynchronous_reset : in std_logic;
        o_reset : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_reset_release is
    signal su3_release : unsigned(2 downto 0) := (others => '1');
    attribute preserve : boolean;
    attribute preserve of su3_release : signal is true;
begin
    o_reset <= su3_release(2);
    release_reset : process(i_clk, i_asynchronous_reset)
    begin
        if (i_asynchronous_reset = '1') then
            su3_release <= (others => '1');
        elsif (rising_edge(i_clk)) then
            su3_release <= su3_release(1 downto 0) & '0';
        end if;
    end process;
end architecture;
