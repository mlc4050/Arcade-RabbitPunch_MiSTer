-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_header_tb is
end entity;

architecture test of state_header_tb is
    -- Independent Python struct.pack/zlib fixture; low-address byte at bit zero.
    constant CU512_EXPECTED : unsigned(511 downto 0) :=
        x"00000000C413E7B30000000800000008000000080000000800000008000000080000007090ABCDEF052021710000003055667788102030400040000131535052";
    constant CU192_SECTIONS : unsigned(191 downto 0) :=
        x"000000080000000800000008000000080000000800000008";
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel : std_logic := '0';
    signal s_rom_valid : std_logic := '1';
    signal s_busy, s_header_valid, s_error : std_logic;
    signal su192_sections : unsigned(191 downto 0) := CU192_SECTIONS;
    signal su32_abi : unsigned(31 downto 0) := x"10203040";
    signal su512_header : unsigned(511 downto 0);
    signal s_check_start, s_byte_valid, s_finish : std_logic := '0';
    signal s_ready, s_active, s_finished, s_valid : std_logic;
    signal su4_check_error : unsigned(3 downto 0);
    signal su8_data : unsigned(7 downto 0) := (others => '0');
begin
    s_clk <= not s_clk after 5 ns;
    header : entity work.rabbitpunch_state_header
        generic map (
            GINT_BODY_BYTES => 48
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            i_rom_identity_valid => s_rom_valid,
            iu32_abi_signature => su32_abi,
            iu32_rom_identity => x"55667788",
            iu32_config_identity => x"90ABCDEF",
            iu32_body_crc => x"05202171",
            iu192_section_bytes => su192_sections,
            o_busy => s_busy,
            o_valid => s_header_valid,
            o_error => s_error,
            ou512_header => su512_header
        );
    preflight : entity work.rabbitpunch_state_preflight
        generic map (
            GINT_BODY_BYTES => 48
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_check_start,
            iu32_payload_words => to_unsigned(28, 32),
            iu32_abi_signature => x"10203040",
            i_rom_identity_valid => '1',
            iu32_rom_identity => x"55667788",
            iu32_config_identity => x"90ABCDEF",
            iu192_section_bytes => CU192_SECTIONS,
            i_byte_valid => s_byte_valid,
            o_byte_ready => s_ready,
            iu8_byte_data => su8_data,
            i_finish => s_finish,
            i_abort => '0',
            o_active => s_active,
            o_finished => s_finished,
            o_valid => s_valid,
            ou4_error => su4_check_error
        );
    stimulus : process
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure start_header is
        begin
            s_start <= '1';
            cycles;
            s_start <= '0';
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        for vint_round in 0 to 2 loop
            start_header;
            assert (s_busy = '1' and s_header_valid = '0') severity failure;
            -- Inputs belong to the accepted transaction; later changes do not
            -- alter its captured fields. The parent must cancel on ROM reload.
            su32_abi <= x"FFFFFFFF";
            cycles(55);
            assert (s_header_valid = '0' and s_busy = '1') severity failure;
            cycles;
            assert (s_header_valid = '1' and s_busy = '0' and s_error = '0' and
                su512_header = CU512_EXPECTED) report "Header differs from zlib fixture" severity failure;
            su32_abi <= x"10203040";
            cycles(4);
            assert (su512_header = CU512_EXPECTED) severity failure;
            s_check_start <= '1';
            cycles;
            s_check_start <= '0';
            for vint_byte in 0 to 111 loop
                s_byte_valid <= '0';
                if (vint_byte mod 7 = 0) then
                    cycles(3);
                end if;
                assert (s_ready = '1') severity failure;
                if (vint_byte < 64) then
                    su8_data <= su512_header(8*vint_byte + 7 downto 8*vint_byte);
                else
                    su8_data <= to_unsigned(vint_byte - 64, 8);
                end if;
                s_byte_valid <= '1';
                if (vint_byte = 111) then
                    s_finish <= '1';
                end if;
                cycles;
            end loop;
            s_byte_valid <= '0';
            s_finish <= '0';
            assert (s_finished = '1' and s_valid = '1' and su4_check_error = 0)
                report "Constructed header/body rejected by preflight" severity failure;
        end loop;
        -- Cancel must suppress a delayed publication, including the last CRC edge.
        for vint_delay in 0 to 55 loop
            start_header;
            if (vint_delay > 0) then
                cycles(vint_delay);
            end if;
            s_cancel <= '1';
            cycles;
            s_cancel <= '0';
            cycles(60);
            assert (s_header_valid = '0' and s_busy = '0') severity failure;
        end loop;
        s_rom_valid <= '0';
        start_header;
        assert (s_error = '1' and s_busy = '0' and s_header_valid = '0') severity failure;
        s_rom_valid <= '1';
        su192_sections <= (others => '1');
        start_header;
        assert (s_error = '1' and s_busy = '0') severity failure;
        su192_sections <= CU192_SECTIONS;
        su192_sections(31 downto 0) <= to_unsigned(7, 32);
        su192_sections(63 downto 32) <= to_unsigned(9, 32);
        start_header;
        assert (s_error = '1' and s_busy = '0') severity failure;
        su192_sections <= (others => '0');
        start_header;
        assert (s_error = '1' and s_busy = '0') severity failure;
        su192_sections <= CU192_SECTIONS;
        start_header;
        cycles(56);
        assert (s_header_valid = '1' and s_error = '0' and su512_header = CU512_EXPECTED) severity failure;
        report "STATE_HEADER_PASS three preflight roundtrips,56 cancellation edges,four rejects,retry" severity note;
        stop;
        wait;
    end process;
end architecture;
