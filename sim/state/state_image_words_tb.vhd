-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;

entity state_image_words_tb is
end entity;

architecture test of state_image_words_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel, s_new_case : std_logic := '0';
    signal s_valid, s_ready : std_logic := '1';
    signal s_read, s_response, s_read_error, s_word_valid, s_active, s_finished, s_success : std_logic := '0';
    signal su18_address : unsigned(17 downto 0);
    signal su8_data : unsigned(7 downto 0);
    signal su64_data : unsigned(63 downto 0);
    signal su3_error : unsigned(2 downto 0);
    signal sint_case, sint_reads, sint_words : natural := 0;
    function F_BYTE(vint_address : natural) return unsigned is
    begin
        return to_unsigned((vint_address*19 + vint_address/128 + 57) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_state_image_words
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            i_image_valid => s_valid,
            o_image_read => s_read,
            ou18_image_address => su18_address,
            i_image_response => s_response,
            i_image_error => s_read_error,
            iu8_image_data => su8_data,
            o_word_valid => s_word_valid,
            i_word_ready => s_ready,
            ou64_word_data => su64_data,
            o_active => s_active,
            o_finished => s_finished,
            o_success => s_success,
            ou3_error => su3_error
        );
    endpoint : process(s_clk)
        variable vint_debt, vint_address, vint_phase : natural := 0;
        variable s_stalled : std_logic := '0';
        variable vu64_stalled : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_response <= '0';
            s_read_error <= '0';
            vint_phase := (vint_phase + 1) mod 97;
            s_ready <= '0';
            if (vint_phase = 0 and sint_case /= 2) then
                s_ready <= '1';
            end if;
            if (s_new_case = '1') then
                assert (vint_debt = 0) severity failure;
                sint_reads <= 0;
                sint_words <= 0;
            end if;
            if (s_read = '1') then
                assert (vint_debt = 0 and su18_address = sint_reads) severity failure;
                vint_address := to_integer(su18_address);
                vint_debt := 6;
                sint_reads <= sint_reads + 1;
            elsif (vint_debt > 0) then
                vint_debt := vint_debt - 1;
                if (vint_debt = 0) then
                    su8_data <= F_BYTE(vint_address);
                    s_response <= '1';
                    if (sint_case = 3 and vint_address = 40) then
                        s_read_error <= '1';
                    end if;
                end if;
            end if;
            if (s_stalled = '1' and s_word_valid = '1') then
                assert (su64_data = vu64_stalled) report "Backpressured word changed" severity failure;
            end if;
            s_stalled := '0';
            if (s_word_valid = '1') then
                for vint_lane in 0 to 7 loop
                    assert (su64_data(8*vint_lane + 7 downto 8*vint_lane) = F_BYTE(sint_words*8 + vint_lane))
                        report "Image word packing/order mismatch" severity failure;
                end loop;
                if (s_ready = '1') then
                    sint_words <= sint_words + 1;
                else
                    s_stalled := '1';
                    vu64_stalled := su64_data;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_expected_error : natural;
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
        for vint_case in 0 to 6 loop
            sint_case <= vint_case;
            s_valid <= '1';
            s_new_case <= '1';
            cycles;
            s_new_case <= '0';
            if (vint_case = 6) then
                s_valid <= '0';
            end if;
            s_start <= '1';
            cycles;
            s_start <= '0';
            vint_expected_error := 0;
            if (vint_case = 1 or vint_case = 4) then
                while (sint_reads = 0) loop
                    cycles;
                end loop;
                if (vint_case = 1) then
                    s_cancel <= '1';
                    vint_expected_error := 2;
                else
                    s_initialize <= '1';
                end if;
                cycles;
                s_cancel <= '0';
                s_initialize <= '0';
                assert (s_active = '1') report "Image word stream discarded read debt" severity failure;
            elsif (vint_case = 2) then
                while (s_word_valid /= '1') loop
                    cycles;
                end loop;
                cycles(12);
                assert (sint_words = 0 and sint_reads = 8) severity failure;
                s_valid <= '0';
                vint_expected_error := 1;
            elsif (vint_case = 3) then
                vint_expected_error := 3;
            elsif (vint_case = 6) then
                vint_expected_error := 1;
            end if;
            for vint_timeout in 0 to 1999999 loop
                exit when s_finished = '1' or (vint_case = 4 and s_active = '0');
                cycles;
                assert (vint_timeout < 1999999) report "Image word stream timeout" severity failure;
            end loop;
            assert (su3_error = vint_expected_error) severity failure;
            if (vint_case = 0 or vint_case = 5) then
                assert (s_success = '1' and sint_words = CINT_IMAGE_BYTES/8 and sint_reads = CINT_IMAGE_BYTES)
                    report "Incomplete image word stream" severity failure;
            else
                assert (s_success = '0') severity failure;
            end if;
            cycles(12);
        end loop;
        report "STATE_IMAGE_WORDS_PASS full image,byte lanes,backpressure,read debt,cancel/reset,permission,error,retry" severity note;
        stop;
        wait;
    end process;
end architecture;
