-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_crc.all;

-- Validate the board payload before any CPU/RAM/chip load. The standard host
-- control word is excluded from this stream. Header: sixteen little-endian
-- words: magic, version/header-size, ABI, ROM CRC, body bytes, body CRC, config,
-- total bytes, six section sizes, header CRC (first56bytes), reserved zero.
-- This checks framing/compatibility/integrity, not field-specific CPU/beam bounds.
-- Caller must add those semantic checks and keep the source slot immutable
-- between preflight and application. Canceled DDR debt belongs to the caller.
entity rabbitpunch_state_preflight is
    generic (
        GINT_BODY_BYTES : positive
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        iu32_payload_words : in unsigned(31 downto 0);
        iu32_abi_signature : in unsigned(31 downto 0);
        i_rom_identity_valid : in std_logic;
        iu32_rom_identity : in unsigned(31 downto 0);
        iu32_config_identity : in unsigned(31 downto 0);
        iu192_section_bytes : in unsigned(191 downto 0);
        i_byte_valid : in std_logic;
        o_byte_ready : out std_logic;
        iu8_byte_data : in unsigned(7 downto 0);
        i_finish : in std_logic;
        i_abort : in std_logic;
        o_active : out std_logic;
        o_finished : out std_logic;
        o_valid : out std_logic;
        ou4_error : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_preflight is
    constant CU4_NONE : unsigned(3 downto 0) := x"0";
    constant CU4_LENGTH : unsigned(3 downto 0) := x"1";
    constant CU4_MAGIC : unsigned(3 downto 0) := x"2";
    constant CU4_ABI : unsigned(3 downto 0) := x"3";
    constant CU4_ROM : unsigned(3 downto 0) := x"4";
    constant CU4_CONFIG : unsigned(3 downto 0) := x"5";
    constant CU4_HEADER_CRC : unsigned(3 downto 0) := x"6";
    constant CU4_BODY_CRC : unsigned(3 downto 0) := x"7";
    constant CU4_SECTIONS : unsigned(3 downto 0) := x"8";
    constant CU4_ABORT : unsigned(3 downto 0) := x"9";
    constant CU4_TRUNCATED : unsigned(3 downto 0) := x"A";
    constant CU4_OVERSIZE : unsigned(3 downto 0) := x"B";
    constant CU4_RESERVED : unsigned(3 downto 0) := x"C";
    constant CU4_VERSION : unsigned(3 downto 0) := x"D";
    signal s_active, s_valid : std_logic := '0';
    signal su4_error : unsigned(3 downto 0) := CU4_NONE;
    signal su19_count : unsigned(18 downto 0) := (others => '0');
    signal su512_header : unsigned(511 downto 0) := (others => '0');
    signal su32_header_crc, su32_body_crc : unsigned(31 downto 0) := CU32_CRC_SEED;
    signal su32_abi, su32_rom, su32_config : unsigned(31 downto 0) := (others => '0');
    signal su192_sections : unsigned(191 downto 0) := (others => '0');
    function F_WORD(vu512_header : unsigned(511 downto 0); vint_word : natural) return unsigned is
    begin
        return vu512_header(32*vint_word + 31 downto 32*vint_word);
    end function;
begin
    assert (GINT_BODY_BYTES mod 8 = 0 and GINT_BODY_BYTES <= 262072)
        report "State body must fit the host slot and use eight-byte section alignment" severity failure;
    o_active <= s_active;
    o_valid <= s_valid;
    ou4_error <= su4_error;
    o_byte_ready <= s_active and not i_initialize and not i_abort and not i_start;
    validate : process(i_clk)
        variable vu19_count : unsigned(18 downto 0);
        variable vu512_header : unsigned(511 downto 0);
        variable vu32_header_crc, vu32_body_crc : unsigned(31 downto 0);
        variable vu4_error : unsigned(3 downto 0);
        variable vu35_section_sum : unsigned(34 downto 0);
        variable vint_byte : natural;
        variable vint_header_byte : natural range 0 to 63;
        variable v_sections_bad : boolean;
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            if (i_initialize = '1') then
                s_active <= '0';
                s_valid <= '0';
                su4_error <= CU4_NONE;
                su19_count <= (others => '0');
            elsif (i_abort = '1') then
                o_finished <= s_active;
                s_active <= '0';
                s_valid <= '0';
                su4_error <= CU4_ABORT;
            elsif (i_start = '1') then
                assert (s_active = '0') report "State preflight restarted before completion" severity failure;
                s_active <= '1';
                s_valid <= '0';
                su4_error <= CU4_NONE;
                su19_count <= (others => '0');
                su512_header <= (others => '0');
                su32_header_crc <= CU32_CRC_SEED;
                su32_body_crc <= CU32_CRC_SEED;
                su32_abi <= iu32_abi_signature;
                su32_rom <= iu32_rom_identity;
                su32_config <= iu32_config_identity;
                su192_sections <= iu192_section_bytes;
                if (iu32_payload_words /= (GINT_BODY_BYTES + 64)/4) then
                    su4_error <= CU4_LENGTH;
                elsif (i_rom_identity_valid = '0') then
                    su4_error <= CU4_ROM;
                end if;
            elsif (s_active = '1') then
                vu19_count := su19_count;
                vu512_header := su512_header;
                vu32_header_crc := su32_header_crc;
                vu32_body_crc := su32_body_crc;
                vu4_error := su4_error;
                if (i_byte_valid = '1' and o_byte_ready = '1') then
                    vint_byte := to_integer(vu19_count);
                    if (vint_byte < 64) then
                        vint_header_byte := to_integer(vu19_count(5 downto 0));
                        vu512_header(8*vint_header_byte + 7 downto 8*vint_header_byte) := iu8_byte_data;
                        if (vint_byte < 56) then
                            vu32_header_crc := F_CRC32_BYTE(vu32_header_crc, iu8_byte_data);
                        end if;
                    elsif (vint_byte < GINT_BODY_BYTES + 64) then
                        vu32_body_crc := F_CRC32_BYTE(vu32_body_crc, iu8_byte_data);
                    elsif (vu4_error = CU4_NONE) then
                        vu4_error := CU4_OVERSIZE;
                    end if;
                    if (vint_byte <= GINT_BODY_BYTES + 64) then
                        vu19_count := vu19_count + 1;
                    end if;
                    if (vint_byte = 63 and vu4_error = CU4_NONE) then
                        vu35_section_sum := (others => '0');
                        v_sections_bad := false;
                        for vint_section in 0 to 5 loop
                            vu35_section_sum := vu35_section_sum + resize(F_WORD(vu512_header, 8 + vint_section), 35);
                            if (F_WORD(vu512_header, 8 + vint_section) /=
                                su192_sections(32*vint_section + 31 downto 32*vint_section)) then
                                v_sections_bad := true;
                            end if;
                        end loop;
                        if (not vu32_header_crc /= F_WORD(vu512_header, 14)) then
                            vu4_error := CU4_HEADER_CRC;
                        elsif (F_WORD(vu512_header, 0) /= x"31535052") then
                            vu4_error := CU4_MAGIC;
                        elsif (F_WORD(vu512_header, 1) /= x"00400001") then
                            vu4_error := CU4_VERSION;
                        elsif (F_WORD(vu512_header, 2) /= su32_abi) then
                            vu4_error := CU4_ABI;
                        elsif (F_WORD(vu512_header, 3) /= su32_rom) then
                            vu4_error := CU4_ROM;
                        elsif (F_WORD(vu512_header, 6) /= su32_config) then
                            vu4_error := CU4_CONFIG;
                        elsif (F_WORD(vu512_header, 4) /= GINT_BODY_BYTES or
                            F_WORD(vu512_header, 7) /= GINT_BODY_BYTES + 64) then
                            vu4_error := CU4_LENGTH;
                        elsif (F_WORD(vu512_header, 15) /= 0) then
                            vu4_error := CU4_RESERVED;
                        elsif (v_sections_bad or vu35_section_sum /= GINT_BODY_BYTES) then
                            vu4_error := CU4_SECTIONS;
                        end if;
                    end if;
                end if;
                if (i_finish = '1') then
                    s_active <= '0';
                    o_finished <= '1';
                    if (vu4_error = CU4_NONE) then
                        if (vu19_count /= GINT_BODY_BYTES + 64) then
                            vu4_error := CU4_TRUNCATED;
                        elsif (not vu32_body_crc /= F_WORD(vu512_header, 5)) then
                            vu4_error := CU4_BODY_CRC;
                        elsif (i_rom_identity_valid = '0' or iu32_rom_identity /= su32_rom) then
                            vu4_error := CU4_ROM;
                        elsif (iu32_config_identity /= su32_config) then
                            vu4_error := CU4_CONFIG;
                        end if;
                    end if;
                    if (vu4_error = CU4_NONE) then
                        s_valid <= '1';
                    end if;
                end if;
                su19_count <= vu19_count;
                su512_header <= vu512_header;
                su32_header_crc <= vu32_header_crc;
                su32_body_crc <= vu32_body_crc;
                su4_error <= vu4_error;
            end if;
        end if;
    end process;
end architecture;
