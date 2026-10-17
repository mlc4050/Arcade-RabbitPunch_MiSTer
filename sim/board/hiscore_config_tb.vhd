-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity hiscore_config_tb is
end entity;
architecture test of hiscore_config_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_download, s_write : std_logic := '0';
    signal su16_index : unsigned(15 downto 0) := to_unsigned(3, 16);
    signal su27_address : unsigned(26 downto 0) := (others => '0');
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal s_valid, s_us, s_error : std_logic;
    signal su32_start : unsigned(31 downto 0);
    signal su16_check : unsigned(15 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_hiscore_config
        port map (
            i_clk => s_clk,
            i_initialize => s_reset,
            i_download => s_download,
            iu16_file_index => su16_index,
            i_write => s_write,
            iu27_byte_address => su27_address,
            iu8_data => su8_data,
            o_profile_valid => s_valid,
            o_us_set => s_us,
            ou32_start_wait => su32_start,
            ou16_check_wait => su16_check,
            o_error => s_error
        );
    process
        variable vu192_packet : unsigned(191 downto 0);
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure send(vint_count : natural := 24; v_reorder : boolean := false) is
        begin
            su16_index <= to_unsigned(3, 16);
            s_download <= '1';
            cycles(2);
            assert (s_valid = '0') report "Old score profile survived a new configuration start" severity failure;
            for vint_byte in 0 to vint_count - 1 loop
                su27_address <= to_unsigned(vint_byte, 27);
                if (v_reorder and vint_byte = 3) then
                    su27_address <= to_unsigned(4, 27);
                end if;
                su8_data <= vu192_packet(191 - (vint_byte mod 24) * 8 downto 184 - (vint_byte mod 24) * 8);
                s_write <= '1';
                cycles(1);
                s_write <= '0';
                cycles(1);
                assert (s_valid = '0') report "Partial metadata enabled score access" severity failure;
            end loop;
            s_download <= '0';
            cycles(2);
        end procedure;
    begin
        cycles(3);
        s_reset <= '0';
        -- Full-width waits detect accidental truncation or little-endian parsing.
        vu192_packet := x"12345678ABCD00020002000100000000000FFE0100770080";
        send;
        assert (s_valid = '1' and s_us = '0' and s_error = '0' and
            su32_start = x"12345678" and su16_check = x"ABCD")
            report "Japan score profile/header byte order mismatch" severity failure;
        vu192_packet(31 downto 16) := to_unsigned(115, 16);
        vu192_packet(7 downto 0) := x"17";
        send;
        assert (s_valid = '1' and s_us = '1' and s_error = '0')
            report "US score profile mismatch" severity failure;
        send(23);
        assert (s_valid = '0' and s_error = '1') report "Truncated metadata accepted" severity failure;
        send(25);
        assert (s_valid = '0' and s_error = '1') report "Oversized metadata accepted" severity failure;
        send(24, true);
        assert (s_valid = '0' and s_error = '1') report "Reordered metadata accepted" severity failure;
        -- Every descriptor/geometry byte must be enforced, not silently ignored.
        for vint_byte in 6 to 23 loop
            vu192_packet(191 - vint_byte * 8 downto 184 - vint_byte * 8) :=
                vu192_packet(191 - vint_byte * 8 downto 184 - vint_byte * 8) xor x"01";
            send;
            assert (s_valid = '0' and s_error = '1')
                report "Unsupported score descriptor accepted at byte " & integer'image(vint_byte) severity failure;
            vu192_packet(191 - vint_byte * 8 downto 184 - vint_byte * 8) :=
                vu192_packet(191 - vint_byte * 8 downto 184 - vint_byte * 8) xor x"01";
        end loop;
        send;
        assert (s_valid = '1') report "Valid metadata did not recover after a rejected file" severity failure;
        su16_index <= to_unsigned(254, 16);
        s_download <= '1';
        s_write <= '1';
        cycles(5);
        s_write <= '0';
        s_download <= '0';
        cycles(2);
        assert (s_valid = '1') report "Unrelated DIP transfer changed score configuration" severity failure;
        su16_index <= (others => '0');
        s_download <= '1';
        cycles(2);
        assert (s_valid = '0' and s_error = '0') report "ROM replacement retained score configuration" severity failure;
        report "HISCORE_CONFIG_PASS sets=2 full_width_waits=checked partial_reordered_oversize=checked unsupported_header_and_geometry=18 mutation_recovery=checked unrelated_index=checked generation_reset=checked";
        finish;
        wait;
    end process;
end architecture;
