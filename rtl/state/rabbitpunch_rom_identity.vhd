-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_crc.all;

-- Passive observer of accepted, sequential raw-ROM words. Begin invalidates
-- the previous identity immediately. Publish only after the downstream loader
-- confirms that the exact complete image has committed and all debt drained.
-- Game reset must not connect to initialize. CRC is compatibility/integrity
-- metadata, not a cryptographic identity or a replacement for loader validation.
entity rabbitpunch_rom_identity is
    generic (
        GINT_IMAGE_BYTES : positive := 16#210000#
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_begin : in std_logic;
        i_word_accepted : in std_logic;
        iu27_word_byte_address : in unsigned(26 downto 0);
        iu16_word_data : in unsigned(15 downto 0);
        i_finish : in std_logic;
        i_image_committed : in std_logic;
        o_active : out std_logic;
        o_valid : out std_logic;
        o_error : out std_logic;
        ou32_identity : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_rom_identity is
    signal s_active, s_valid, s_error : std_logic := '0';
    signal su27_count : unsigned(26 downto 0) := (others => '0');
    signal su32_crc : unsigned(31 downto 0) := CU32_CRC_SEED;
begin
    assert (GINT_IMAGE_BYTES mod 2 = 0 and GINT_IMAGE_BYTES <= 2**27 - 2)
        report "ROM identity requires an even bounded image" severity failure;
    o_active <= s_active;
    o_valid <= s_valid;
    o_error <= s_error;
    ou32_identity <= not su32_crc when s_valid = '1' else (others => '0');
    observe : process(i_clk)
        variable vu27_count : unsigned(26 downto 0);
        variable vu32_crc : unsigned(31 downto 0);
        variable v_bad : boolean;
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                s_active <= '0';
                s_valid <= '0';
                s_error <= '0';
                su27_count <= (others => '0');
                su32_crc <= CU32_CRC_SEED;
            elsif (i_begin = '1') then
                assert (i_word_accepted = '0' and i_finish = '0')
                    report "ROM identity begin overlaps data or completion" severity failure;
                s_active <= '1';
                s_valid <= '0';
                s_error <= '0';
                su27_count <= (others => '0');
                su32_crc <= CU32_CRC_SEED;
            elsif (s_active = '1') then
                vu27_count := su27_count;
                vu32_crc := su32_crc;
                v_bad := s_error = '1';
                if (i_word_accepted = '1') then
                    if (iu27_word_byte_address = vu27_count and vu27_count < GINT_IMAGE_BYTES) then
                        vu32_crc := F_CRC32_WORD(vu32_crc, iu16_word_data);
                        vu27_count := vu27_count + 2;
                    else
                        v_bad := true;
                    end if;
                end if;
                su27_count <= vu27_count;
                su32_crc <= vu32_crc;
                if (i_finish = '1') then
                    s_active <= '0';
                    if (not v_bad and vu27_count = GINT_IMAGE_BYTES and i_image_committed = '1') then
                        s_valid <= '1';
                    else
                        v_bad := true;
                        s_valid <= '0';
                    end if;
                end if;
                if (v_bad) then
                    s_error <= '1';
                end if;
            else
                assert (i_word_accepted = '0' and i_finish = '0')
                    report "ROM identity event outside a download transaction" severity failure;
            end if;
        end if;
    end process;
end architecture;
