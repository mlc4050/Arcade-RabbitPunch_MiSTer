-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_snapshot_tb is
end entity;

architecture test of state_snapshot_tb is
    constant CU512_HEADER : unsigned(511 downto 0) :=
        x"00000000C413E7B30000000800000008000000080000000800000008000000080000007090ABCDEF052021710000003055667788102030400040000131535052";
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel, s_machine_held : std_logic := '0';
    signal s_rom_valid : std_logic := '1';
    signal su32_rom : unsigned(31 downto 0) := x"55667788";
    signal su192_sections : unsigned(191 downto 0) := x"000000080000000800000008000000080000000800000008";
    signal s_hold, s_body_request, s_body_ready, s_body_response, s_body_error : std_logic := '0';
    signal su18_body_address : unsigned(17 downto 0);
    signal su8_body_data, su8_image_data, su8_read_data : unsigned(7 downto 0);
    signal s_image_begin, s_image_cancel, s_image_valid, s_image_ready, s_image_seal : std_logic;
    signal s_active, s_finished, s_success, s_buffer_ready, s_sealed, s_buffer_error : std_logic;
    signal s_read, s_response, s_read_error, s_fill_enable : std_logic := '0';
    signal su18_read_address, su18_count : unsigned(17 downto 0) := (others => '0');
    signal su4_error : unsigned(3 downto 0);
    signal sint_cycle, sint_reads, sint_case : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_body_ready <= '0' when sint_cycle mod 4 = 0 else '1';
    s_fill_enable <= '0' when sint_cycle mod 5 = 0 else '1';
    s_image_ready <= s_buffer_ready and s_fill_enable;
    snapshot : entity work.rabbitpunch_state_snapshot
        generic map (
            GINT_BODY_BYTES => 48
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            i_rom_identity_valid => s_rom_valid,
            iu32_abi_signature => x"10203040",
            iu32_rom_identity => su32_rom,
            iu32_config_identity => x"90ABCDEF",
            iu192_section_bytes => su192_sections,
            o_machine_hold_request => s_hold,
            i_machine_held => s_machine_held,
            o_body_request => s_body_request,
            i_body_ready => s_body_ready,
            ou18_body_address => su18_body_address,
            i_body_response => s_body_response,
            i_body_error => s_body_error,
            iu8_body_data => su8_body_data,
            o_image_begin => s_image_begin,
            o_image_cancel => s_image_cancel,
            o_image_valid => s_image_valid,
            i_image_ready => s_image_ready,
            ou8_image_data => su8_image_data,
            o_image_seal => s_image_seal,
            o_active => s_active,
            o_finished => s_finished,
            o_success => s_success,
            ou4_error => su4_error
        );
    staging : entity work.rabbitpunch_state_image_buffer
        generic map (
            GINT_IMAGE_BYTES => 112
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_begin => s_image_begin,
            i_cancel => s_image_cancel,
            i_fill_valid => s_image_valid and s_fill_enable,
            o_fill_ready => s_buffer_ready,
            iu8_fill_data => su8_image_data,
            i_seal => s_image_seal,
            o_sealed => s_sealed,
            o_error => s_buffer_error,
            ou18_filled_bytes => su18_count,
            i_read_valid => s_read,
            iu18_read_address => su18_read_address,
            o_read_response => s_response,
            o_read_error => s_read_error,
            ou8_read_data => su8_read_data
        );
    body_model : process(s_clk)
        variable vint_delay : natural := 0;
        variable vu8_data : unsigned(7 downto 0);
        variable v_error : std_logic;
    begin
        if (rising_edge(s_clk)) then
            sint_cycle <= sint_cycle + 1;
            s_body_response <= '0';
            s_body_error <= '0';
            if (s_start = '1') then
                assert (vint_delay = 0) severity failure;
                sint_reads <= 0;
            end if;
            if (vint_delay > 0) then
                vint_delay := vint_delay - 1;
                if (vint_delay = 0) then
                    su8_body_data <= vu8_data;
                    s_body_error <= v_error;
                    s_body_response <= '1';
                end if;
            end if;
            if (s_body_request = '1') then
                assert (vint_delay = 0 and s_body_ready = '1' and s_machine_held = '1') severity failure;
                assert (su18_body_address = sint_reads mod 48) report "Body capture reordered bytes" severity failure;
                vu8_data := resize(su18_body_address, 8);
                if (sint_case = 1 and sint_reads = 48) then
                    vu8_data := vu8_data xor x"01";
                end if;
                v_error := '0';
                if (sint_case = 2 and su18_body_address = 5) then
                    v_error := '1';
                end if;
                vint_delay := 4;
                sint_reads <= sint_reads + 1;
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
        for vint_case in 0 to 12 loop
            sint_case <= vint_case;
            su192_sections <= x"000000080000000800000008000000080000000800000008";
            if (vint_case = 8) then
                su192_sections(31 downto 0) <= to_unsigned(7, 32);
                su192_sections(63 downto 32) <= to_unsigned(9, 32);
            end if;
            s_machine_held <= '0';
            su32_rom <= x"55667788";
            if (vint_case = 5) then
                s_rom_valid <= '0';
            else
                s_rom_valid <= '1';
            end if;
            s_start <= '1';
            cycles;
            s_start <= '0';
            if (vint_case /= 5) then
                cycles(7);
                assert (s_body_request = '0' and s_hold = '1') severity failure;
                if (vint_case = 11) then
                    s_cancel <= '1';
                    cycles;
                    s_cancel <= '0';
                else
                    s_machine_held <= '1';
                end if;
                if (vint_case = 3 or vint_case = 4 or vint_case = 7 or vint_case = 9) then
                    while (sint_reads = 0) loop
                        cycles;
                    end loop;
                    if (vint_case = 3) then
                        s_cancel <= '1';
                    elsif (vint_case = 4) then
                        su32_rom <= x"12345678";
                    elsif (vint_case = 7) then
                        s_machine_held <= '0';
                    else
                        s_initialize <= '1';
                    end if;
                    cycles;
                    s_cancel <= '0';
                    s_initialize <= '0';
                    assert (s_active = '1' and s_hold = '1') report "Canceled body debt lost hold" severity failure;
                end if;
                for vint_timeout in 0 to 4999 loop
                    exit when s_finished = '1' or (vint_case = 9 and s_active = '0');
                    cycles;
                    assert (vint_timeout < 4999) report "Snapshot stalled case=" & integer'image(vint_case) severity failure;
                end loop;
            end if;
            if (vint_case = 0 or vint_case = 6 or vint_case = 10 or vint_case = 12) then
                assert (s_success = '1' and su4_error = 0 and s_sealed = '1' and sint_reads = 96) severity failure;
                for vint_byte in 0 to 111 loop
                    s_read <= '1';
                    su18_read_address <= to_unsigned(vint_byte, 18);
                    cycles;
                    assert (s_response = '1' and s_read_error = '0') severity failure;
                    if (vint_byte < 64) then
                        assert (su8_read_data = CU512_HEADER(8*vint_byte + 7 downto 8*vint_byte))
                            report "Snapshot header differs from independent zlib fixture" severity failure;
                    else
                        assert (su8_read_data = vint_byte - 64) report "Snapshot body differs" severity failure;
                    end if;
                end loop;
                s_read <= '0';
            else
                assert (s_success = '0') severity failure;
                case vint_case is
                    when 1 => assert (su4_error = 3) severity failure;
                    when 2 => assert (su4_error = 2) severity failure;
                    when 3 => assert (su4_error = 4) severity failure;
                    when 4 => assert (su4_error = 5) severity failure;
                    when 5 => assert (su4_error = 1 and sint_reads = 0) severity failure;
                    when 7 => assert (su4_error = 6) severity failure;
                    when 8 => assert (su4_error = 7) severity failure;
                    when 11 => assert (su4_error = 4 and sint_reads = 0) severity failure;
                    when 9 => assert (su4_error = 0 and s_finished = '0') severity failure;
                    when others => null;
                end case;
                cycles(2);
                assert (s_sealed = '0') report "Failed snapshot sealed an image" severity failure;
            end if;
            cycles(3);
        end loop;
        report "STATE_SNAPSHOT_PASS two-pass CRC,immutable image,zlib header,stalls,unstable body,backend error,canceled debt,ROM identity,hold loss,bad sections,reset debt,cancel before held,valid retry" severity note;
        stop;
        wait;
    end process;
end architecture;
