-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity cheats_tb is
end entity;

architecture test of cheats_tb is
    signal s_clk : std_logic := '0';
    signal s_clear, s_download, s_write : std_logic := '0';
    signal s_read : std_logic := '1';
    signal s_available, s_error : std_logic;
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
            i_cpu_read => s_read,
            iu24_cpu_address => su24_cpu_address,
            iu16_cpu_data => su16_raw,
            ou16_cpu_data => su16_result,
            o_available => s_available,
            o_load_error => s_error
        );
    process
        variable vint_address : natural := 0;
        variable vint_checks : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure start_download is
        begin
            s_download <= '1';
            s_write <= '0';
            vint_address := 0;
            tick;
        end procedure;
        procedure send_byte(iu8_data : unsigned(7 downto 0)) is
        begin
            su27_byte_address <= to_unsigned(vint_address, 27);
            su8_byte_data <= iu8_data;
            s_write <= '1';
            tick;
            s_write <= '0';
            vint_address := vint_address + 1;
        end procedure;
        procedure send_code(
            iint_flags : natural;
            iint_address : natural;
            iu32_compare : unsigned(31 downto 0);
            iu32_data : unsigned(31 downto 0)
        ) is
            variable vu128_code : unsigned(127 downto 0);
        begin
            vu128_code := to_unsigned(iint_flags, 32) & to_unsigned(iint_address, 32) & iu32_compare & iu32_data;
            for vint_byte in 15 downto 0 loop
                send_byte(vu128_code(vint_byte * 8 + 7 downto vint_byte * 8));
            end loop;
        end procedure;
        procedure end_download(i_error : std_logic := '0') is
        begin
            s_download <= '0';
            s_write <= '0';
            tick;
            assert (s_error = i_error) report "Unexpected loader error state" severity failure;
        end procedure;
        procedure check(
            iint_address : natural;
            iu16_raw : unsigned(15 downto 0);
            iu16_expected : unsigned(15 downto 0)
        ) is
        begin
            su24_cpu_address <= to_unsigned(iint_address, 24);
            su16_raw <= iu16_raw;
            tick;
            assert (su16_result = iu16_expected)
                report "Read override mismatch at " & integer'image(iint_address)
                severity failure;
            assert (su16_raw = iu16_raw) report "Raw RAM data changed" severity failure;
            vint_checks := vint_checks + 1;
        end procedure;
    begin
        tick;
        check(16#FC3D8#, x"0201", x"0201");
        start_download;
        send_code(16#10#, 16#FC269#, x"00000000", x"00000090");
        send_code(16#10#, 16#FC3D9#, x"00000000", x"00000003");
        send_code(16#10#, 16#FC3D8#, x"00000000", x"00000000");
        send_code(16#10#, 16#FC2A9#, x"00000000", x"00000090");
        send_code(16#10#, 16#FC3F9#, x"00000000", x"00000003");
        send_code(16#10#, 16#FC3F8#, x"00000000", x"00000000");
        check(16#FC3D8#, x"0201", x"0201");
        end_download;
        assert (s_available = '1') severity failure;
        check(16#FC268#, x"1201", x"1290");
        check(16#FC3D8#, x"0201", x"0003");
        check(16#FC2A8#, x"3400", x"3490");
        check(16#FC3F8#, x"0102", x"0003");
        check(16#FFC268#, x"1201", x"1290");
        check(16#AFC3D8#, x"0201", x"0003");
        check(16#FC3DA#, x"ABCD", x"ABCD");
        check(16#C3D8#, x"0201", x"0201");
        s_read <= '0';
        check(16#FC3D8#, x"7654", x"7654");
        s_read <= '1';
        start_download;
        send_code(16#11#, 16#FC001#, x"00000034", x"000000AB");
        send_code(16#11#, 16#FC002#, x"00000056", x"000000CD");
        send_code(16#20#, 16#FC010#, x"00000000", x"00001234");
        send_code(16#41#, 16#FC020#, x"12345678", x"AABBCCDD");
        send_code(16#110#, 16#FC030#, x"00000000", x"000000F0");
        send_code(16#210#, 16#FC033#, x"00000000", x"0000000F");
        end_download;
        check(16#FC000#, x"1234", x"12AB");
        check(16#FC000#, x"1235", x"1235");
        check(16#FC002#, x"5678", x"CD78");
        check(16#FC002#, x"5778", x"5778");
        check(16#FC010#, x"DEAD", x"1234");
        check(16#FC020#, x"1234", x"AABB");
        check(16#FC022#, x"5678", x"CCDD");
        check(16#FC022#, x"5679", x"5679");
        check(16#FC030#, x"05AA", x"F5AA");
        check(16#FC032#, x"BEEF", x"BE0F");
        start_download;
        send_code(16#10#, 16#FC040#, x"00000000", x"000000AB");
        send_code(16#110#, 16#FC040#, x"00000000", x"0000000F");
        send_code(16#210#, 16#FC040#, x"00000000", x"0000000F");
        end_download;
        check(16#FC040#, x"55FF", x"05FF");
        start_download;
        for vint_code in 0 to 7 loop
            send_code(16#10#, 16#FC100# + vint_code, x"00000000", to_unsigned(vint_code + 1, 32));
        end loop;
        end_download;
        for vint_word in 0 to 3 loop
            check(16#FC100# + vint_word * 2, x"FFFF", to_unsigned((vint_word * 2 + 1) * 256 + vint_word * 2 + 2, 16));
        end loop;
        start_download;
        for vint_code in 0 to 8 loop
            send_code(16#10#, 16#FC100# + vint_code, x"00000000", x"00000001");
        end loop;
        end_download('1');
        assert (s_available = '0') severity failure;
        check(16#FC100#, x"FFFF", x"FFFF");
        start_download;
        send_code(16#10#, 16#FC269#, x"00000000", x"00000090");
        send_byte(x"00");
        end_download('1');
        check(16#FC268#, x"0001", x"0001");
        start_download;
        send_byte(x"00");
        send_byte(x"00");
        end_download;
        assert (s_available = '0') severity failure;
        for vint_invalid in 0 to 4 loop
            start_download;
            case vint_invalid is
                when 0 =>
                    send_code(16#80#, 16#FC100#, x"00000000", x"00000001");
                when 1 =>
                    send_code(16#30#, 16#FC100#, x"00000000", x"00000001");
                when 2 =>
                    send_code(16#310#, 16#FC100#, x"00000000", x"00000001");
                when 3 =>
                    send_code(16#20#, 16#FC101#, x"00000000", x"00000001");
                when others =>
                    send_code(16#10#, 16#000100#, x"00000000", x"00000001");
            end case;
            end_download('1');
            assert (s_available = '0') severity failure;
        end loop;
        start_download;
        vint_address := 5;
        send_byte(x"12");
        end_download('1');
        start_download;
        send_code(16#10#, 16#FC269#, x"00000000", x"00000090");
        end_download;
        check(16#FC268#, x"AA01", x"AA90");
        s_clear <= '1';
        check(16#FC268#, x"AA01", x"AA01");
        s_clear <= '0';
        tick;
        assert (s_available = '0' and s_error = '0') severity failure;
        report "CHEATS_PASS checks=" & integer'image(vint_checks);
        finish;
    end process;
end architecture;
