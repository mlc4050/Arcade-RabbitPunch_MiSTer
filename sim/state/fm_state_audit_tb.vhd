-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity fm_state_audit_tb is
end entity;

architecture test of fm_state_audit_tb is
    type t_trace is array(0 to 32767) of unsigned(73 downto 0);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_hold, s_load, s_write, s_data_register : std_logic := '0';
    signal su3_phase, su3_restore : unsigned(2 downto 0) := (others => '0');
    signal s_enable, s_half, s_irq_n, s_sample : std_logic;
    signal su8_data, su8_status : unsigned(7 downto 0) := (others => '0');
    signal su16_left, su16_right, su16_full_left, su16_full_right : unsigned(15 downto 0);
    signal su2820_state, su2820_restore : unsigned(2819 downto 0) := (others => '0');
    signal su74_observed : unsigned(73 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when s_hold = '0' and (su3_phase = 3 or su3_phase = 7) else '0';
    s_half <= '1' when s_hold = '0' and su3_phase = 7 else '0';
    su74_observed <= su8_status & s_irq_n & s_sample & su16_left & su16_right & su16_full_left & su16_full_right;
    cadence : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_load = '1') then
                su3_phase <= su3_restore;
            elsif (s_hold = '0') then
                su3_phase <= su3_phase + 1;
            end if;
        end if;
    end process;
    chip : entity work.rabbitpunch_fm_state
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_chip_enable => s_enable,
            i_half_chip_enable => s_half,
            i_write => s_write,
            i_data_register => s_data_register,
            iu8_write_data => su8_data,
            ou8_status => su8_status,
            o_interrupt_n => s_irq_n,
            o_sample => s_sample,
            ou16_left_pcm => su16_left,
            ou16_right_pcm => su16_right,
            ou16_full_left_pcm => su16_full_left,
            ou16_full_right_pcm => su16_full_right,
            iu2820_state => su2820_restore,
            ou2820_state => su2820_state,
            i_state_load => s_load
        );
    stimulus : process
        variable vu2820_saved : unsigned(2819 downto 0);
        variable vu3_saved_phase : unsigned(2 downto 0);
        variable vu74_trace : t_trace;
        variable vint_nonzero, vint_differences, vint_late_differences : natural := 0;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure write_register(vint_address, vint_data : natural) is
        begin
            s_data_register <= '0';
            su8_data <= to_unsigned(vint_address, 8);
            s_write <= '1';
            cycles(8);
            s_write <= '0';
            cycles(8);
            s_data_register <= '1';
            su8_data <= to_unsigned(vint_data, 8);
            s_write <= '1';
            cycles(8);
            s_write <= '0';
            for vint_wait in 0 to 2047 loop
                cycles;
                exit when (su8_status(7) = '0');
            end loop;
            assert (su8_status(7) = '0') report "State donor YM write stayed busy" severity failure;
            cycles(8);
        end procedure;
    begin
        -- Keep the chip enables running while reset fills all shift storage.
        cycles(4096);
        s_reset <= '0';
        cycles(4096);
        for vint_address in 0 to 255 loop
            write_register(vint_address, 0);
        end loop;
        -- The donor does not reset stopped timer counts. Initialize both via
        -- real load edges before asserting that every exported state bit is known.
        write_register(16#10#, 255);
        write_register(16#11#, 3);
        write_register(16#12#, 255);
        write_register(16#14#, 3);
        cycles(2048);
        write_register(16#14#, 16#30#);
        cycles(2048);
        write_register(16#20#, 16#F8#);
        write_register(16#28#, 16#4C#);
        for vint_operator in 0 to 3 loop
            write_register(16#40# + 8 * vint_operator, 1);
            write_register(16#60# + 8 * vint_operator, 24);
            write_register(16#80# + 8 * vint_operator, 31);
            write_register(16#E0# + 8 * vint_operator, 15);
        end loop;
        write_register(16#08#, 16#78#);
        cycles(65536);
        for vint_bit in su2820_state'range loop
            if (su2820_state(vint_bit) /= '0' and su2820_state(vint_bit) /= '1') then
                report "JT51_UNKNOWN_STATE_BIT " & integer'image(vint_bit);
            end if;
        end loop;
        assert (not is_x(su2820_state)) report "Donor exported unknown persistent state" severity failure;
        vu2820_saved := su2820_state;
        vu3_saved_phase := su3_phase;
        for vint_cycle in vu74_trace'range loop
            assert (not is_x(su74_observed)) report "Donor output not initialized" severity failure;
            vu74_trace(vint_cycle) := su74_observed;
            if (su16_full_left /= 0 or su16_full_right /= 0) then
                vint_nonzero := vint_nonzero + 1;
            end if;
            cycles;
        end loop;
        assert (vint_nonzero > 1000) report "State audit recorded a silent/ineffective tone" severity failure;
        cycles(12345);
        s_hold <= '1';
        cycles;
        su2820_restore <= vu2820_saved;
        su3_restore <= vu3_saved_phase;
        s_load <= '1';
        cycles;
        s_load <= '0';
        assert (su2820_state = vu2820_saved) report "Donor did not reload its advertised state vector" severity failure;
        s_hold <= '0';
        wait for 1 ns;
        for vint_cycle in vu74_trace'range loop
            if (su74_observed /= vu74_trace(vint_cycle)) then
                vint_differences := vint_differences + 1;
                if (vint_cycle >= 4096) then
                    vint_late_differences := vint_late_differences + 1;
                end if;
            end if;
            cycles;
        end loop;
        report "JT51_STATE_AUDIT_COMPLETE differences=" & integer'image(vint_differences) &
            " late_differences=" & integer'image(vint_late_differences) &
            " trace_cycles=32768 audible_cycles=" & integer'image(vint_nonzero);
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 10 ms;
        assert (false) report "JT51 state audit timed out" severity failure;
        wait;
    end process;
end architecture;
