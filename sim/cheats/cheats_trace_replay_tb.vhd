-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity cheats_trace_replay_tb is
end entity;

architecture test of cheats_trace_replay_tb is
    signal s_clk : std_logic := '0';
    signal s_clear : std_logic := '1';
    signal s_download, s_write : std_logic := '0';
    signal s_error : std_logic;
    signal su27_byte_address : unsigned(26 downto 0) := (others => '0');
    signal su8_byte_data : unsigned(7 downto 0) := (others => '0');
    signal su24_cpu_address : unsigned(23 downto 0) := (others => '0');
    signal su16_raw, su16_result : unsigned(15 downto 0) := (others => '0');
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_cheats
        port map (
            i_clk => s_clk,
            i_clear => s_clear,
            i_download => s_download,
            i_write => s_write,
            iu27_byte_address => su27_byte_address,
            iu8_byte_data => su8_byte_data,
            i_cpu_read => '1',
            iu24_cpu_address => su24_cpu_address,
            iu16_cpu_data => su16_raw,
            ou16_cpu_data => su16_result,
            o_available => open,
            o_load_error => s_error
        );
    process
        file f_vectors : text open read_mode is "vectors.txt";
        variable v_line : line;
        variable vint_active, vint_previous_active : natural := 0;
        variable vint_address, vint_raw, vint_expected : natural;
        variable vint_reads : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure select_codes(vbool_active : boolean) is
            file f_codes : text;
            variable v_code_line : line;
            variable vint_byte : natural;
            variable vint_offset : natural := 0;
        begin
            s_download <= '1';
            s_write <= '0';
            tick;
            if (vbool_active) then
                file_open(f_codes, "codes.txt", read_mode);
                while (not endfile(f_codes)) loop
                    readline(f_codes, v_code_line);
                    for vint_index in 0 to 15 loop
                        read(v_code_line, vint_byte);
                        su27_byte_address <= to_unsigned(vint_offset, 27);
                        su8_byte_data <= to_unsigned(vint_byte, 8);
                        s_write <= '1';
                        tick;
                        vint_offset := vint_offset + 1;
                    end loop;
                end loop;
                file_close(f_codes);
                assert (vint_offset = 96) report "Expected six complete MRA codes" severity failure;
            else
                for vint_index in 0 to 1 loop
                    su27_byte_address <= to_unsigned(vint_index, 27);
                    su8_byte_data <= (others => '0');
                    s_write <= '1';
                    tick;
                end loop;
            end if;
            s_write <= '0';
            s_download <= '0';
            tick;
            assert (s_error = '0') report "Trace replay cheat load rejected" severity failure;
        end procedure;
    begin
        tick;
        s_clear <= '0';
        tick;
        while (not endfile(f_vectors)) loop
            readline(f_vectors, v_line);
            read(v_line, vint_active);
            read(v_line, vint_address);
            read(v_line, vint_raw);
            read(v_line, vint_expected);
            if (vint_active /= vint_previous_active) then
                select_codes(vint_active = 1);
                vint_previous_active := vint_active;
            end if;
            su24_cpu_address <= to_unsigned(vint_address, 24);
            su16_raw <= to_unsigned(vint_raw, 16);
            tick;
            assert (su16_result = to_unsigned(vint_expected, 16))
                report "MAME cheat read differs at vector " & integer'image(vint_reads)
                severity failure;
            assert (su16_raw = to_unsigned(vint_raw, 16))
                report "Trace replay changed raw memory response" severity failure;
            vint_reads := vint_reads + 1;
        end loop;
        assert (vint_reads > 1000) report "Trace workload is too short" severity failure;
        report "CHEATS_TRACE_REPLAY_PASS reads=" & integer'image(vint_reads);
        finish;
    end process;
end architecture;
