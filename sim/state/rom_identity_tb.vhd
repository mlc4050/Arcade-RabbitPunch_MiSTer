-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_crc.all;

entity rom_identity_tb is
end entity;

architecture test of rom_identity_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_begin, s_word, s_finish, s_committed : std_logic := '0';
    signal s_active, s_valid, s_error : std_logic;
    signal su27_address : unsigned(26 downto 0) := (others => '0');
    signal su16_data : unsigned(15 downto 0) := (others => '0');
    signal su32_identity : unsigned(31 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    identity : entity work.rabbitpunch_rom_identity
        generic map (
            GINT_IMAGE_BYTES => 8
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_begin => s_begin,
            i_word_accepted => s_word,
            iu27_word_byte_address => su27_address,
            iu16_word_data => su16_data,
            i_finish => s_finish,
            i_image_committed => s_committed,
            o_active => s_active,
            o_valid => s_valid,
            o_error => s_error,
            ou32_identity => su32_identity
        );
    stimulus : process
        variable vu32_crc : unsigned(31 downto 0);
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure begin_image is
        begin
            s_begin <= '1';
            cycles;
            s_begin <= '0';
            assert (s_valid = '0' and su32_identity = 0 and s_active = '1' and s_error = '0')
                report "New ROM retained stale identity" severity failure;
        end procedure;
        procedure word(vint_address, vint_data : natural) is
        begin
            su27_address <= to_unsigned(vint_address, 27);
            su16_data <= to_unsigned(vint_data, 16);
            s_word <= '1';
            cycles;
            s_word <= '0';
            cycles(3);
            assert (s_valid = '0') report "Identity published before loader commit" severity failure;
        end procedure;
        procedure finish_image(v_committed : boolean; v_valid : boolean) is
        begin
            s_finish <= '1';
            if (v_committed) then
                s_committed <= '1';
            else
                s_committed <= '0';
            end if;
            cycles;
            s_finish <= '0';
            s_committed <= '0';
            s_word <= '0';
            assert ((s_valid = '1') = v_valid and s_active = '0') severity failure;
            if (not v_valid) then
                assert (s_error = '1' and su32_identity = 0) severity failure;
            end if;
            cycles;
        end procedure;
        procedure digits is
        begin
            word(0, 16#3231#);
            word(2, 16#3433#);
            word(4, 16#3635#);
            word(6, 16#3837#);
        end procedure;
    begin
        vu32_crc := CU32_CRC_SEED;
        for vint_byte in 16#31# to 16#39# loop
            vu32_crc := F_CRC32_BYTE(vu32_crc, to_unsigned(vint_byte, 8));
        end loop;
        assert (not vu32_crc = x"CBF43926") report "CRC-32 standard check differs" severity failure;
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        cycles;
        for vint_round in 1 to 3 loop
            begin_image;
            digits;
            finish_image(true, true);
            assert (su32_identity = x"9AE0DAAF") report "Download byte order/CRC differs" severity failure;
            cycles(8);
            assert (s_valid = '1' and su32_identity = x"9AE0DAAF") severity failure;
        end loop;
        begin_image;
        word(0, 16#6261#);
        word(2, 16#6463#);
        word(4, 16#6665#);
        -- Accept the final word and downstream completion on the same edge.
        su27_address <= to_unsigned(6, 27);
        su16_data <= x"6867";
        s_word <= '1';
        finish_image(true, true);
        s_word <= '0';
        assert (su32_identity = x"AEEF2A50") report "Replacement ROM retained old CRC" severity failure;
        cycles;
        begin_image;
        word(0, 16#3231#);
        finish_image(true, false);
        begin_image;
        word(2, 16#3433#);
        digits;
        finish_image(true, false);
        begin_image;
        digits;
        word(8, 0);
        finish_image(true, false);
        begin_image;
        digits;
        finish_image(false, false);
        begin_image;
        digits;
        finish_image(true, true);
        s_initialize <= '1';
        cycles;
        assert (s_valid = '0' and s_active = '0' and su32_identity = 0) severity failure;
        report "ROM_IDENTITY_PASS ieee_check=CBF43926 repeat=3 replacement=checked invalid_images=rejected";
        finish;
        wait;
    end process;
end architecture;
