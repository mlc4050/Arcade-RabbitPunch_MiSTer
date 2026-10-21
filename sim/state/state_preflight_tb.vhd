-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_crc.all;

entity state_preflight_tb is
end entity;

architecture test of state_preflight_tb is
    type t_bytes is array(0 to 112) of unsigned(7 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_byte, s_finish, s_abort : std_logic := '0';
    signal s_rom_valid : std_logic := '1';
    signal s_ready, s_active, s_finished, s_valid : std_logic;
    signal su32_words : unsigned(31 downto 0) := to_unsigned(28, 32);
    signal su32_rom : unsigned(31 downto 0) := x"55667788";
    signal su32_config : unsigned(31 downto 0) := x"90ABCDEF";
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal su4_error : unsigned(3 downto 0);
    procedure P_WORD(variable vu8_image : inout t_bytes; vint_word : natural;
        vu32_data : unsigned(31 downto 0)) is
    begin
        for vint_byte in 0 to 3 loop
            vu8_image(4*vint_word + vint_byte) := vu32_data(8*vint_byte + 7 downto 8*vint_byte);
        end loop;
    end procedure;
    procedure P_HEADER_CRC(variable vu8_image : inout t_bytes) is
        variable vu32_crc : unsigned(31 downto 0) := CU32_CRC_SEED;
    begin
        for vint_byte in 0 to 55 loop
            vu32_crc := F_CRC32_BYTE(vu32_crc, vu8_image(vint_byte));
        end loop;
        P_WORD(vu8_image, 14, not vu32_crc);
    end procedure;
    function F_IMAGE return t_bytes is
        variable vu8_image : t_bytes := (others => (others => '0'));
    begin
        P_WORD(vu8_image, 0, x"31535052");
        P_WORD(vu8_image, 1, x"00400001");
        P_WORD(vu8_image, 2, x"10203040");
        P_WORD(vu8_image, 3, x"55667788");
        P_WORD(vu8_image, 4, to_unsigned(48, 32));
        -- Independent zlib CRC-32 reference for bytes 0..47.
        P_WORD(vu8_image, 5, x"05202171");
        P_WORD(vu8_image, 6, x"90ABCDEF");
        P_WORD(vu8_image, 7, to_unsigned(112, 32));
        for vint_section in 0 to 5 loop
            P_WORD(vu8_image, 8 + vint_section, to_unsigned(8, 32));
        end loop;
        for vint_byte in 0 to 47 loop
            vu8_image(64 + vint_byte) := to_unsigned(vint_byte, 8);
        end loop;
        P_HEADER_CRC(vu8_image);
        return vu8_image;
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    preflight : entity work.rabbitpunch_state_preflight
        generic map (
            GINT_BODY_BYTES => 48
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            iu32_payload_words => su32_words,
            iu32_abi_signature => x"10203040",
            i_rom_identity_valid => s_rom_valid,
            iu32_rom_identity => su32_rom,
            iu32_config_identity => su32_config,
            iu192_section_bytes => x"000000080000000800000008000000080000000800000008",
            i_byte_valid => s_byte,
            o_byte_ready => s_ready,
            iu8_byte_data => su8_data,
            i_finish => s_finish,
            i_abort => s_abort,
            o_active => s_active,
            o_finished => s_finished,
            o_valid => s_valid,
            ou4_error => su4_error
        );
    stimulus : process
        variable vu8_image : t_bytes;
        variable vu4_expected : unsigned(3 downto 0);
        variable vint_length : positive;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
    begin
        s_initialize <= '1';
        cycles(2);
        s_initialize <= '0';
        for vint_case in 0 to 20 loop
            vu8_image := F_IMAGE;
            vu4_expected := x"0";
            vint_length := 112;
            su32_words <= to_unsigned(28, 32);
            su32_rom <= x"55667788";
            su32_config <= x"90ABCDEF";
            s_rom_valid <= '1';
            case vint_case is
                when 1 =>
                    P_WORD(vu8_image, 0, x"00000000");
                    vu4_expected := x"2";
                when 2 =>
                    P_WORD(vu8_image, 1, x"00400002");
                    vu4_expected := x"D";
                when 3 =>
                    P_WORD(vu8_image, 2, x"FFFFFFFF");
                    vu4_expected := x"3";
                when 4 =>
                    P_WORD(vu8_image, 3, x"55667789");
                    vu4_expected := x"4";
                when 5 =>
                    P_WORD(vu8_image, 6, x"00000000");
                    vu4_expected := x"5";
                when 6 =>
                    su32_words <= to_unsigned(27, 32);
                    vu4_expected := x"1";
                when 7 =>
                    P_WORD(vu8_image, 4, to_unsigned(40, 32));
                    vu4_expected := x"1";
                when 8 =>
                    P_WORD(vu8_image, 7, to_unsigned(108, 32));
                    vu4_expected := x"1";
                when 9 =>
                    P_WORD(vu8_image, 8, x"FFFFFFFF");
                    vu4_expected := x"8";
                when 10 =>
                    vu4_expected := x"6";
                when 11 =>
                    vu8_image(80) := vu8_image(80) xor x"01";
                    vu4_expected := x"7";
                when 12 =>
                    P_WORD(vu8_image, 15, to_unsigned(1, 32));
                    vu4_expected := x"C";
                when 13 =>
                    vint_length := 70;
                    vu4_expected := x"A";
                when 14 =>
                    vint_length := 113;
                    vu4_expected := x"B";
                when 15 =>
                    vu4_expected := x"5";
                when 16 | 17 | 19 =>
                    vu4_expected := x"4";
                when 18 =>
                    vu4_expected := x"9";
                when others => null;
            end case;
            P_HEADER_CRC(vu8_image);
            if (vint_case = 10) then
                P_WORD(vu8_image, 14, x"00000000");
            end if;
            if (vint_case = 19) then
                s_rom_valid <= '0';
            end if;
            s_start <= '1';
            cycles;
            s_start <= '0';
            wait for 1 ns;
            assert (s_active = '1' and s_valid = '0' and s_ready = '1') severity failure;
            for vint_byte in 0 to vint_length - 1 loop
                if (vint_byte mod 7 = 0) then
                    s_byte <= '0';
                    su8_data <= x"FF";
                    cycles(2);
                end if;
                if (vint_byte = 80) then
                    if (vint_case = 15) then
                        su32_config <= x"90ABCDEE";
                    elsif (vint_case = 16) then
                        s_rom_valid <= '0';
                    elsif (vint_case = 17) then
                        su32_rom <= x"55667789";
                    end if;
                end if;
                su8_data <= vu8_image(vint_byte);
                s_byte <= '1';
                if (vint_case = 0 and vint_byte = vint_length - 1) then
                    s_finish <= '1';
                end if;
                cycles;
                s_byte <= '0';
                if (vint_case = 18 and vint_byte = 80) then
                    exit;
                end if;
                if (vint_byte /= vint_length - 1) then
                    assert (s_valid = '0' and s_finished = '0') severity failure;
                end if;
            end loop;
            if (vint_case = 18) then
                s_abort <= '1';
                cycles;
                s_abort <= '0';
            elsif (vint_case /= 0) then
                s_finish <= '1';
                cycles;
            end if;
            s_finish <= '0';
            assert (s_finished = '1' and s_active = '0' and su4_error = vu4_expected and
                ((s_valid = '1') = (vu4_expected = 0)))
                report "Preflight case " & integer'image(vint_case) & " returned " & to_hstring(su4_error)
                severity failure;
            -- Late canceled bytes must not re-open or validate the old image.
            if (vint_case = 18) then
                s_byte <= '1';
                cycles(3);
                s_byte <= '0';
                assert (s_valid = '0' and s_finished = '0' and su4_error = x"9") severity failure;
            end if;
            cycles(2);
        end loop;
        report "STATE_PREFLIGHT_PASS cases=21 stalled_stream=checked wrong_rom_abi_config_crc_size=rejected";
        finish;
        wait;
    end process;
end architecture;
