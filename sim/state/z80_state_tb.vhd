-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity z80_state_tb is
end entity;
architecture test of z80_state_tb is
    type t_bytes is array(natural range <>) of unsigned(7 downto 0);
    type t_words is array(natural range <>) of unsigned(15 downto 0);
    type t_trace is record
        su16_address : unsigned(15 downto 0);
        su8_data : unsigned(7 downto 0);
    end record;
    type t_traces is array(0 to 399) of t_trace;
    constant CU8_START_PROGRAM : t_bytes := (x"F3", x"31", x"00", x"FF", x"ED", x"56", x"3E", x"11", x"01", x"22", x"33", x"11", x"44", x"55", x"21", x"66", x"77", x"DD", x"21", x"88", x"99", x"FD", x"21", x"AA", x"BB", x"3E", x"3C", x"ED", x"47", x"3E", x"11", x"08", x"D9", x"3E", x"CC", x"01", x"DD", x"EE", x"11", x"34", x"12", x"21", x"78", x"56", x"D9", x"08", x"FB", x"C3", x"00", x"01");
    constant CU8_LOOP_PROGRAM : t_bytes := (x"3C", x"03", x"13", x"23", x"DD", x"23", x"FD", x"23", x"32", x"00", x"80", x"ED", x"43", x"02", x"80", x"ED", x"53", x"04", x"80", x"22", x"06", x"80", x"DD", x"22", x"08", x"80", x"FD", x"22", x"0A", x"80", x"08", x"D9", x"3D", x"0B", x"32", x"10", x"80", x"ED", x"43", x"12", x"80", x"D9", x"08", x"C3", x"00", x"01");
    constant CU8_INTERRUPT_PROGRAM : t_bytes := (x"F5", x"3A", x"00", x"90", x"3C", x"32", x"00", x"90", x"F1", x"FB", x"ED", x"4D");
    signal s_clk : std_logic := '0';
    signal s_reset_n : std_logic := '0';
    signal su2_divider : unsigned(1 downto 0) := (others => '0');
    signal s_enable, s_fetch_n, s_memory_n, s_io_n, s_read_n, s_write_n : std_logic;
    signal s_irq, s_nmi, s_overlay, s_parked : std_logic := '0';
    signal s_capture, s_resume, s_state_write, s_state_word : std_logic := '0';
    signal su16_address, su16_state_in, su16_state_out : unsigned(15 downto 0);
    signal su8_data, su8_memory_data, su8_overlay_data, su8_write_data : unsigned(7 downto 0);
    signal s_snapshot, s_restore, s_record, s_compare : std_logic := '0';
    signal sint_writes, sint_recorded, sint_compared : natural := 0;
    signal sint_irq_writes : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    su2_divider <= su2_divider + 1 when rising_edge(s_clk);
    s_enable <= '1' when (su2_divider = 0) else '0';
    su8_data <= su8_overlay_data when (s_overlay = '1') else su8_memory_data;
    cpu : entity work.rabbitpunch_t80
        port map (
            i_clk => s_clk,
            i_reset_n => s_reset_n,
            i_clock_enable => s_enable,
            i_wait_n => '1',
            i_interrupt_n => not s_irq,
            i_nonmaskable_interrupt_n => not s_nmi,
            i_bus_request_n => '1',
            o_opcode_fetch_n => s_fetch_n,
            o_memory_request_n => s_memory_n,
            o_io_request_n => s_io_n,
            o_read_n => s_read_n,
            o_write_n => s_write_n,
            o_refresh_n => open,
            o_halted_n => open,
            o_bus_acknowledge_n => open,
            ou16_address => su16_address,
            iu8_read_data => su8_data,
            ou8_write_data => su8_write_data
        );
    state_access : entity work.rabbitpunch_z80_state
        port map (
            i_clk => s_clk,
            i_clock_enable => s_enable,
            i_reset_n => s_reset_n,
            i_capture_request => s_capture,
            o_cpu_parked => s_parked,
            i_resume => s_resume,
            iu16_cpu_address => su16_address,
            i_opcode_fetch_n => s_fetch_n,
            i_memory_request_n => s_memory_n,
            i_io_request_n => s_io_n,
            i_read_n => s_read_n,
            i_write_n => s_write_n,
            i_wait_n => '1',
            iu8_cpu_write_data => su8_write_data,
            iu8_bus_read_data => su8_data,
            o_nonmaskable_request => s_nmi,
            o_overlay_read => s_overlay,
            ou8_overlay_read_data => su8_overlay_data,
            i_state_word => s_state_word,
            i_state_write => s_state_write,
            iu16_state_write_data => su16_state_in,
            ou16_state_read_data => su16_state_out
        );
    memory_and_scoreboard : process(s_clk)
        variable v_ram, v_saved_ram : t_bytes(0 to 65535) := (others => (others => '0'));
        variable v_trace : t_traces;
        variable v_initialized, v_writing, v_irq, v_saved_irq : boolean := false;
        variable vu16_last_address : unsigned(15 downto 0);
        variable vu8_last_data : unsigned(7 downto 0);
        variable vint_irq_count, vint_saved_irq_count : natural range 0 to 15 := 0;
    begin
        if (rising_edge(s_clk)) then
            if (not v_initialized) then
                for vint_byte in CU8_START_PROGRAM'range loop
                    v_ram(vint_byte) := CU8_START_PROGRAM(vint_byte);
                end loop;
                for vint_byte in CU8_LOOP_PROGRAM'range loop
                    v_ram(16#100# + vint_byte) := CU8_LOOP_PROGRAM(vint_byte);
                end loop;
                for vint_byte in CU8_INTERRUPT_PROGRAM'range loop
                    v_ram(16#38# + vint_byte) := CU8_INTERRUPT_PROGRAM(vint_byte);
                end loop;
                v_ram(16#66#) := x"ED";
                v_ram(16#67#) := x"45";
                v_initialized := true;
            end if;
            if (s_fetch_n = '0' and s_io_n = '0') then
                v_irq := false;
            end if;
            if (s_memory_n = '0' and s_write_n = '0') then
                v_writing := true;
                vu16_last_address := su16_address;
                vu8_last_data := su8_write_data;
            elsif (v_writing) then
                v_writing := false;
                if (not (s_capture = '1' and vu16_last_address >= 16#D0# and vu16_last_address <= 16#D7#)) then
                    v_ram(to_integer(vu16_last_address)) := vu8_last_data;
                    if (vu16_last_address >= 16#8000# and vu16_last_address <= 16#9000#) then
                        sint_writes <= sint_writes + 1;
                        if (vu16_last_address = 16#9000#) then
                            sint_irq_writes <= sint_irq_writes + 1;
                        end if;
                        if (vu16_last_address = 16#8012#) then
                            if (vint_irq_count = 15) then
                                vint_irq_count := 0;
                                v_irq := true;
                            else
                                vint_irq_count := vint_irq_count + 1;
                            end if;
                        end if;
                        if (s_record = '1' and sint_recorded < 400) then
                            v_trace(sint_recorded) := (vu16_last_address, vu8_last_data);
                            sint_recorded <= sint_recorded + 1;
                        end if;
                        if (s_compare = '1' and sint_compared < 1200) then
                            assert (v_trace(sint_compared mod 400) = t_trace'(vu16_last_address, vu8_last_data))
                                report "Z80 continuation differs at write " & integer'image(sint_compared) severity failure;
                            sint_compared <= sint_compared + 1;
                        end if;
                    end if;
                end if;
            end if;
            if (s_snapshot = '1') then
                assert (s_parked = '1') report "Z80 RAM snapshot before park" severity failure;
                v_saved_ram := v_ram;
                vint_saved_irq_count := vint_irq_count;
                v_saved_irq := v_irq;
            end if;
            if (s_restore = '1') then
                assert (s_parked = '1') report "Z80 RAM restore before park" severity failure;
                v_ram := v_saved_ram;
                vint_irq_count := vint_saved_irq_count;
                v_irq := v_saved_irq;
            end if;
            su8_memory_data <= v_ram(to_integer(su16_address));
            if (v_irq) then
                s_irq <= '1';
            else
                s_irq <= '0';
            end if;
        end if;
    end process;
    stimulus : process
        variable v_registers : t_words(0 to 1);
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
            for vint_cycle in 1 to 100000 loop
                cycles(1);
                exit when (s_parked = '1');
            end loop;
            assert (s_parked = '1') report "Z80 never reached park monitor" severity failure;
            cycles(5);
        end procedure;
        procedure resume is
        begin
            s_resume <= '1';
            for vint_cycle in 1 to 100000 loop
                cycles(1);
                exit when (s_parked = '0');
            end loop;
            assert (s_parked = '0') report "Z80 never left park monitor" severity failure;
            s_capture <= '0';
            s_resume <= '0';
        end procedure;
    begin
        cycles(80);
        s_reset_n <= '1';
        wait until sint_writes >= 300;
        park;
        s_state_word <= '0';
        cycles(2);
        v_registers(0) := su16_state_out;
        s_state_word <= '1';
        cycles(2);
        v_registers(1) := su16_state_out;
        assert (v_registers(1) = 1) report "Z80 interrupt mode capture incorrect" severity failure;
        s_snapshot <= '1';
        cycles(1);
        s_snapshot <= '0';
        s_record <= '1';
        resume;
        wait until sint_recorded = 400;
        s_record <= '0';
        for vint_round in 1 to 3 loop
            vint_prior_writes := sint_writes;
            wait until sint_writes >= vint_prior_writes + 1000;
            park;
            s_restore <= '1';
            cycles(1);
            s_restore <= '0';
            s_state_word <= '0';
            su16_state_in <= v_registers(0);
            s_state_write <= '1';
            cycles(1);
            s_state_word <= '1';
            su16_state_in <= v_registers(1);
            cycles(1);
            s_state_write <= '0';
            s_compare <= '1';
            resume;
            wait until sint_compared = 400 * vint_round;
            s_compare <= '0';
        end loop;
        assert (sint_irq_writes >= 3) report "Z80 continuation did not exercise its IRQ handler" severity failure;
        report "Z80_STATE_PASS ordered_continuation_writes=1200 repeated_restores=3 mode1_irq=checked ram_and_register_restore=checked";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 20 ms;
        assert (false) report "Z80 state round-trip timed out" severity failure;
        wait;
    end process;
end architecture;
