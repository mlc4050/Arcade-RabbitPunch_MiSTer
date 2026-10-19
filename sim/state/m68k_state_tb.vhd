-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;

entity m68k_state_tb is
    generic (GINT_INITIAL_STATUS : natural := 8192);
end entity;

architecture test of m68k_state_tb is
    type t_words is array(natural range <>) of unsigned(15 downto 0);
    type t_trace is record
        su24_address : unsigned(23 downto 0);
        su16_data : unsigned(15 downto 0);
        su2_bytes : unsigned(1 downto 0);
    end record;
    type t_traces is array(0 to 399) of t_trace;
    constant CU16_PROGRAM : t_words := (
        x"46FC", to_unsigned(GINT_INITIAL_STATUS, 16), x"2C7C", x"1234", x"5678", x"4E66", x"4CF9", x"7FFF", x"0000", x"1800", x"7000", x"7201",
        x"243C", x"0BAD", x"F00D", x"2E3C", x"AAAA", x"5555",
        x"2A7C", x"DEAD", x"BEEF", x"227C", x"0000", x"2000",
        x"5280", x"E399", x"D482", x"48F9", x"7FFF", x"0000", x"3100", x"32C0", x"33C0", x"0000", x"3000",
        x"23C1", x"0000", x"3004", x"23C2", x"0000", x"3008",
        x"B2FC", x"2100", x"66D8", x"227C", x"0000", x"2000", x"60D0"
    );
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal su2_divider : unsigned(1 downto 0) := (others => '0');
    signal s_phase1, s_phase2, s_read, s_address_n, s_upper_n, s_lower_n : std_logic;
    signal s_interrupt_cycle, s_acknowledge_n : std_logic;
    signal su23_word_address : unsigned(23 downto 1);
    signal su24_address : unsigned(23 downto 0);
    signal su3_function_code, su3_park_interrupt, su3_interrupt_n : unsigned(2 downto 0);
    signal su16_read_data, su16_write_data, su16_memory_data, su16_overlay_data : unsigned(15 downto 0);
    signal s_capture, s_parked, s_resume, s_overlay, s_state_write : std_logic := '0';
    signal su2_state_word : unsigned(1 downto 0) := (others => '0');
    signal su16_state_in, su16_state_out : unsigned(15 downto 0) := (others => '0');
    signal s_snapshot, s_restore, s_record, s_compare : std_logic := '0';
    signal sint_game_writes, sint_recorded, sint_compared : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    su2_divider <= su2_divider + 1 when falling_edge(s_clk);
    s_phase1 <= '1' when (su2_divider = 0) else '0';
    s_phase2 <= '1' when (su2_divider = 2) else '0';
    su24_address <= su23_word_address & '0';
    su3_interrupt_n <= not su3_park_interrupt;
    s_interrupt_cycle <= '1' when (s_address_n = '0' and su3_function_code = 7) else '0';
    s_acknowledge_n <= s_address_n or s_interrupt_cycle;
    su16_read_data <= su16_overlay_data when (s_overlay = '1') else su16_memory_data;
    cpu : entity work.rabbitpunch_fx68k
        port map (
            i_clk => s_clk,
            i_external_reset => s_reset,
            i_powerup_reset => s_reset,
            i_enable_phase1 => s_phase1,
            i_enable_phase2 => s_phase2,
            i_run => '1',
            o_read => s_read,
            o_address_strobe_n => s_address_n,
            o_upper_byte_strobe_n => s_upper_n,
            o_lower_byte_strobe_n => s_lower_n,
            ou23_word_address => su23_word_address,
            ou16_write_data => su16_write_data,
            iu16_read_data => su16_read_data,
            i_transfer_acknowledge_n => s_acknowledge_n,
            i_peripheral_transfer_n => not s_interrupt_cycle,
            i_bus_error_n => '1',
            i_bus_request_n => '1',
            i_bus_grant_acknowledge_n => '1',
            iu3_interrupt_level_n => su3_interrupt_n,
            ou3_function_code => su3_function_code,
            o_peripheral_clock => open,
            o_peripheral_address_valid_n => open,
            o_bus_grant_n => open,
            o_external_reset_out_n => open,
            o_halted_out_n => open
        );
    state_access : entity work.rabbitpunch_m68k_state
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_phase2_enable => s_phase2,
            i_capture_request => s_capture,
            o_cpu_parked => s_parked,
            i_resume => s_resume,
            iu23_cpu_word_address => su23_word_address,
            i_address_strobe_n => s_address_n,
            i_read => s_read,
            iu3_function_code => su3_function_code,
            iu16_cpu_write_data => su16_write_data,
            ou3_interrupt_level => su3_park_interrupt,
            o_overlay_read => s_overlay,
            ou16_overlay_read_data => su16_overlay_data,
            iu2_state_word => su2_state_word,
            i_state_write => s_state_write,
            iu16_state_write_data => su16_state_in,
            ou16_state_read_data => su16_state_out
        );
    memory_and_scoreboard : process(s_clk)
        variable v_ram, v_saved_ram : t_words(0 to 32767) := (others => (others => '0'));
        variable v_trace : t_traces;
        variable v_initialized, v_writing : boolean := false;
        variable vu24_last_address : unsigned(23 downto 0);
        variable vu16_last_data, vu16_value : unsigned(15 downto 0);
        variable vu2_last_bytes : unsigned(1 downto 0);
        variable vint_index : natural;
        variable v_trace_line : line;
        variable v_old_address_active : boolean := false;
        file v_bus_log : text open write_mode is "bus.txt";
    begin
        if (rising_edge(s_clk)) then
            if (not v_initialized) then
                v_ram(0) := x"0000";
                v_ram(1) := x"8000";
                v_ram(2) := x"0000";
                v_ram(3) := x"1000";
                for vint_word in CU16_PROGRAM'range loop
                    v_ram(16#800# + vint_word) := CU16_PROGRAM(vint_word);
                end loop;
                for vint_word in 0 to 29 loop
                    v_ram(16#C00# + vint_word) := to_unsigned(16#1000# + vint_word * 37, 16);
                end loop;
                v_initialized := true;
            end if;
            if (s_address_n = '0' and s_read = '0' and su24_address < 16#10000#) then
                v_writing := true;
                vu24_last_address := su24_address;
                vu16_last_data := su16_write_data;
                vu2_last_bytes := (not s_upper_n) & (not s_lower_n);
            elsif (v_writing) then
                v_writing := false;
                vint_index := to_integer(vu24_last_address(15 downto 1));
                vu16_value := v_ram(vint_index);
                if (vu2_last_bytes(1) = '1') then
                    vu16_value(15 downto 8) := vu16_last_data(15 downto 8);
                end if;
                if (vu2_last_bytes(0) = '1') then
                    vu16_value(7 downto 0) := vu16_last_data(7 downto 0);
                end if;
                v_ram(vint_index) := vu16_value;
                if (vu24_last_address >= 16#2000# and vu24_last_address < 16#4000#) then
                    sint_game_writes <= sint_game_writes + 1;
                    if (s_record = '1' and sint_recorded < 400) then
                        v_trace(sint_recorded) := (vu24_last_address, vu16_last_data, vu2_last_bytes);
                        sint_recorded <= sint_recorded + 1;
                    end if;
                    if (s_compare = '1' and sint_compared < 400) then
                        assert (v_trace(sint_compared) = t_trace'(vu24_last_address, vu16_last_data, vu2_last_bytes))
                            report "68000 continuation differs at write " & integer'image(sint_compared) severity failure;
                        sint_compared <= sint_compared + 1;
                    end if;
                end if;
            end if;
            if (s_address_n = '0' and not v_old_address_active) then
                write(v_trace_line, to_hstring(su24_address) & " " & to_hstring(su3_function_code) & " " & std_logic'image(s_read) & " cap=" & std_logic'image(s_capture) & " ipl=" & to_hstring(su3_park_interrupt) & " " & to_hstring(su16_read_data) & " " & to_hstring(su16_write_data));
                writeline(v_bus_log, v_trace_line);
            end if;
            v_old_address_active := s_address_n = '0';
            if (s_snapshot = '1') then
                assert (s_parked = '1') report "RAM snapshot before CPU park" severity failure;
                v_saved_ram := v_ram;
            end if;
            if (s_restore = '1') then
                assert (s_parked = '1') report "RAM restore before CPU park" severity failure;
                v_ram := v_saved_ram;
            end if;
            su16_memory_data <= v_ram(to_integer(su24_address(15 downto 1)));
        end if;
    end process;
    stimulus : process
        variable v_registers : t_words(0 to 3);
        variable vint_prior_writes : natural;
        procedure cycles(vint_count : natural) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure park is
        begin
            s_capture <= '1';
            for vint_cycle in 1 to 200000 loop
                cycles(1);
                exit when (s_parked = '1');
            end loop;
            assert (s_parked = '1') report "68000 never reached park monitor" severity failure;
            cycles(5);
        end procedure;
        procedure resume is
        begin
            s_resume <= '1';
            for vint_cycle in 1 to 200000 loop
                cycles(1);
                exit when (s_parked = '0');
            end loop;
            assert (s_parked = '0') report "68000 never left park monitor" severity failure;
            s_capture <= '0';
            s_resume <= '0';
        end procedure;
    begin
        cycles(80);
        s_reset <= '0';
        wait until sint_game_writes >= 300;
        park;
        for vint_word in 0 to 3 loop
            su2_state_word <= to_unsigned(vint_word, 2);
            cycles(2);
            v_registers(vint_word) := su16_state_out;
        end loop;
        assert (v_registers(2) = x"1234" and v_registers(3) = x"5678")
            report "68000 USP capture incorrect" severity failure;
        s_snapshot <= '1';
        cycles(1);
        s_snapshot <= '0';
        s_record <= '1';
        resume;
        wait until sint_recorded = 400;
        s_record <= '0';
        vint_prior_writes := sint_game_writes;
        wait until sint_game_writes >= vint_prior_writes + 1000;
        park;
        s_restore <= '1';
        cycles(1);
        s_restore <= '0';
        for vint_word in 0 to 3 loop
            su2_state_word <= to_unsigned(vint_word, 2);
            su16_state_in <= v_registers(vint_word);
            s_state_write <= '1';
            cycles(1);
        end loop;
        s_state_write <= '0';
        s_compare <= '1';
        resume;
        wait until sint_compared = 400;
        report "M68K_STATE_PASS ordered_continuation_writes=400 usp=checked ram_and_register_restore=checked";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 20 ms;
        assert (false) report "68000 state round-trip timed out" severity failure;
        wait;
    end process;
end architecture;
