-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity diagnostic_rom_tb is
    generic (
        GBOOL_CORRUPT_ROM : boolean := false;
        GINT_FILL_WORDS : positive := 64
    );
end entity;

architecture test of diagnostic_rom_tb is
    type t_rom is array(0 to 131071) of unsigned(15 downto 0);
    impure function read_rom return t_rom is
        file rom_file : text open read_mode is "maincpu.hex";
        variable v_line : line;
        variable vu16_word : unsigned(15 downto 0);
        variable vtyp_rom : t_rom;
    begin
        for vint_address in vtyp_rom'range loop
            readline(rom_file, v_line);
            hread(v_line, vu16_word);
            vtyp_rom(vint_address) := vu16_word(7 downto 0) & vu16_word(15 downto 8);
        end loop;
        return vtyp_rom;
    end function;
    constant CUX_ROM : t_rom := read_rom;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_request, s_write, s_response_valid : std_logic := '0';
    signal su24_address : unsigned(23 downto 0);
    signal su16_data, su16_response_data : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes : unsigned(1 downto 0);
begin
    s_clk <= not s_clk after 10417 ps;
    s_reset <= '0' after 1 us;
    cpu : entity work.rabbitpunch_maincpu
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pause => '0',
            o_interrupt_acknowledge => open,
            o_request => s_request,
            o_request_write => s_write,
            ou24_request_address => su24_address,
            ou16_request_data => su16_data,
            ou2_request_bytes => su2_bytes,
            i_response_valid => s_response_valid,
            iu16_response_data => su16_response_data,
            o_paused => open
        );
    memory : process(s_clk)
        variable vint_delay : natural := 0;
        variable vint_bitmap_words : natural := 0;
        variable vu4_seen_inputs : unsigned(3 downto 0) := (others => '0');
        variable v_passed : boolean := false;
    begin
        if (rising_edge(s_clk)) then
            s_response_valid <= '0';
            if (vint_delay > 0) then
                vint_delay := vint_delay - 1;
                if (vint_delay = 0) then
                    s_response_valid <= '1';
                end if;
            end if;
            if (s_request = '1') then
                assert (vint_delay = 0) report "Overlapping diagnostic CPU requests" severity failure;
                vint_delay := 3 + (to_integer(su24_address(3 downto 1)) mod 4);
                if (s_write = '0') then
                    if (su24_address < 16#040000#) then
                        su16_response_data <= CUX_ROM(to_integer(su24_address(17 downto 1)));
                        if (GBOOL_CORRUPT_ROM and su24_address = 16#020000#) then
                            su16_response_data <= CUX_ROM(65536) xor x"0001";
                        end if;
                    else
                        case to_integer(su24_address) is
                            when 16#0C0018# => su16_response_data <= x"A512";
                            when 16#0C001A# => su16_response_data <= x"5A34";
                            when 16#0C001C# => su16_response_data <= x"9876";
                            when others =>
                                assert false report "Unexpected diagnostic read address" severity failure;
                        end case;
                    end if;
                else
                    assert (su2_bytes = "11") report "Diagnostic write was not a full word" severity failure;
                    if (su24_address >= 16#040000# and su24_address < 16#050000#) then
                        assert (su24_address = 16#040000# + vint_bitmap_words * 2 and su16_data = x"1234")
                            report "Diagnostic bitmap loop address/data mismatch" severity failure;
                        vint_bitmap_words := vint_bitmap_words + 1;
                    elsif (su24_address = 16#0FC000#) then
                        assert (vint_bitmap_words = GINT_FILL_WORDS)
                            report "Diagnostic skipped part of bitmap fill" severity failure;
                        if (GBOOL_CORRUPT_ROM) then
                            assert (su16_data = x"DEAD") report "Corrupt ROM was accepted" severity failure;
                            report "DIAGNOSTIC_ROM_NEGATIVE_PASS";
                            finish;
                        else
                            assert (su16_data = x"CAFE") report "Known ROM word failed self-test" severity failure;
                            v_passed := true;
                        end if;
                    elsif (su24_address >= 16#0FC002# and su24_address <= 16#0FC008#) then
                        assert (v_passed) report "Diagnostic entered input loop before ROM check" severity failure;
                        case to_integer(su24_address) is
                            when 16#0FC002# =>
                                assert (su16_data = x"A512") severity failure;
                                vu4_seen_inputs(0) := '1';
                            when 16#0FC004# =>
                                assert (su16_data = x"5A34") severity failure;
                                vu4_seen_inputs(1) := '1';
                            when 16#0FC006# =>
                                assert (su16_data = x"9876") severity failure;
                                vu4_seen_inputs(2) := '1';
                            when 16#0FC008# =>
                                assert (su16_data = x"BEEF" and vu4_seen_inputs(2 downto 0) = "111")
                                    report "Diagnostic control copy or heartbeat failed" severity failure;
                                report "DIAGNOSTIC_ROM_PASS";
                                finish;
                            when others => null;
                        end case;
                    else
                        assert (su24_address = 16#0A0402# or su24_address = 16#0A0404# or
                                su24_address = 16#0A0406# or su24_address = 16#0A0408# or
                                su24_address = 16#0C000C# or su24_address = 16#0C0010#)
                            report "Unexpected diagnostic write address" severity failure;
                    end if;
                end if;
            end if;
        end if;
    end process;
    timeout : process
    begin
        wait for 200 ms;
        assert false report "Diagnostic ROM timeout" severity failure;
    end process;
end architecture;
