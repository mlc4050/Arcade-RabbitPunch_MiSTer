-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity fm_netlist_state_tb is
end entity;

architecture test of fm_netlist_state_tb is
    type t_words is array(0 to 125) of unsigned(31 downto 0);
    type t_trace is array(0 to 4095) of unsigned(73 downto 0);
    component jt51 is
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen : in std_logic;
            cen_p1 : in std_logic;
            cs_n : in std_logic;
            wr_n : in std_logic;
            a0 : in std_logic;
            din : in unsigned(7 downto 0);
            dout : out unsigned(7 downto 0);
            ct1 : out std_logic;
            ct2 : out std_logic;
            irq_n : out std_logic;
            sample : out std_logic;
            left : out unsigned(15 downto 0);
            right : out unsigned(15 downto 0);
            xleft : out unsigned(15 downto 0);
            xright : out unsigned(15 downto 0)
        );
    end component;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_hold, s_load, s_phase_load, s_compare_native, s_write, s_data_register : std_logic := '0';
    signal su3_phase, su3_restore : unsigned(2 downto 0) := (others => '0');
    signal s_enable, s_half, s_irq_n, s_sample : std_logic;
    signal su8_data, su8_status : unsigned(7 downto 0) := (others => '0');
    signal su16_left, su16_right, su16_full_left, su16_full_right : unsigned(15 downto 0);
    signal su16_state_address : unsigned(15 downto 0) := (others => '0');
    signal su32_state_read, su32_state_write : unsigned(31 downto 0) := (others => '0');
    signal su8_native_status : unsigned(7 downto 0);
    signal s_native_irq_n, s_native_sample : std_logic;
    signal su16_native_left, su16_native_right, su16_native_full_left, su16_native_full_right : unsigned(15 downto 0);
    signal su74_native : unsigned(73 downto 0);
    signal su74_observed : unsigned(73 downto 0);
