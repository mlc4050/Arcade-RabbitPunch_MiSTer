-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_slot_reader_tb is
end entity;

architecture test of state_slot_reader_tb is
    -- Python struct/zlib board header plus body bytes 0..15, low byte first.
    constant CU640_IMAGE : unsigned(639 downto 0) :=
        x"0F0E0D0C0B0A090807060504030201000000000006D712270000000000000000000000000000000000000008000000080000005090ABCDEFCECEE2880000001055667788102030400040000131535052";
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel : std_logic := '0';
    signal s_byte_valid, s_byte_ready, s_buffer_ready, s_fill_enable : std_logic;
    signal s_active, s_finished, s_success, s_ddr_read, s_ddr_busy : std_logic;
    signal s_ddr_reply : std_logic := '0';
    signal su64_ddr_data : unsigned(63 downto 0) := (others => '0');
    signal su29_address : unsigned(28 downto 0);
    signal su8_byte, su8_buffer_data : unsigned(7 downto 0);
    signal su3_error : unsigned(2 downto 0);
    signal s_sealed, s_buffer_error, s_buffer_read, s_buffer_response, s_buffer_read_error : std_logic := '0';
    signal su18_count, su18_read_address, su18_response_address : unsigned(17 downto 0) := (others => '0');
    signal s_check_start, s_check_finish : std_logic := '0';
    signal s_check_ready, s_check_active, s_check_finished, s_check_valid : std_logic;
    signal su4_check_error : unsigned(3 downto 0);
    signal sint_cycle, sint_reads : natural := 0;
    signal sint_case : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_ddr_busy <= '1' when sint_cycle mod 5 = 0 else '0';
    s_fill_enable <= '0' when sint_cycle mod 7 = 0 else '1';
    s_byte_ready <= s_buffer_ready and s_fill_enable;
    reader : entity work.rabbitpunch_state_slot_reader
        generic map (
            GINT_PAYLOAD_BYTES => 80
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            iu2_slot => "10",
            o_byte_valid => s_byte_valid,
            i_byte_ready => s_byte_ready,
            ou8_byte_data => su8_byte,
            o_active => s_active,
            o_finished => s_finished,
            o_success => s_success,
            ou3_error => su3_error,
            o_ddr_read => s_ddr_read,
            ou29_ddr_word_address => su29_address,
            i_ddr_busy => s_ddr_busy,
            i_ddr_read_valid => s_ddr_reply,
            iu64_ddr_read_data => su64_ddr_data
        );
    image : entity work.rabbitpunch_state_image_buffer
        generic map (
            GINT_IMAGE_BYTES => 80
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_begin => s_start,
            i_cancel => s_cancel,
            i_fill_valid => s_byte_valid and s_fill_enable,
            o_fill_ready => s_buffer_ready,
            iu8_fill_data => su8_byte,
            i_seal => s_finished and s_success,
            o_sealed => s_sealed,
            o_error => s_buffer_error,
            ou18_filled_bytes => su18_count,
            i_read_valid => s_buffer_read,
            iu18_read_address => su18_read_address,
            o_read_response => s_buffer_response,
            o_read_error => s_buffer_read_error,
            ou8_read_data => su8_buffer_data
        );
    s_check_finish <= '1' when s_buffer_response = '1' and su18_response_address = 79 else '0';
    preflight : entity work.rabbitpunch_state_preflight
        generic map (
            GINT_BODY_BYTES => 16
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_check_start,
            iu32_payload_words => to_unsigned(20, 32),
            iu32_abi_signature => x"10203040",
            i_rom_identity_valid => '1',
            iu32_rom_identity => x"55667788",
            iu32_config_identity => x"90ABCDEF",
            iu192_section_bytes => x"000000000000000000000000000000000000000800000008",
            i_byte_valid => s_buffer_response,
            o_byte_ready => s_check_ready,
            iu8_byte_data => su8_buffer_data,
            i_finish => s_check_finish,
            i_abort => '0',
            o_active => s_check_active,
            o_finished => s_check_finished,
            o_valid => s_check_valid,
            ou4_error => su4_check_error
        );
    memory_model : process(s_clk)
        variable vint_delay : natural := 0;
        variable vint_word : natural;
        variable vu64_reply : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            sint_cycle <= sint_cycle + 1;
            su18_response_address <= su18_read_address;
            s_ddr_reply <= '0';
            if (s_start = '1') then
                assert (vint_delay = 0) severity failure;
                sint_reads <= 0;
            end if;
            if (vint_delay > 0) then
                vint_delay := vint_delay - 1;
                if (vint_delay = 0) then
                    su64_ddr_data <= vu64_reply;
                    s_ddr_reply <= '1';
                end if;
            end if;
            if (s_ddr_read = '1') then
                assert (vint_delay = 0 and s_ddr_busy = '0') severity failure;
                vint_word := to_integer(su29_address - to_unsigned(16#07C10000#, 29));
                if (vint_word = 0) then
                    vu64_reply := x"0000001400000007";
                    if (sint_case >= 7) then
                        -- ARM process_ss rewrites the outer change counter
                        -- after loading a saved file, retaining its length.
                        vu64_reply := x"00000014FFFFFFFF";
                    end if;
                    if (sint_case = 1 or sint_case = 8) then
                        vu64_reply := x"0000000000000007";
                        if (sint_case = 8) then
                            vu64_reply := x"00000000FFFFFFFF";
                        end if;
                    elsif (sint_case = 2) then
                        vu64_reply := x"0000001300000007";
                    elsif (sint_case = 3 and sint_reads > 0) then
                        vu64_reply := x"0000001400000008";
                    elsif (sint_case = 9 and sint_reads > 0) then
                        vu64_reply := x"0000001400000000";
                    end if;
                else
                    assert (vint_word <= 10) severity failure;
                    vu64_reply := CU640_IMAGE(64*vint_word - 1 downto 64*(vint_word - 1));
                    if ((sint_case = 5 or sint_case = 10) and vint_word = 10) then
                        vu64_reply := vu64_reply xor to_unsigned(1, 64);
                    end if;
                end if;
                sint_reads <= sint_reads + 1;
                vint_delay := 4;
            end if;
        end if;
    end process;
    stimulus : process
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        for vint_case in 0 to 10 loop
            sint_case <= vint_case;
            s_start <= '1';
            cycles;
            s_start <= '0';
            if (vint_case = 4) then
                while (sint_reads = 0) loop
                    cycles;
                end loop;
                s_cancel <= '1';
                cycles;
                s_cancel <= '0';
                assert (s_active = '1') report "Canceled read debt lost" severity failure;
            end if;
            for vint_timeout in 0 to 1000 loop
                exit when s_finished = '1';
                cycles;
                assert (vint_timeout < 1000) report "Reader stalled" severity failure;
            end loop;
            if (vint_case = 0 or vint_case = 5 or vint_case = 6 or vint_case = 7 or vint_case = 10) then
                assert (s_success = '1' and su3_error = 0 and sint_reads = 12 and su18_count = 80)
                    report "Complete slot rejected in case " & integer'image(vint_case) severity failure;
                cycles;
                assert (s_sealed = '1' and s_buffer_error = '0') severity failure;
                s_check_start <= '1';
                cycles;
                s_check_start <= '0';
                for vint_byte in 0 to 79 loop
                    s_buffer_read <= '1';
                    su18_read_address <= to_unsigned(vint_byte, 18);
                    cycles;
                end loop;
                s_buffer_read <= '0';
                cycles(2);
                if (vint_case = 5 or vint_case = 10) then
                    assert (s_check_valid = '0' and su4_check_error = 7)
                        report "Corrupt staged body passed preflight" severity failure;
                else
                    assert (s_check_valid = '1' and su4_check_error = 0)
                        report "Staged image rejected" severity failure;
                end if;
            elsif (vint_case = 8) then
                assert (s_success = '0' and su3_error = 1 and s_sealed = '0') severity failure;
            elsif (vint_case = 9) then
                assert (s_success = '0' and su3_error = 3 and s_sealed = '0') severity failure;
            else
                assert (s_success = '0' and su3_error = vint_case and s_sealed = '0') severity failure;
            end if;
            cycles(3);
        end loop;
        report "STATE_SLOT_READER_PASS DDR-to-private-buffer-to-preflight,stalls,empty,length,changed counter,canceled debt,corrupt body,valid retry,ARM loaded sentinel,ARM empty,ARM changed counter,ARM corrupt body" severity note;
        stop;
        wait;
    end process;
end architecture;
