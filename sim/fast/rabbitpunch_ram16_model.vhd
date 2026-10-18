-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical RAM abstraction for fast simulation only. Never add to files.qip.
-- Production uses Intel altsyncram; this model covers only its exercised single-
-- clock enabled read/write contract. Uninitialized/X and collision behavior are
-- intentionally not modeled. Same-word mixed-port writes are rejected.
entity rabbitpunch_ram16 is
    generic (
        GINT_ADDRESS_BITS : positive := 13;
        GU16_POWER_UP_WORD : unsigned(15 downto 0) := x"0000"
    );
    port (
        i_clk : in std_logic;
        i_cpu_enable : in std_logic;
        i_cpu_write : in std_logic;
        iux_cpu_address : in unsigned;
        iu2_cpu_bytes : in unsigned(1 downto 0);
        iu16_cpu_data : in unsigned(15 downto 0);
        ou16_cpu_data : out unsigned(15 downto 0);
        i_view_enable : in std_logic;
        iux_view_address : in unsigned;
        ou16_view_data : out unsigned(15 downto 0)
    );
end entity;

architecture fast_sim of rabbitpunch_ram16 is
    type t_bytes is array (0 to 2 ** GINT_ADDRESS_BITS - 1) of unsigned(7 downto 0);
    signal su8_low_memory : t_bytes := (others => GU16_POWER_UP_WORD(7 downto 0));
    signal su8_high_memory : t_bytes := (others => GU16_POWER_UP_WORD(15 downto 8));
begin
    assert (iux_cpu_address'length = GINT_ADDRESS_BITS and iux_view_address'length = GINT_ADDRESS_BITS)
        report "Fast RAM16 address widths differ" severity failure;
    access_memory : process(i_clk)
        variable vint_cpu_address, vint_view_address : natural range 0 to 2 ** GINT_ADDRESS_BITS - 1;
    begin
        if (rising_edge(i_clk)) then
            vint_cpu_address := to_integer(iux_cpu_address);
            vint_view_address := to_integer(iux_view_address);
            assert (not (i_cpu_enable = '1' and i_cpu_write = '1' and i_view_enable = '1' and
                vint_cpu_address = vint_view_address))
                report "Fast RAM16 cannot represent a mixed-port same-word write" severity failure;
            if (i_cpu_enable = '1') then
                if (i_cpu_write = '1') then
                    if (iu2_cpu_bytes(0) = '1') then
                        su8_low_memory(vint_cpu_address) <= iu16_cpu_data(7 downto 0);
                    end if;
                    if (iu2_cpu_bytes(1) = '1') then
                        su8_high_memory(vint_cpu_address) <= iu16_cpu_data(15 downto 8);
                    end if;
                else
                    ou16_cpu_data <= su8_high_memory(vint_cpu_address) & su8_low_memory(vint_cpu_address);
                end if;
            end if;
            if (i_view_enable = '1') then
                ou16_view_data <= su8_high_memory(vint_view_address) & su8_low_memory(vint_view_address);
            end if;
        end if;
    end process;
end architecture;
