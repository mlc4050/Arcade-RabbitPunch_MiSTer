-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity ram_powerup_tb is
end entity;
architecture test of ram_powerup_tb is
    type t_words is array (0 to 2) of unsigned(15 downto 0);
    constant C_INITIAL : t_words := (x"0000", x"FFFF", x"A55A");
    signal su16_cpu_data, su16_view_data : t_words;
    signal s_clk : std_logic := '0';
    signal s_enable, s_view_enable : std_logic := '1';
    signal s_write16, s_write8 : std_logic := '0';
    signal su8_cpu_address, su8_view_address : unsigned(7 downto 0) := (others => '0');
    signal su16_write_data : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes : unsigned(1 downto 0) := "11";
    signal su8_write_data, su8_cpu_data, su8_view_data : unsigned(7 downto 0) := (others => '0');
begin
    s_clk <= not s_clk after 5 ns;
    banks : for vint_bank in 0 to 2 generate
        ram : entity work.rabbitpunch_ram16
            generic map (
                GINT_ADDRESS_BITS => 8,
                GU16_POWER_UP_WORD => C_INITIAL(vint_bank)
            )
            port map (
                i_clk => s_clk,
                i_cpu_enable => s_enable,
                i_cpu_write => s_write16,
                iux_cpu_address => su8_cpu_address,
                iu2_cpu_bytes => su2_bytes,
                iu16_cpu_data => su16_write_data,
                ou16_cpu_data => su16_cpu_data(vint_bank),
                i_view_enable => s_view_enable,
                iux_view_address => su8_view_address,
                ou16_view_data => su16_view_data(vint_bank)
            );
    end generate;
    byte_ram : entity work.rabbitpunch_ram8
        generic map (
            GINT_ADDRESS_BITS => 8
        )
        port map (
            i_clk => s_clk,
            i_cpu_enable => s_enable,
            i_cpu_write => s_write8,
            iux_cpu_address => su8_cpu_address,
            iu8_cpu_data => su8_write_data,
            ou8_cpu_data => su8_cpu_data,
            i_view_enable => s_view_enable,
            iux_view_address => su8_view_address,
            ou8_view_data => su8_view_data
        );
    process
        variable vu16_expected : unsigned(15 downto 0);
        variable v_cpu_hold, v_view_hold : t_words;
        variable vu8_cpu_hold, vu8_view_hold : unsigned(7 downto 0);
        procedure cycle is
        begin
            wait until falling_edge(s_clk);
        end procedure;
    begin
        cycle;
        for vint_address in 0 to 255 loop
            su8_cpu_address <= to_unsigned(vint_address, 8);
            su8_view_address <= to_unsigned(255 - vint_address, 8);
            cycle;
            for vint_bank in 0 to 2 loop
                assert (su16_cpu_data(vint_bank) = C_INITIAL(vint_bank) and
                    su16_view_data(vint_bank) = C_INITIAL(vint_bank))
                    report "Native RAM16 configuration contents differ before any write" severity failure;
            end loop;
            assert (su8_cpu_data = 0 and su8_view_data = 0)
                report "Native RAM8 configuration contents are not zero" severity failure;
        end loop;
        s_view_enable <= '0';
        s_write16 <= '1';
        s_write8 <= '1';
        su2_bytes <= "10";
        su16_write_data <= x"ABCD";
        for vint_address in 0 to 255 loop
            su8_cpu_address <= to_unsigned(vint_address, 8);
            su8_write_data <= to_unsigned(vint_address, 8) xor x"C3";
            cycle;
        end loop;
        s_write16 <= '0';
        s_write8 <= '0';
        s_view_enable <= '1';
        for vint_address in 0 to 255 loop
            su8_cpu_address <= to_unsigned(vint_address, 8);
            su8_view_address <= to_unsigned(255 - vint_address, 8);
            cycle;
            for vint_bank in 0 to 2 loop
                vu16_expected := x"AB00";
                vu16_expected(7 downto 0) := C_INITIAL(vint_bank)(7 downto 0);
                assert (su16_cpu_data(vint_bank) = vu16_expected and su16_view_data(vint_bank) = vu16_expected)
                    report "Upper-byte write corrupted encoded lower-byte initialization" severity failure;
            end loop;
            assert (su8_cpu_data = (to_unsigned(vint_address, 8) xor x"C3") and
                su8_view_data = (to_unsigned(255 - vint_address, 8) xor x"C3"))
                report "Initialized byte RAM write/read mismatch" severity failure;
        end loop;
        s_view_enable <= '0';
        s_write16 <= '1';
        su2_bytes <= "01";
        for vint_address in 0 to 255 loop
            su8_cpu_address <= to_unsigned(vint_address, 8);
            su16_write_data <= x"1200" or resize(to_unsigned(vint_address, 8) xor x"5A", 16);
            cycle;
        end loop;
        s_write16 <= '0';
        s_view_enable <= '1';
        for vint_address in 0 to 255 loop
            su8_cpu_address <= to_unsigned(vint_address, 8);
            su8_view_address <= to_unsigned(255 - vint_address, 8);
            cycle;
            for vint_bank in 0 to 2 loop
                assert (su16_cpu_data(vint_bank) = (x"AB00" or resize(to_unsigned(vint_address, 8) xor x"5A", 16)) and
                    su16_view_data(vint_bank) = (x"AB00" or resize(to_unsigned(255 - vint_address, 8) xor x"5A", 16)))
                    report "Lower-byte write or dual-port decoding corrupted initialized RAM" severity failure;
            end loop;
        end loop;
        v_cpu_hold := su16_cpu_data;
        v_view_hold := su16_view_data;
        vu8_cpu_hold := su8_cpu_data;
        vu8_view_hold := su8_view_data;
        s_enable <= '0';
        s_view_enable <= '0';
        su8_cpu_address <= x"7F";
        su8_view_address <= x"80";
        for vint_cycle in 1 to 8 loop
            cycle;
            assert (su16_cpu_data = v_cpu_hold and su16_view_data = v_view_hold and
                su8_cpu_data = vu8_cpu_hold and su8_view_data = vu8_view_hold)
                report "Disabled native RAM outputs did not retain their contents" severity failure;
        end loop;
        report "RAM_POWERUP_PASS words_per_bank=256 logical_patterns=0000_FFFF_A55A byte_ram_zero=checked dual_ports=checked independent_byte_lanes=checked clock_enable_hold=checked no_simulator_deposits=checked";
        finish;
        wait;
    end process;
end architecture;
