-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_crc.all;

-- Construct the board payload header after the immutable body's CRC is known.
-- One CRC byte per clock avoids a 56-byte combinational CRC path. The host's
-- outer change-counter word is separate and must be published last by a parent.
entity rabbitpunch_state_header is
    generic (
        GINT_BODY_BYTES : positive
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        i_rom_identity_valid : in std_logic;
        iu32_abi_signature : in unsigned(31 downto 0);
        iu32_rom_identity : in unsigned(31 downto 0);
        iu32_config_identity : in unsigned(31 downto 0);
        iu32_body_crc : in unsigned(31 downto 0);
        iu192_section_bytes : in unsigned(191 downto 0);
        o_busy : out std_logic;
        o_valid : out std_logic;
        o_error : out std_logic;
        ou512_header : out unsigned(511 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_header is
    signal s_busy, s_valid, s_error : std_logic := '0';
    signal su512_header : unsigned(511 downto 0) := (others => '0');
    signal su32_crc : unsigned(31 downto 0) := CU32_CRC_SEED;
    signal sint_byte : natural range 0 to 55 := 0;
begin
    assert (GINT_BODY_BYTES mod 8 = 0 and GINT_BODY_BYTES <= 262072)
        report "State body must fit the host slot and use eight-byte alignment" severity failure;
    o_busy <= s_busy;
    o_valid <= s_valid;
    o_error <= s_error;
    ou512_header <= su512_header;
    construct : process(i_clk)
        variable vu35_sum : unsigned(34 downto 0);
        variable vu32_size, vu32_next_crc : unsigned(31 downto 0);
        variable v_bad : boolean;
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1' or i_cancel = '1') then
                s_busy <= '0';
                s_valid <= '0';
                s_error <= '0';
            elsif (i_start = '1') then
                assert (s_busy = '0') report "State header restarted while busy" severity failure;
                s_valid <= '0';
                s_error <= '0';
                s_busy <= '0';
                vu35_sum := (others => '0');
                v_bad := i_rom_identity_valid /= '1';
                for vint_section in 0 to 5 loop
                    vu32_size := iu192_section_bytes(32*vint_section + 31 downto 32*vint_section);
                    vu35_sum := vu35_sum + resize(vu32_size, 35);
                    if (vu32_size(2 downto 0) /= 0) then
                        v_bad := true;
                    end if;
                end loop;
                if (vu35_sum /= GINT_BODY_BYTES) then
                    v_bad := true;
                end if;
                if (v_bad) then
                    s_error <= '1';
                else
                    su512_header <= (others => '0');
                    su512_header(31 downto 0) <= x"31535052";
                    su512_header(63 downto 32) <= x"00400001";
                    su512_header(95 downto 64) <= iu32_abi_signature;
                    su512_header(127 downto 96) <= iu32_rom_identity;
                    su512_header(159 downto 128) <= to_unsigned(GINT_BODY_BYTES, 32);
                    su512_header(191 downto 160) <= iu32_body_crc;
                    su512_header(223 downto 192) <= iu32_config_identity;
                    su512_header(255 downto 224) <= to_unsigned(GINT_BODY_BYTES + 64, 32);
                    su512_header(447 downto 256) <= iu192_section_bytes;
                    su32_crc <= CU32_CRC_SEED;
                    sint_byte <= 0;
                    s_busy <= '1';
                end if;
            elsif (s_busy = '1') then
                vu32_next_crc := F_CRC32_BYTE(su32_crc,
                    su512_header(8*sint_byte + 7 downto 8*sint_byte));
                su32_crc <= vu32_next_crc;
                if (sint_byte = 55) then
                    su512_header(479 downto 448) <= not vu32_next_crc;
                    s_busy <= '0';
                    s_valid <= '1';
                else
                    sint_byte <= sint_byte + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
