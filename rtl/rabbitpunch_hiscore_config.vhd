-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standard 16-byte hiscore header plus one eight-byte CFG_LENGTHWIDTH=2
-- record. The acknowledged engine supports one write pass, two-clock minimum
-- hold descriptors, no fixed pause padding and no change-mask extension.
-- Unsupported descriptors fail closed instead of writing an arbitrary address.
entity rabbitpunch_hiscore_config is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_download : in std_logic;
        iu16_file_index : in unsigned(15 downto 0);
        i_write : in std_logic;
        iu27_byte_address : in unsigned(26 downto 0);
        iu8_data : in unsigned(7 downto 0);
        o_profile_valid : out std_logic;
        o_us_set : out std_logic;
        ou32_start_wait : out unsigned(31 downto 0);
        ou16_check_wait : out unsigned(15 downto 0);
        o_error : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_hiscore_config is
    signal s_config, s_old_config, s_bad : std_logic := '0';
    signal su5_count : unsigned(4 downto 0) := (others => '0');
    signal su192_packet : unsigned(191 downto 0) := (others => '0');
begin
    s_config <= '1' when i_download = '1' and iu16_file_index = 3 else '0';
    process(i_clk)
        variable v_valid_header, v_japan, v_us : boolean;
    begin
        if (rising_edge(i_clk)) then
            s_old_config <= s_config;
            if (i_initialize = '1' or (i_download = '1' and iu16_file_index = 0)) then
                o_profile_valid <= '0';
                o_us_set <= '0';
                ou32_start_wait <= (others => '0');
                ou16_check_wait <= (others => '0');
                o_error <= '0';
                s_bad <= '0';
                su5_count <= (others => '0');
            elsif (s_config = '1') then
                if (s_old_config = '0') then
                    o_profile_valid <= '0';
                    o_error <= '0';
                    s_bad <= '0';
                    su5_count <= (others => '0');
                    su192_packet <= (others => '0');
                end if;
                if (i_write = '1') then
                    if (s_old_config = '1' and s_bad = '0' and su5_count < 24 and
                        iu27_byte_address = resize(su5_count, 27)) then
                        su192_packet <= su192_packet(183 downto 0) & iu8_data;
                        su5_count <= su5_count + 1;
                    else
                        s_bad <= '1';
                    end if;
                end if;
            elsif (s_old_config = '1') then
                v_valid_header := su192_packet(143 downto 128) = 2 and
                    su192_packet(127 downto 112) = 2 and su192_packet(111 downto 96) = 1 and
                    su192_packet(95 downto 64) = 0 and su192_packet(63 downto 32) = 16#FFE01# and
                    su192_packet(15 downto 8) = 0;
                v_japan := su192_packet(31 downto 16) = 119 and su192_packet(7 downto 0) = 16#80#;
                v_us := su192_packet(31 downto 16) = 115 and su192_packet(7 downto 0) = 16#17#;
                if (s_bad = '0' and su5_count = 24 and v_valid_header and (v_japan or v_us)) then
                    o_profile_valid <= '1';
                    o_us_set <= '0';
                    if (v_us) then
                        o_us_set <= '1';
                    end if;
                    ou32_start_wait <= su192_packet(191 downto 160);
                    ou16_check_wait <= su192_packet(159 downto 144);
                else
                    o_profile_valid <= '0';
                    o_error <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
