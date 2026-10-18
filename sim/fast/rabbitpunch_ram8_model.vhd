-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical RAM abstraction for fast simulation only. Never add to files.qip.
-- Production uses Intel altsyncram; this model covers only its exercised single-
-- clock enabled read/write contract. Uninitialized/X and collision behavior are
-- intentionally not modeled. Same-word mixed-port writes are rejected.
entity rabbitpunch_ram8 is
    generic (GINT_ADDRESS_BITS : positive := 11);
    port (
        i_clk : in std_logic;
        i_cpu_enable : in std_logic;
        i_cpu_write : in std_logic;
        iux_cpu_address : in unsigned;
        iu8_cpu_data : in unsigned(7 downto 0);
        ou8_cpu_data : out unsigned(7 downto 0);
        i_view_enable : in std_logic;
        iux_view_address : in unsigned;
        ou8_view_data : out unsigned(7 downto 0)
    );
end entity;

architecture fast_sim of rabbitpunch_ram8 is
    type t_bytes is array (0 to 2 ** GINT_ADDRESS_BITS - 1) of unsigned(7 downto 0);
    signal su8_memory : t_bytes := (others => (others => '0'));
begin
    assert (iux_cpu_address'length = GINT_ADDRESS_BITS and iux_view_address'length = GINT_ADDRESS_BITS)
        report "Fast RAM8 address widths differ" severity failure;
    access_memory : process(i_clk)
        variable vint_cpu_address, vint_view_address : natural range 0 to 2 ** GINT_ADDRESS_BITS - 1;
    begin
        if (rising_edge(i_clk)) then
            vint_cpu_address := to_integer(iux_cpu_address);
            vint_view_address := to_integer(iux_view_address);
            assert (not (i_cpu_enable = '1' and i_cpu_write = '1' and i_view_enable = '1' and
                vint_cpu_address = vint_view_address))
                report "Fast RAM8 cannot represent a mixed-port same-word write" severity failure;
            if (i_cpu_enable = '1') then
                if (i_cpu_write = '1') then
                    su8_memory(vint_cpu_address) <= iu8_cpu_data;
                else
                    ou8_cpu_data <= su8_memory(vint_cpu_address);
                end if;
            end if;
            if (i_view_enable = '1') then
                ou8_view_data <= su8_memory(vint_view_address);
            end if;
        end if;
    end process;
end architecture;
