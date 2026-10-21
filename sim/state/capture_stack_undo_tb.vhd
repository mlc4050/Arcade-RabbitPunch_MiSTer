-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity capture_stack_undo_tb is
end entity;

architecture test of capture_stack_undo_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_request, s_write, s_capture, s_response, s_ready : std_logic := '0';
    signal s_acknowledge, s_discard, s_valid, s_done, s_error, s_idle : std_logic := '0';
    signal s_backend_request, s_backend_write, s_backend_response : std_logic := '0';
    signal su24_address, su24_journal_address, su24_backend_address : unsigned(23 downto 0) := (others => '0');
    signal su16_data, su16_read, su16_backend_data, su16_backend_read : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes, su2_backend_bytes : unsigned(1 downto 0) := "11";
    signal su16_word0, su16_word1 : unsigned(15 downto 0) := x"A55A";
    signal sint_backend_transactions : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    adapter : entity work.rabbitpunch_capture_stack_undo
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_request => s_request,
            o_ready => s_ready,
            i_write => s_write,
            i_capture_ram_write => s_capture,
            iu24_address => su24_address,
            iu16_write_data => su16_data,
            iu2_bytes => su2_bytes,
            o_response => s_response,
            ou16_read_data => su16_read,
            i_level7_acknowledge => s_acknowledge,
            i_discard_journal => s_discard,
            o_journal_valid => s_valid,
            ou24_journal_address => su24_journal_address,
            o_undo_completed => s_done,
            o_undo_error => s_error,
            o_idle => s_idle,
            o_backend_request => s_backend_request,
            o_backend_write => s_backend_write,
            ou24_backend_address => su24_backend_address,
            ou16_backend_data => su16_backend_data,
            ou2_backend_bytes => su2_backend_bytes,
            i_backend_response => s_backend_response,
            iu16_backend_data => su16_backend_read
        );
    backend : process(s_clk)
        variable vint_wait : natural := 0;
        variable vu16_word : unsigned(15 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_backend_response <= '0';
            if (s_backend_request = '1') then
                assert (vint_wait = 0) report "Overlapping backend debt" severity failure;
                vint_wait := 4;
                sint_backend_transactions <= sint_backend_transactions + 1;
                if (su24_backend_address = 0) then
                    vu16_word := su16_word0;
                else
                    vu16_word := su16_word1;
                end if;
                su16_backend_read <= vu16_word;
                if (s_backend_write = '1') then
                    if (su2_backend_bytes(1) = '1') then
                        vu16_word(15 downto 8) := su16_backend_data(15 downto 8);
                    end if;
                    if (su2_backend_bytes(0) = '1') then
                        vu16_word(7 downto 0) := su16_backend_data(7 downto 0);
                    end if;
                    if (su24_backend_address = 0) then
                        su16_word0 <= vu16_word;
                    else
                        su16_word1 <= vu16_word;
                    end if;
                end if;
            elsif (vint_wait > 0) then
                vint_wait := vint_wait - 1;
                if (vint_wait = 0) then
                    s_backend_response <= '1';
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_prior : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure write_word(vint_address : natural; vu16_data : unsigned(15 downto 0);
            vu2_lanes : unsigned(1 downto 0) := "11") is
        begin
            assert (s_ready = '1') severity failure;
            su24_address <= to_unsigned(vint_address, 24);
            su16_data <= vu16_data;
            su2_bytes <= vu2_lanes;
            s_write <= '1';
            s_request <= '1';
            cycles;
            s_request <= '0';
            loop
                cycles;
                exit when (s_response = '1');
            end loop;
            cycles;
        end procedure;
        procedure undo is
        begin
            s_acknowledge <= '1';
            loop
                cycles;
                exit when (s_done = '1');
                assert (s_response = '0' and s_error = '0') severity failure;
            end loop;
            cycles(8);
            assert (s_valid = '0' and s_done = '0') severity failure;
            s_acknowledge <= '0';
            cycles;
        end procedure;
    begin
        s_initialize <= '1';
        cycles(2);
        s_initialize <= '0';
        cycles;
        s_capture <= '1';
        write_word(0, x"1234");
        write_word(2, x"5678");
        assert (s_valid = '1' and su24_journal_address = 2) severity failure;
        undo;
        assert (su16_word0 = x"1234" and su16_word1 = x"A55A")
            report "Undo changed an earlier game write" severity failure;
        for vint_round in 1 to 3 loop
            write_word(0, x"FFFF", "01");
            assert (su16_word0 = x"12FF") severity failure;
            undo;
            assert (su16_word0 = x"1234") report "Repeated byte-lane undo differs" severity failure;
        end loop;
        write_word(0, x"EEEE", "10");
        undo;
        assert (su16_word0 = x"1234") severity failure;
        s_capture <= '0';
        vint_prior := sint_backend_transactions;
        write_word(2, x"BEEF");
        assert (sint_backend_transactions = vint_prior + 1 and s_valid = '0')
            report "Unarmed write was speculatively read" severity failure;
        s_acknowledge <= '1';
        cycles;
        assert (s_error = '1' and s_backend_request = '0') severity failure;
        s_acknowledge <= '0';
        cycles;
        -- A normal read returns through the same acknowledged backend.
        s_write <= '0';
        s_request <= '1';
        cycles;
        s_request <= '0';
        loop
            cycles;
            exit when (s_response = '1');
        end loop;
        assert (su16_read = x"BEEF") severity failure;
        cycles;
        s_write <= '1';
        s_capture <= '1';
        s_request <= '1';
        cycles;
        s_request <= '0';
        cycles;
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        vint_prior := sint_backend_transactions;
        for vint_cycle in 1 to 10 loop
            cycles;
            assert (s_response = '0') report "Canceled old-word read returned to CPU" severity failure;
        end loop;
        assert (s_idle = '1' and s_valid = '0' and sint_backend_transactions = vint_prior)
            report "Canceled old-word read issued a write or lost debt" severity failure;
        assert (su16_word1 = x"BEEF") severity failure;
        -- Cancel after the write has been accepted. Its response must drain;
        -- an already accepted write is allowed to finish, never replayed.
        s_request <= '1';
        cycles;
        s_request <= '0';
        loop
            cycles;
            exit when (s_backend_request = '1' and s_backend_write = '1');
        end loop;
        cycles;
        vint_prior := sint_backend_transactions;
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        for vint_cycle in 1 to 10 loop
            cycles;
            assert (s_response = '0') severity failure;
        end loop;
        assert (s_idle = '1' and s_valid = '0' and sint_backend_transactions = vint_prior)
            report "Canceled game write was replayed or lost debt" severity failure;
        write_word(0, x"ABCD");
        s_discard <= '1';
        cycles;
        s_discard <= '0';
        cycles;
        assert (s_valid = '0' and su16_word0 = x"ABCD") severity failure;
        report "CAPTURE_STACK_UNDO_PASS repeated_undo=5 lanes=both cancellation=drained";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 100 us;
        assert (false) report "Capture stack undo timeout" severity failure;
        wait;
    end process;
end architecture;
