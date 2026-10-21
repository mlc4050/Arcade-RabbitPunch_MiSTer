-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_image_buffer_tb is
end entity;

architecture test of state_image_buffer_tb is
    constant CINT_BYTES : positive := 107280;
    signal s_clk : std_logic := '0';
    signal s_initialize, s_begin, s_cancel, s_fill, s_seal, s_read : std_logic := '0';
    signal s_ready, s_sealed, s_error, s_response, s_read_error : std_logic;
    signal su8_fill, su8_read : unsigned(7 downto 0) := (others => '0');
    signal su18_count, su18_address : unsigned(17 downto 0) := (others => '0');
    function F_BYTE(vint_address, vint_round : natural) return unsigned is
    begin
        return to_unsigned((vint_address*17 + vint_address/251 + vint_round*73) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    buffer_ram : entity work.rabbitpunch_state_image_buffer
        generic map (
            GINT_IMAGE_BYTES => CINT_BYTES
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_begin => s_begin,
            i_cancel => s_cancel,
            i_fill_valid => s_fill,
            o_fill_ready => s_ready,
            iu8_fill_data => su8_fill,
            i_seal => s_seal,
            o_sealed => s_sealed,
            o_error => s_error,
            ou18_filled_bytes => su18_count,
            i_read_valid => s_read,
            iu18_read_address => su18_address,
            o_read_response => s_response,
            o_read_error => s_read_error,
            ou8_read_data => su8_read
        );
    stimulus : process
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure begin_image is
        begin
            s_begin <= '1';
            cycles;
            s_begin <= '0';
            wait for 1 ns;
            assert (s_sealed = '0' and s_response = '0' and su18_count = 0 and s_ready = '1') severity failure;
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        s_read <= '1';
        cycles(3);
        assert (s_response = '0' and s_ready = '0') severity failure;
        s_read <= '0';
        begin_image;
        s_fill <= '1';
        su8_fill <= x"AA";
        cycles(100);
        s_fill <= '0';
        s_seal <= '1';
        cycles;
        s_seal <= '0';
        assert (s_error = '1' and s_sealed = '0' and s_ready = '0') severity failure;
        for vint_round in 0 to 2 loop
            begin_image;
            for vint_byte in 0 to CINT_BYTES - 1 loop
                if (vint_byte mod 257 = 0) then
                    s_fill <= '0';
                    cycles(2);
                end if;
                assert (s_ready = '1') severity failure;
                su8_fill <= F_BYTE(vint_byte, vint_round);
                s_fill <= '1';
                -- The final byte and seal share an edge.
                if (vint_byte = CINT_BYTES - 1) then
                    s_seal <= '1';
                end if;
                cycles;
            end loop;
            s_seal <= '0';
            assert (s_sealed = '1' and s_ready = '0' and s_error = '0' and
                su18_count = CINT_BYTES) severity failure;
            -- Keep a hostile writer asserted while reading. It cannot mutate
            -- the sealed copy used by validation and eventual application.
            su8_fill <= x"00";
            s_read <= '1';
            for vint_byte in CINT_BYTES - 1 downto 0 loop
                su18_address <= to_unsigned(vint_byte, 18);
                cycles;
                assert (s_response = '1' and s_read_error = '0' and
                    su8_read = F_BYTE(vint_byte, vint_round)) report "Sealed image byte changed" severity failure;
            end loop;
            su18_address <= to_unsigned(CINT_BYTES, 18);
            cycles;
            assert (s_response = '1' and s_read_error = '1') severity failure;
            su18_address <= to_unsigned(262143, 18);
            cycles;
            assert (s_response = '1' and s_read_error = '1') severity failure;
            s_fill <= '0';
            -- Session replacement suppresses read requests on its boundary.
            begin_image;
            cycles;
            assert (s_response = '0' and s_sealed = '0') severity failure;
            s_read <= '0';
            s_seal <= '1';
            cycles;
            s_seal <= '0';
            assert (s_error = '1' and s_sealed = '0') severity failure;
            s_cancel <= '1';
            cycles;
            s_cancel <= '0';
            assert (s_ready = '0' and s_sealed = '0' and su18_count = 0) severity failure;
        end loop;
        report "STATE_IMAGE_BUFFER_PASS three107280-byte fills/reverse reads,stalls,sealed write protection,partial seal,range errors,session cancellation" severity note;
        stop;
        wait;
    end process;
end architecture;
