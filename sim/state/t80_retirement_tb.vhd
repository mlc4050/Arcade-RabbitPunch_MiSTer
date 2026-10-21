-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity t80_retirement_tb is
end entity;

architecture test of t80_retirement_tb is
    type t_bytes is array(natural range <>) of unsigned(7 downto 0);
    -- LD A,E retires its accumulator write at the following M1/T1 edge.
    constant CU8_PREFIX : t_bytes := (
        x"F3", x"31", x"00", x"90",
        x"01", x"00", x"00", x"11", x"00", x"00", x"21", x"00", x"00",
        x"DD", x"21", x"00", x"00", x"FD", x"21", x"00", x"00",
        x"D9", x"01", x"00", x"00", x"11", x"00", x"00", x"21", x"00", x"00", x"D9",
        x"AF", x"08", x"AF", x"08", x"11", x"34", x"12", x"3E", x"00", x"7B"
    );
    constant CINT_FETCH : natural := CU8_PREFIX'length;
    constant CU8_PROGRAM : t_bytes := CU8_PREFIX & t_bytes'(
        x"32", x"00", x"80", x"C3", to_unsigned(CINT_FETCH, 8), x"00");
    type t_event is record
        su16_address : unsigned(15 downto 0);
        su8_data : unsigned(7 downto 0);
        su7_bus : unsigned(6 downto 0);
        su256_state : unsigned(255 downto 0);
    end record;
    type t_trace is array(0 to 255) of t_event;
    signal s_clk : std_logic := '0';
    signal s_reset_n, s_request, s_resume, s_load, s_held, s_clean, s_cancel : std_logic := '0';
    signal s_fetch_n, s_memory_n, s_io_n, s_read_n, s_write_n, s_refresh_n, s_halt_n : std_logic;
    signal su16_address : unsigned(15 downto 0);
    signal su8_read, su8_write : unsigned(7 downto 0);
    signal su256_state, su256_load : unsigned(255 downto 0) := (others => '0');
    signal sint_writes : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    su8_read <= CU8_PROGRAM(to_integer(su16_address)) when
        su16_address < CU8_PROGRAM'length else x"00";
    candidate : entity work.rabbitpunch_t80_capture
        port map (
            i_clk => s_clk,
            i_reset_n => s_reset_n,
            i_clock_enable => '1',
            i_wait_n => '1',
            i_interrupt_n => '1',
            o_opcode_fetch_n => s_fetch_n,
            o_memory_request_n => s_memory_n,
            o_io_request_n => s_io_n,
            o_read_n => s_read_n,
            o_write_n => s_write_n,
            o_refresh_n => s_refresh_n,
            o_halted_n => s_halt_n,
            ou16_address => su16_address,
            iu8_read_data => su8_read,
            ou8_write_data => su8_write,
            i_capture_request => s_request,
            i_cancel => s_cancel,
            i_bus_drained => s_memory_n and s_io_n,
            o_capture_pending => open,
            o_held => s_held,
            i_resume => s_resume,
            i_state_write => s_load,
            iu256_state_data => su256_load,
            ou256_state_data => su256_state,
            o_clean_boundary => s_clean,
            ou3_machine_cycle => open,
            ou3_clock_phase => open
        );
    observe_writes : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_reset_n = '1' and s_memory_n = '0' and s_write_n = '0') then
                assert (su16_address = x"8000" and su8_write = x"34")
                    report "Retired LD A,E result lost before memory write" severity failure;
                sint_writes <= sint_writes + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu256_image : unsigned(255 downto 0);
        variable vtyp_trace : t_trace;
        variable vtyp_event : t_event;
        procedure P_HOLD(constant CBOOL_CANCEL_AFTER_RETIRE : boolean := false) is
        begin
            s_request <= '1';
            if (CBOOL_CANCEL_AFTER_RETIRE) then
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
                s_cancel <= '1';
            end if;
            wait until s_held = '1';
            wait until falling_edge(s_clk);
            s_request <= '0';
            s_cancel <= '0';
        end procedure;
        procedure P_RELEASE is
        begin
            s_resume <= '1';
            wait until rising_edge(s_clk);
            wait until falling_edge(s_clk);
            s_resume <= '0';
        end procedure;
    begin
        wait for 25 ns;
        wait until falling_edge(s_clk);
        s_reset_n <= '1';
        loop
            wait until falling_edge(s_clk);
            exit when s_clean = '1' and su16_address = CINT_FETCH;
        end loop;
        P_HOLD(true);
        vu256_image := su256_state;
        assert (vu256_image(7 downto 0) = x"34")
            report "Capture precedes delayed accumulator retirement" severity failure;
        assert (vu256_image(79 downto 64) = CINT_FETCH)
            report "Canonicalization consumed the next opcode" severity failure;
        for vint_round in 0 to 3 loop
            if (vint_round /= 0) then
                P_HOLD;
                su256_load <= vu256_image;
                s_load <= '1';
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
                s_load <= '0';
                assert (su256_state = vu256_image)
                    report "Retirement image did not reload exactly" severity failure;
            end if;
            P_RELEASE;
            for vint_clock in vtyp_trace'range loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
                vtyp_event.su16_address := su16_address;
                vtyp_event.su8_data := (others => '0');
                if (s_memory_n = '0' and s_write_n = '0') then
                    vtyp_event.su8_data := su8_write;
                end if;
                vtyp_event.su7_bus := s_fetch_n & s_memory_n & s_io_n &
                    s_read_n & s_write_n & s_refresh_n & s_halt_n;
                vtyp_event.su256_state := su256_state;
                if (vint_round = 0) then
                    vtyp_trace(vint_clock) := vtyp_event;
                else
                    assert (vtyp_event = vtyp_trace(vint_clock))
                        report "Retirement continuation differs round=" &
                            integer'image(vint_round) & " clock=" & integer'image(vint_clock) &
                            " address=" & to_hstring(vtyp_event.su16_address) & "/" & to_hstring(vtyp_trace(vint_clock).su16_address) &
                            " bus=" & to_hstring(vtyp_event.su7_bus) & "/" & to_hstring(vtyp_trace(vint_clock).su7_bus) &
                            " data=" & to_hstring(vtyp_event.su8_data) & "/" & to_hstring(vtyp_trace(vint_clock).su8_data) &
                            " state=" & to_hstring(vtyp_event.su256_state) & "/" & to_hstring(vtyp_trace(vint_clock).su256_state)
                        severity failure;
                end if;
            end loop;
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_writes >= 32) report "Insufficient continuation writes" severity failure;
        report "T80_RETIREMENT_PASS restores=3 clocks=256" severity note;
        finish;
    end process;
    timeout : process
    begin
        wait for 100 us;
        assert (false) report "Retirement test timeout" severity failure;
    end process;
end architecture;