begin
    su74_native <= su8_native_status & s_native_irq_n & s_native_sample & su16_native_left & su16_native_right & su16_native_full_left & su16_native_full_right;
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when s_hold = '0' and (su3_phase = 3 or su3_phase = 7) else '0';
    s_half <= '1' when s_hold = '0' and su3_phase = 7 else '0';
    su74_observed <= su8_status & s_irq_n & s_sample & su16_left & su16_right & su16_full_left & su16_full_right;
    cadence : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_phase_load = '1') then
                su3_phase <= su3_restore;
            elsif (s_hold = '0') then
                su3_phase <= su3_phase + 1;
            end if;
        end if;
    end process;
    native : jt51
        port map (
            rst => s_reset,
            clk => s_clk,
            cen => s_enable,
            cen_p1 => s_half,
            cs_n => '0',
            wr_n => not s_write,
            a0 => s_data_register,
            din => su8_data,
            dout => su8_native_status,
            ct1 => open,
            ct2 => open,
            irq_n => s_native_irq_n,
            sample => s_native_sample,
            left => su16_native_left,
            right => su16_native_right,
            xleft => su16_native_full_left,
            xright => su16_native_full_right
        );
    chip : entity work.rabbitpunch_jt51_state_netlist
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_chip_enable => s_enable,
            i_half_chip_enable => s_half,
            i_chip_select_n => '0',
            i_write_n => not s_write,
            i_data_register => s_data_register,
            iu8_write_data => su8_data,
            ou8_status => su8_status,
            o_control1 => open,
            o_control2 => open,
            o_interrupt_n => s_irq_n,
            o_sample => s_sample,
            ou16_left_pcm => su16_left,
            ou16_right_pcm => su16_right,
            ou16_full_left_pcm => su16_full_left,
            ou16_full_right_pcm => su16_full_right,
            i_state_hold => s_hold,
            i_state_write => s_load,
            iu16_state_word_address => su16_state_address,
            iu32_state_write_data => su32_state_write,
            ou32_state_read_data => su32_state_read
        );
    stimulus : process
        variable vu32_image : t_words;
        variable vu3_saved_phase : unsigned(2 downto 0);
        variable vu74_trace : t_trace;
        variable vint_nonzero, vint_normal_checks : natural := 0;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
                if (s_compare_native = '1') then
                    assert (not is_x(su74_observed) and su74_observed = su74_native)
                        report "Generated FM normal operation differs from pristine native chip: generated=" &
                        to_hstring(su74_observed) & " native=" & to_hstring(su74_native) &
                        " phase=" & to_hstring(su3_phase) severity failure;
                    vint_normal_checks := vint_normal_checks + 1;
                end if;
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
            assert (su8_status(7) = '0') report "Generated FM write stayed busy" severity failure;
            cycles(8);
        end procedure;
    begin
        -- Keep the chip enables running while reset fills all shift storage.
        cycles(4096);
        s_reset <= '0';
        cycles(4096);
        -- Initialize through the real bus before comparing four-state native
        -- storage with FPGA power-up storage. Keep enables running throughout.
        for vint_register in 0 to 255 loop
            write_register(vint_register, 0);
            if (vint_register mod 64 = 63) then
                report "FM_NETLIST_INIT registers=" & integer'image(vint_register + 1);
            end if;
        end loop;
        write_register(1, 0);
        write_register(16#0F#, 0);
        write_register(16#18#, 0);
        write_register(16#19#, 16#80#);
        write_register(16#19#, 0);
        write_register(16#1B#, 0);
        -- The donor does not reset stopped timer counts. Initialize both via
        -- real load edges before asserting that every exported state bit is known.
        write_register(16#10#, 255);
        write_register(16#11#, 3);
        write_register(16#12#, 255);
        write_register(16#14#, 3);
        cycles(2048);
        write_register(16#14#, 16#30#);
        cycles(2048);
        s_compare_native <= '1';
        write_register(16#20#, 16#F8#);
        write_register(16#28#, 16#4C#);
        for vint_operator in 0 to 3 loop
            write_register(16#40# + 8 * vint_operator, 1);
            write_register(16#60# + 8 * vint_operator, 24);
            write_register(16#80# + 8 * vint_operator, 31);
            write_register(16#A0# + 8 * vint_operator, 0);
            write_register(16#C0# + 8 * vint_operator, 0);
            write_register(16#E0# + 8 * vint_operator, 15);
        end loop;
        write_register(16#08#, 16#78#);
        write_register(16#14#, 16#0F#);
        cycles(8192);
        report "FM_NETLIST_NORMAL_DONE checks=" & integer'image(vint_normal_checks);
        assert (s_irq_n = '0') report "FM state fixture missed pending timer IRQ" severity failure;
        s_compare_native <= '0';
        s_hold <= '1';
        cycles;
        vu3_saved_phase := su3_phase;
        for vint_word in vu32_image'range loop
            su16_state_address <= to_unsigned(vint_word, 16);
            cycles;
            assert (not is_x(su32_state_read)) report "Unknown generated FM scan word" severity failure;
            vu32_image(vint_word) := su32_state_read;
        end loop;
        cycles(20);
        for vint_word in vu32_image'range loop
            su16_state_address <= to_unsigned(vint_word, 16);
            cycles;
            assert (su32_state_read = vu32_image(vint_word)) report "FM freeze missed state" severity failure;
        end loop;
        s_hold <= '0';
        wait for 1 ns;
        for vint_cycle in vu74_trace'range loop
            assert (not is_x(su74_observed)) report "Generated FM output not initialized" severity failure;
            vu74_trace(vint_cycle) := su74_observed;
            if (su16_full_left /= 0 or su16_full_right /= 0) then
                vint_nonzero := vint_nonzero + 1;
            end if;
            cycles;
        end loop;
        assert (vint_nonzero > 1000) report "FM state test recorded a silent tone" severity failure;
        report "FM_NETLIST_TRACE_CAPTURED nonzero=" & integer'image(vint_nonzero);
        for vint_round in 1 to 3 loop
            cycles(1234 + vint_round);
            write_register(16#14#, 16#30#);
            cycles(16);
            assert (s_irq_n = '1') report "FM perturbation failed to clear timer IRQ" severity failure;
            s_hold <= '1';
            cycles;
            -- Complement every real state bit while frozen, including bits
            -- that happened to be zero in this tone, before restoring the image.
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                su32_state_write <= not vu32_image(vint_word);
                s_load <= '1';
                cycles;
            end loop;
            s_load <= '0';
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                cycles;
                if (vint_word = 125) then
                    assert (su32_state_read(15 downto 0) = not vu32_image(vint_word)(15 downto 0) and
                        su32_state_read(31 downto 16) = 0) report "FM tail state bit/padding differs" severity failure;
                else
                    assert (su32_state_read = not vu32_image(vint_word)) report "FM scan missed complemented state bit" severity failure;
                end if;
            end loop;
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                su32_state_write <= vu32_image(vint_word);
                s_load <= '1';
                cycles;
            end loop;
            s_load <= '0';
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                cycles;
                assert (su32_state_read = vu32_image(vint_word)) report "FM scan round trip differs" severity failure;
            end loop;
            su3_restore <= vu3_saved_phase;
            s_phase_load <= '1';
            cycles;
            s_phase_load <= '0';
            s_hold <= '0';
            wait for 1 ns;
            for vint_cycle in vu74_trace'range loop
                assert (not is_x(su74_observed) and su74_observed = vu74_trace(vint_cycle))
                    report "FM immediate continuation differs at cycle " & integer'image(vint_cycle) severity failure;
                cycles;
            end loop;
            report "FM_NETLIST_RESTORE_DONE round=" & integer'image(vint_round);
        end loop;
        assert (vint_normal_checks > 10000) report "FM native comparison too short" severity failure;
        report "FM_NETLIST_STATE_PASS normal_native_cycles=" & integer'image(vint_normal_checks) &
            " state_bits=4016 repeated_restores=3 immediate_continuation_cycles=12288 audible_cycles=" & integer'image(vint_nonzero);
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 10 ms;
        assert (false) report "FM netlist state test timed out" severity failure;
        wait;
    end process;
end architecture;
