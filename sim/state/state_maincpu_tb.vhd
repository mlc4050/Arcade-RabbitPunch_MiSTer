-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_maincpu_tb is
    generic (
        GINT_START_SR : natural := 16#2000#
    );
end entity;

architecture test of state_maincpu_tb is
    type t_words is array(natural range <>) of unsigned(15 downto 0);
    type t_trace is record
        su24_address : unsigned(23 downto 0);
        su16_data : unsigned(15 downto 0);
    end record;
    type t_traces is array(0 to 399) of t_trace;
    constant CU16_PROGRAM : t_words := (
        x"203C", x"1111", x"1111", x"227C", x"000F", x"C000",
        x"46FC", to_unsigned(GINT_START_SR, 16), x"5280", x"22C0", x"60FA"
    );
    signal su52_cpu_bus : unsigned(51 downto 0);
    signal s_user_pause, s_paused, s_slow_backend, s_backend_pending : std_logic := '0';
    signal sint_backend_requests : natural := 0;
    signal s_release, s_capture_error : std_logic := '0';
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_phase1, s_phase2, s_e_clock, s_monitor_held : std_logic;
    type t_clock_trace is array(0 to 511) of unsigned(51 downto 0);
    signal s_read, s_address_n, s_upper_n, s_lower_n, s_stopped : std_logic;
    signal s_iack, s_ready, s_access, s_take, s_irq1 : std_logic := '0';
    signal s_request, s_resume, s_overlay, s_overlay_ready, s_held, s_done, s_irq7 : std_logic := '0';
    signal s_state_write, s_snapshot, s_restore, s_record, s_compare : std_logic := '0';
    signal su3_fc, su3_interrupt_n : unsigned(2 downto 0);
    signal su23_address : unsigned(23 downto 1);
    signal su24_address : unsigned(23 downto 0);
    signal su16_read, su16_write, su16_overlay : unsigned(15 downto 0) := (others => '0');
    signal su5_state_address : unsigned(4 downto 0) := (others => '0');
    signal su32_state_write, su32_state_read : unsigned(31 downto 0) := (others => '0');
    signal sint_writes, sint_recorded, sint_compared : natural := 0;
    signal s_ram_request, s_ram_ready, s_ram_response, s_ram_sent : std_logic := '0';
    signal s_backend_request, s_backend_write, s_backend_response : std_logic := '0';
    signal s_undo_done, s_undo_error, s_stack_clean : std_logic := '0';
    signal su24_backend_address, su24_journal_address : unsigned(23 downto 0);
    signal su16_backend_write, su16_backend_read, su16_ram_read : unsigned(15 downto 0);
    signal su2_backend_bytes : unsigned(1 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    s_address_n <= su52_cpu_bus(51);
    s_read <= su52_cpu_bus(48);
    su3_fc <= su52_cpu_bus(47 downto 45);
    su24_address <= su52_cpu_bus(39 downto 16);
    s_iack <= '1' when s_address_n = '0' and su3_fc = 7 else '0';
    s_stack_clean <= s_held and not s_capture_error;
    adapter : entity work.rabbitpunch_state_maincpu
        generic map (
            GINT_PHASE_DIVIDER => 1
        )
        port map (
            i_clk => s_clk,
            i_phase_enable => '0',
            i_reset => s_reset,
            i_pause => s_user_pause,
            i_interrupt_level1 => s_irq1,
            o_interrupt_acknowledge => open,
            o_request => s_backend_request,
            o_request_write => s_backend_write,
            ou24_request_address => su24_backend_address,
            ou16_request_data => su16_backend_write,
            ou2_request_bytes => su2_backend_bytes,
            i_response_valid => s_backend_response,
            iu16_response_data => su16_backend_read,
            o_paused => s_paused,
            i_capture_request => s_request,
            i_capture_cancel => '0',
            o_capture_pending => open,
            o_capture_held => s_held,
            o_capture_error => s_capture_error,
            i_state_resume => s_resume,
            o_return_held => s_done,
            i_return_release => s_release,
            o_resume_completed => open,
            o_resume_canceled => open,
            iu5_state_address => su5_state_address,
            i_state_write => s_state_write,
            iu32_state_data => su32_state_write,
            ou32_state_data => su32_state_read,
            ou24_journal_address => su24_journal_address,
            o_stopped => s_stopped,
            ou52_debug_bus => su52_cpu_bus
        );
    memory_and_scoreboard : process(s_clk)
        variable vu16_ram, vu16_saved : t_words(0 to 32767) := (others => (others => '0'));
        variable vu24_trace : t_traces;
        variable v_initialized : boolean := false;
        variable vint_index : natural;
        variable vint_reply_delay : natural := 0;
        variable vu16_pending_reply : unsigned(15 downto 0);
    begin
        if (rising_edge(s_clk)) then
            if (not v_initialized) then
                vu16_ram(0) := x"000F";
                vu16_ram(1) := x"F800";
                vu16_ram(16#7BFF#) := x"A55A";
                vu16_ram(3) := x"0400";
                vu16_ram(16#32#) := x"0000";
                vu16_ram(16#33#) := x"0620";
                vu16_ram(16#310#) := x"4E73";
                for vint_word in CU16_PROGRAM'range loop
                    vu16_ram(16#200# + vint_word) := CU16_PROGRAM(vint_word);
                end loop;
                vu16_ram(16#280#) := x"4E72";
                vu16_ram(16#281#) := x"2000";
                vu16_ram(16#282#) := x"5282";
                vu16_ram(16#283#) := x"24C2";
                vu16_ram(16#284#) := x"60F6";
                v_initialized := true;
            end if;
            s_backend_response <= '0';
            if (s_backend_pending = '1') then
                if (vint_reply_delay = 0) then
                    s_backend_response <= '1';
                    su16_backend_read <= vu16_pending_reply;
                    s_backend_pending <= '0';
                else
                    vint_reply_delay := vint_reply_delay - 1;
                end if;
            end if;
            if (s_backend_request = '1') then
                assert (s_backend_pending = '0') report "Main CPU overlapped accepted backend debt" severity failure;
                sint_backend_requests <= sint_backend_requests + 1;
                if (s_slow_backend = '1') then
                    s_backend_pending <= '1';
                    vint_reply_delay := 65;
                else
                    s_backend_response <= '1';
                end if;
                assert (su24_backend_address < 65536 or (su24_backend_address >= 16#FC000# and su24_backend_address <= 16#FFFFE#)) report "Capture access escaped monitor overlay" severity failure;
                vint_index := to_integer(su24_backend_address(15 downto 1));
                vu16_pending_reply := vu16_ram(vint_index);
                if (s_slow_backend = '0') then
                    su16_backend_read <= vu16_ram(vint_index);
                end if;
                if (s_backend_write = '1') then
                    if (su2_backend_bytes(1) = '1') then
                        vu16_ram(vint_index)(15 downto 8) := su16_backend_write(15 downto 8);
                    end if;
                    if (su2_backend_bytes(0) = '1') then
                        vu16_ram(vint_index)(7 downto 0) := su16_backend_write(7 downto 0);
                    end if;
                    if (su24_backend_address >= 16#FC000# and su24_backend_address < 16#FF700#) then
                        sint_writes <= sint_writes + 1;
                        if (s_record = '1' and sint_recorded < 400) then
                            vu24_trace(sint_recorded) := (su24_backend_address, su16_backend_write);
                            sint_recorded <= sint_recorded + 1;
                        end if;
                        if (s_compare = '1' and sint_compared < 1200) then
                            assert (vu24_trace(sint_compared mod 400) = t_trace'(su24_backend_address, su16_backend_write))
                                report "GX capture continuation differs" severity failure;
                            sint_compared <= sint_compared + 1;
                        end if;
                    end if;
                end if;
            end if;
            if (s_snapshot = '1') then
                assert (s_held = '1') report "RAM snapshot before held monitor" severity failure;
                vu16_saved := vu16_ram;
                assert (s_stack_clean = '1' and vu16_ram(16#7BFF#) = x"A55A")
                    report "Pre-IACK PC-low push changed original stack RAM" severity failure;
                for vint_word in 16#7B80# to 16#7BFE# loop
                    assert (vu16_ram(vint_word) = 0) report "Monitor spilled into game stack" severity failure;
                end loop;
            end if;
            if (s_held = '1' and s_stack_clean = '1') then
                assert (vu16_ram(16#7BFF#) = x"A55A")
                    report "Capture or STOP recapture changed original stack word" severity failure;
            end if;
            if (s_restore = '1') then
                assert (s_held = '1') report "RAM restore before held monitor" severity failure;
                vu16_ram := vu16_saved;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu52_clock_trace : t_clock_trace;
        impure function F_CLOCK_EVENT return unsigned is
        begin
            return su52_cpu_bus;
        end function;
        type t_bank is array(0 to 22) of unsigned(31 downto 0);
        variable vu32_bank : t_bank;
        variable vint_prior, vint_requests_before : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure park is
        begin
            s_user_pause <= '1';
            s_request <= '1';
            cycles;
            s_request <= '0';
            for vint_wait in 0 to 10000 loop
                cycles;
                exit when (s_held = '1');
            end loop;
            assert (s_held = '1') report "GX monitor never held CPU" severity failure;
            su5_state_address <= to_unsigned(18, 5);
            cycles;
            assert (s_stack_clean = '1' and resize(su24_journal_address, 32) = su32_state_read + 4)
                report "Undo journal did not match captured SSP-2" severity failure;
        end procedure;
        procedure resume is
            variable vint_writes_before : natural;
        begin
            vint_writes_before := sint_writes;
            s_resume <= '1';
            cycles;
            s_resume <= '0';
            for vint_wait in 0 to 10000 loop
                cycles;
                exit when (s_done = '1');
            end loop;
            assert (s_done = '1' and s_capture_error = '0') report "Private RTE failed canonical return hold" severity failure;
            s_release <= '1';
            cycles;
            s_release <= '0';
            for vint_wait in 0 to 10000 loop
                exit when s_paused = '1';
                cycles;
            end loop;
            cycles(20);
            assert (s_paused = '1' and sint_writes = vint_writes_before)
                report "Private return ignored retained user pause" severity failure;
            s_user_pause <= '0';
            wait for 1 ns;
        end procedure;
        procedure bank_write(vint_word : natural; vu32_data : unsigned(31 downto 0)) is
        begin
            su5_state_address <= to_unsigned(vint_word, 5);
            su32_state_write <= vu32_data;
            s_state_write <= '1';
            cycles;
            s_state_write <= '0';
        end procedure;
    begin
        cycles(80);
        s_reset <= '0';
        wait until sint_writes >= 100;
        park;
        for vint_word in vu32_bank'range loop
            su5_state_address <= to_unsigned(vint_word, 5);
            cycles;
            vu32_bank(vint_word) := su32_state_read;
        end loop;
        assert (vu32_bank(18) = x"000FF7FA" and vu32_bank(22) = 0) report "Wrong captured SSP/STOP state" severity failure;
        s_snapshot <= '1';
        cycles;
        s_snapshot <= '0';
        s_record <= '1';
        resume;
        for vint_clock in vu52_clock_trace'range loop
            vu52_clock_trace(vint_clock) := F_CLOCK_EVENT;
            cycles;
        end loop;
        wait until sint_recorded = 400;
        s_record <= '0';
        for vint_round in 1 to 3 loop
            vint_prior := sint_writes;
            wait until sint_writes >= vint_prior + 200;
            park;
            s_restore <= '1';
            cycles;
            s_restore <= '0';
            for vint_word in vu32_bank'range loop
                bank_write(vint_word, vu32_bank(vint_word));
            end loop;
            s_compare <= '1';
            resume;
            for vint_clock in vu52_clock_trace'range loop
                assert (F_CLOCK_EVENT = vu52_clock_trace(vint_clock))
                    report "68000 clock continuation differs at " & integer'image(vint_clock) severity failure;
                cycles;
            end loop;
            wait until sint_compared = 400 * vint_round;
            s_compare <= '0';
        end loop;
        park;
        bank_write(2, x"00000000");
        bank_write(10, x"000FE000");
        bank_write(20, x"00000500");
        bank_write(19, x"00002000");
        resume;
        cycles(300);
        assert (s_stopped = '1') report "STOP setup failed" severity failure;
        vint_prior := sint_writes;
        for vint_round in 1 to 3 loop
            park;
            su5_state_address <= to_unsigned(22, 5);
            cycles;
            assert (su32_state_read = 1) report "STOP flag missing" severity failure;
            su5_state_address <= to_unsigned(20, 5);
            cycles;
            assert (su32_state_read = x"00000504") report "STOP architectural PC differs" severity failure;
            resume;
            cycles(300);
            assert (s_stopped = '1' and sint_writes = vint_prior) report "Capture woke stopped game" severity failure;
        end loop;
        s_irq1 <= '1';
        wait until s_iack = '1';
        wait until falling_edge(s_clk);
        s_irq1 <= '0';
        cycles(600);
        assert (sint_writes = vint_prior + 2 and s_stopped = '1') report "Restored STOP failed normal IRQ wake" severity failure;
        -- A new reset-vector read must wait behind an old accepted reply.
        s_slow_backend <= '1';
        s_reset <= '1';
        cycles(20);
        s_reset <= '0';
        wait until s_backend_pending = '1';
        cycles;
        vint_requests_before := sint_backend_requests;
        s_reset <= '1';
        cycles(2);
        s_reset <= '0';
        wait until s_backend_pending = '0';
        assert (sint_backend_requests = vint_requests_before)
            report "Reset reused the backend before its old read retired" severity failure;
        s_slow_backend <= '0';
        vint_prior := sint_writes;
        wait until sint_writes >= vint_prior + 30;
        report "STATE_MAINCPU_PASS repeated_restores=3 ordered_writes=1200 stop_roundtrips=3 irq_wakeup=checked monitor_stack_spill=none exact_resume_clocks=1536 user_pause=checked reset_read_debt=65";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 10 ms;
        assert (false) report "GX 68000 capture test timed out" severity failure;
        wait;
    end process;
end architecture;
