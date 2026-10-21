-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_slot_writer_tb is
end entity;

architecture test of state_slot_writer_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel, s_valid : std_logic := '0';
    signal s_ready, s_active, s_finished, s_success, s_error, s_read, s_write : std_logic;
    signal s_busy : std_logic := '1';
    signal s_reply : std_logic := '0';
    signal su2_slot : unsigned(1 downto 0) := (others => '0');
    signal su64_data, su64_reply, su64_write : unsigned(63 downto 0) := (others => '0');
    signal su29_address, su29_expected_base : unsigned(28 downto 0);
    signal su32_expected_counter : unsigned(31 downto 0) := (others => '0');
    signal su32_previous_counter : unsigned(31 downto 0) := (others => '0');
    signal su64_last_control : unsigned(63 downto 0) := (others => '0');
    signal s_score_reset : std_logic := '0';
    signal sint_writes : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    writer : entity work.rabbitpunch_state_slot_writer
        generic map (
            GINT_PAYLOAD_BYTES => 80
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            iu2_slot => su2_slot,
            i_payload_valid => s_valid,
            o_payload_ready => s_ready,
            iu64_payload_data => su64_data,
            o_active => s_active,
            o_finished => s_finished,
            o_success => s_success,
            o_error => s_error,
            o_ddr_read => s_read,
            o_ddr_write => s_write,
            ou29_ddr_word_address => su29_address,
            ou64_ddr_write_data => su64_write,
            i_ddr_busy => s_busy,
            i_ddr_read_valid => s_reply,
            iu64_ddr_read_data => su64_reply
        );
    scoreboard : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            assert (not (s_read = '1' and s_write = '1')) severity failure;
            assert (s_busy = '0' or (s_read = '0' and s_write = '0')) severity failure;
            if (s_score_reset = '1') then
                sint_writes <= 0;
            elsif (s_write = '1') then
                if (su29_address = su29_expected_base) then
                    su64_last_control <= su64_write;
                end if;
                if (sint_writes = 0) then
                    assert (su29_address = su29_expected_base and
                        su64_write = (to_unsigned(0, 32) & su32_previous_counter))
                        report "Slot not invalidated before payload overwrite" severity failure;
                elsif (sint_writes < 11) then
                    assert (su29_address = su29_expected_base + sint_writes and
                        su64_write = to_unsigned(16#101F# + sint_writes, 64))
                        report "Payload reordered or wrong slot" severity failure;
                else
                    assert (sint_writes = 11 and su29_address = su29_expected_base and
                        su64_write = to_unsigned(20, 32) & su32_expected_counter)
                        report "Host commit precedes payload or has wrong length/counter" severity failure;
                end if;
                sint_writes <= sint_writes + 1;
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
        procedure begin_save(vint_slot : natural) is
        begin
            s_busy <= '1';
            s_score_reset <= '1';
            su2_slot <= to_unsigned(vint_slot, 2);
            su29_expected_base <= to_unsigned(16#07C00000# + vint_slot*32768, 29);
            s_start <= '1';
            cycles;
            s_start <= '0';
            s_score_reset <= '0';
            -- Live selection changes must not redirect an in-progress image.
            su2_slot <= to_unsigned((vint_slot + 1) mod 4, 2);
            cycles(3);
            assert (s_active = '1' and s_read = '0' and s_write = '0') severity failure;
            s_busy <= '0';
            wait for 1 ns;
            assert (s_read = '1' and su29_address = su29_expected_base) severity failure;
            cycles;
            assert (s_read = '0') severity failure;
        end procedure;
        procedure reply(vu32_counter : unsigned(31 downto 0)) is
        begin
            cycles(5);
            assert (s_ready = '0' and s_write = '0') severity failure;
            su32_previous_counter <= vu32_counter;
            su64_reply <= x"DEADBEEF" & vu32_counter;
            s_reply <= '1';
            cycles;
            s_reply <= '0';
            cycles;
            assert (s_ready = '1' and su64_last_control(63 downto 32) = 0) severity failure;
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        for vint_round in 0 to 4 loop
            begin_save(vint_round mod 4);
            if (vint_round = 0) then
                su32_expected_counter <= x"00000000";
                reply(x"FFFFFFFF");
            elsif (vint_round = 1) then
                su32_expected_counter <= x"00000000";
                reply(x"FFFFFFFE");
            else
                su32_expected_counter <= to_unsigned(vint_round + 1, 32);
                reply(to_unsigned(vint_round, 32));
            end if;
            for vint_word in 0 to 9 loop
                s_valid <= '0';
                cycles(2);
                su64_data <= to_unsigned(16#1020# + vint_word, 64);
                s_valid <= '1';
                s_busy <= '1';
                cycles(2);
                assert (s_ready = '0' and s_write = '0') severity failure;
                s_busy <= '0';
                cycles;
            end loop;
            s_valid <= '0';
            s_busy <= '1';
            cycles(3);
            assert (sint_writes = 11 and s_finished = '0') severity failure;
            s_busy <= '0';
            cycles;
            assert (s_finished = '1' and s_success = '1' and s_active = '0' and
                s_error = '0' and sint_writes = 12) severity failure;
            cycles(2);
            assert (s_finished = '0' and s_write = '0') severity failure;
        end loop;
        -- Cancel/reset must retain routing ownership until accepted read debt
        -- is retired; an attempted new start during drain cannot issue a read.
        for vint_reset in 0 to 1 loop
            begin_save(2);
            if (vint_reset = 0) then
                s_cancel <= '1';
            else
                s_initialize <= '1';
            end if;
            cycles;
            s_cancel <= '0';
            s_initialize <= '0';
            s_start <= '1';
            cycles(4);
            s_start <= '0';
            assert (s_active = '1' and s_read = '0' and s_write = '0') severity failure;
            s_reply <= '1';
            cycles;
            s_reply <= '0';
            assert (s_active = '0' and s_success = '0' and sint_writes = 0) severity failure;
        end loop;
        -- No partial payload may publish a new counter, regardless of where
        -- cancellation lands in its stream.
        for vint_partial in 0 to 9 loop
            begin_save(1);
            reply(x"01020304");
            for vint_word in 1 to vint_partial loop
                su64_data <= to_unsigned(16#1020# + vint_word - 1, 64);
                s_valid <= '1';
                cycles;
            end loop;
            s_cancel <= '1';
            cycles;
            s_cancel <= '0';
            s_valid <= '0';
            assert (s_finished = '1' and s_success = '0' and
                sint_writes = vint_partial + 1 and s_active = '0') severity failure;
        end loop;
        -- Cancel and the owed response may arrive on the same edge.
        begin_save(0);
        s_cancel <= '1';
        s_reply <= '1';
        cycles;
        s_cancel <= '0';
        s_reply <= '0';
        assert (s_active = '0' and s_finished = '1' and s_success = '0') severity failure;
        -- Cancellation on the final commit edge suppresses publication.
        begin_save(3);
        reply(x"12345678");
        for vint_word in 0 to 9 loop
            su64_data <= to_unsigned(16#1020# + vint_word, 64);
            s_valid <= '1';
            cycles;
        end loop;
        s_valid <= '0';
        s_cancel <= '1';
        cycles;
        s_cancel <= '0';
        assert (s_finished = '1' and s_success = '0' and s_error = '1' and
            sint_writes = 11 and su64_last_control(63 downto 32) = 0) severity failure;
        cycles(3);
        assert (s_write = '0' and s_read = '0') severity failure;
        report "STATE_SLOT_WRITER_PASS five saves,four slots,backpressure,counter wrap,read debt,ten partial cancellations,commit cancellation" severity note;
        stop;
        wait;
    end process;
end architecture;
