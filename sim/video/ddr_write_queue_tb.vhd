-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity ddr_write_queue_tb is
end entity;

architecture test of ddr_write_queue_tb is
    type t_packets is array(0 to 10000) of unsigned(100 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_write, s_expected_drop : std_logic := '0';
    signal s_busy : std_logic := '1';
    signal s_full, s_empty, s_overflow, s_ddr_write : std_logic;
    signal su29_address, su29_output_address : unsigned(28 downto 0) := (others => '0');
    signal su64_data, su64_output_data : unsigned(63 downto 0) := (others => '0');
    signal su8_bytes, su8_output_bytes : unsigned(7 downto 0) := (others => '0');
    signal sint_checked : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_ddr_write_queue
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_write => s_write,
            iu29_word_address => su29_address,
            iu64_data => su64_data,
            iu8_byte_enables => su8_bytes,
            o_full => s_full,
            o_empty => s_empty,
            o_overflow => s_overflow,
            i_ddr_busy => s_busy,
            o_ddr_write => s_ddr_write,
            ou29_ddr_word_address => su29_output_address,
            ou64_ddr_data => su64_output_data,
            ou8_ddr_byte_enables => su8_output_bytes
        );
    scoreboard : process
        variable v_expected : t_packets;
        variable vint_written, vint_read, vint_total : natural := 0;
        variable v_previous_stall : boolean := false;
        variable vu101_held : unsigned(100 downto 0) := (others => '0');
    begin
        wait until rising_edge(s_clk);
        if (s_initialize = '1') then
            assert (s_ddr_write = '0') report "Queue issued DDR write during initialization" severity failure;
            vint_written := 0;
            vint_read := 0;
            v_previous_stall := false;
        else
            if (v_previous_stall) then
                assert ((su29_output_address & su64_output_data & su8_output_bytes) = vu101_held)
                    report "Queue changed the stalled output packet" severity failure;
            end if;
            if (s_ddr_write = '1') then
                assert (s_busy = '0' and vint_read < vint_written)
                    report "Queue issued an unowned DDR write" severity failure;
                assert ((su29_output_address & su64_output_data & su8_output_bytes) = v_expected(vint_read))
                    report "Queue reordered, corrupted or duplicated a packet" severity failure;
                vint_read := vint_read + 1;
                vint_total := vint_total + 1;
                sint_checked <= vint_total;
            end if;
            if (s_write = '1') then
                if (s_expected_drop = '1') then
                    assert (s_full = '1' and s_busy = '1') report "Overflow stimulus was not full and stalled" severity failure;
                else
                    assert (vint_written <= v_expected'high) report "Queue test expectation capacity exceeded" severity failure;
                    v_expected(vint_written) := su29_address & su64_data & su8_bytes;
                    vint_written := vint_written + 1;
                end if;
            end if;
            v_previous_stall := s_busy = '1' and s_empty = '0';
            vu101_held := su29_output_address & su64_output_data & su8_output_bytes;
        end if;
        wait until falling_edge(s_clk);
        assert ((s_empty = '1') = (vint_written = vint_read))
            report "Queue empty flag disagrees with independently accepted traffic" severity failure;
    end process;
    stimulus : process
        variable vu16_random : unsigned(15 downto 0) := x"ACE1";
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait until falling_edge(s_clk);
        end procedure;
        procedure packet(constant CINT_SEQUENCE : natural) is
        begin
            su29_address <= to_unsigned(16#4800000# + CINT_SEQUENCE * 8, 29);
            su64_data <= shift_left(to_unsigned(CINT_SEQUENCE, 64), 32) xor unsigned'(x"91E2D3C4B5A69788");
            su8_bytes <= rotate_left(to_unsigned(1, 8), CINT_SEQUENCE mod 8);
        end procedure;
    begin
        tick;
        s_initialize <= '0';
        s_write <= '1';
        for vint_sequence in 0 to 511 loop
            packet(vint_sequence);
            tick;
        end loop;
        assert (s_full = '1' and s_empty = '0') report "Queue did not hold exactly 512 stalled packets" severity failure;
        packet(512);
        s_expected_drop <= '1';
        tick;
        s_write <= '0';
        s_expected_drop <= '0';
        assert (s_overflow = '1') report "Queue overflow was not recorded" severity failure;
        s_busy <= '0';
        while (s_empty = '0') loop
            tick;
        end loop;
        assert (sint_checked = 512 and s_overflow = '1') report "Overflow overwrote accepted packets or failed to stay sticky" severity failure;
        for vint_sequence in 1000 to 8999 loop
            vu16_random := vu16_random(14 downto 0) &
                (vu16_random(15) xor vu16_random(13) xor vu16_random(12) xor vu16_random(10));
            s_busy <= vu16_random(0) and vu16_random(1);
            s_write <= not s_full and vu16_random(2);
            packet(vint_sequence);
            tick;
        end loop;
        s_write <= '0';
        s_busy <= '0';
        while (s_empty = '0') loop
            tick;
        end loop;
        assert (sint_checked > 3000) report "Insufficient queue wraparound traffic" severity failure;
        s_busy <= '1';
        s_write <= '1';
        for vint_sequence in 9000 to 9006 loop
            packet(vint_sequence);
            tick;
        end loop;
        s_initialize <= '1';
        tick;
        s_write <= '0';
        assert (s_empty = '1' and s_overflow = '0') report "Queue reset did not discard pending presentation state" severity failure;
        s_initialize <= '0';
        s_busy <= '0';
        s_write <= '1';
        packet(10000);
        tick;
        s_write <= '0';
        tick;
        tick;
        assert (s_empty = '1' and s_overflow = '0') report "Queue leaked stale packets after reset" severity failure;
        report "DDR_WRITE_QUEUE_PASS checked=" & integer'image(sint_checked) & " capacity=512 overflow=pass reset=pass";
        finish;
    end process;
    watchdog : process
    begin
        wait for 1 ms;
        assert (false) report "Queue test did not finish" severity failure;
        wait;
    end process;
end architecture;
