-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity ddr_copy_tb is
end entity;

architecture test of ddr_copy_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_start : std_logic := '0';
    signal s_active, s_done, s_word_valid, s_word_ready : std_logic;
    signal su27_word_address : unsigned(26 downto 0);
    signal su16_word_data : unsigned(15 downto 0);
    signal s_ddr_busy, s_ddr_read, s_ddr_write : std_logic;
    signal s_ddr_valid : std_logic := '0';
    signal su8_burst, su8_bytes : unsigned(7 downto 0);
    signal su29_address : unsigned(28 downto 0);
    signal su64_read_data, su64_write_data : unsigned(63 downto 0) := (others => '0');
    signal sint_cycles, sint_reads, sint_words, sint_dones : natural := 0;
    signal sint_epoch : natural range 0 to 1 := 0;
    function byte_value(vint_address, vint_epoch : natural) return unsigned is
    begin
        return to_unsigned((vint_address + vint_epoch * 64) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 10417 ps;
    s_ddr_busy <= '1' when sint_cycles < 24 or sint_cycles mod 19 < 5 else '0';
    s_word_ready <= '1' when s_initialize = '0' and sint_cycles mod 11 >= 7 else '0';
    dut : entity work.rabbitpunch_ddr_copy
        generic map (sint_IMAGE_BYTES => 64)
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            o_active => s_active,
            o_done => s_done,
            o_word_valid => s_word_valid,
            i_word_ready => s_word_ready,
            ou27_word_byte_address => su27_word_address,
            ou16_word_data => su16_word_data,
            i_ddr_busy => s_ddr_busy,
            ou8_ddr_burst_count => su8_burst,
            ou29_ddr_word_address => su29_address,
            iu64_ddr_read_data => su64_read_data,
            i_ddr_read_valid => s_ddr_valid,
            o_ddr_read => s_ddr_read,
            ou64_ddr_write_data => su64_write_data,
            ou8_ddr_byte_enables => su8_bytes,
            o_ddr_write => s_ddr_write
        );
    backend : process(s_clk)
        variable v_pending, v_stalled : boolean := false;
        variable vint_delay, vint_base, vint_epoch : natural := 0;
        variable vu27_stalled_address : unsigned(26 downto 0);
        variable vu16_stalled_data : unsigned(15 downto 0);
        variable vu64_reply : unsigned(63 downto 0);
        variable vu16_expected : unsigned(15 downto 0);
    begin
        if (rising_edge(s_clk)) then
            sint_cycles <= sint_cycles + 1;
            s_ddr_valid <= '0';
            -- Deliberately spoil the shared data pins outside the valid beat.
            su64_read_data <= x"BAD0BAD1BAD2BAD3";
            assert (s_ddr_write = '0') report "Load-only DDR transport wrote staging memory" severity failure;
            if (s_ddr_read = '1') then
                assert (s_ddr_busy = '0' and not v_pending and su8_burst = 1 and su8_bytes = x"FF")
                    report "Invalid or repeated physical DDR read" severity failure;
                assert (su29_address = to_unsigned(16#6000000# + sint_reads mod 8, 29))
                    report "DDR base/word addressing mismatch" severity failure;
                vint_base := (sint_reads mod 8) * 8;
                vint_epoch := sint_epoch;
                vint_delay := 3 + (sint_reads mod 7) * 5;
                v_pending := true;
                sint_reads <= sint_reads + 1;
            elsif (v_pending) then
                if (vint_delay = 0) then
                    for vint_byte in 0 to 7 loop
                        vu64_reply(vint_byte * 8 + 7 downto vint_byte * 8) := byte_value(vint_base + vint_byte, vint_epoch);
                    end loop;
                    su64_read_data <= vu64_reply;
                    s_ddr_valid <= '1';
                    v_pending := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (v_stalled) then
                assert (s_word_valid = '1' and su27_word_address = vu27_stalled_address and su16_word_data = vu16_stalled_data)
                    report "DDR output word/address changed during backpressure" severity failure;
            end if;
            v_stalled := s_word_valid = '1' and s_word_ready = '0';
            vu27_stalled_address := su27_word_address;
            vu16_stalled_data := su16_word_data;
            if (s_word_valid = '1' and s_word_ready = '1') then
                vu16_expected := byte_value((sint_words mod 32) * 2 + 1, sint_epoch) &
                    byte_value((sint_words mod 32) * 2, sint_epoch);
                assert (su27_word_address = (sint_words mod 32) * 2 and su16_word_data = vu16_expected)
                    report "DDR copy lost/repeated/reordered a word or swapped its byte lanes" severity failure;
                sint_words <= sint_words + 1;
            end if;
            if (s_done = '1') then
                assert (s_active = '0' and s_word_valid = '0' and not v_pending)
                    report "DDR copy finished before its output drained" severity failure;
                sint_dones <= sint_dones + 1;
            end if;
        end if;
    end process;
    process
    begin
        wait for 2 us;
        wait until falling_edge(s_clk);
        s_initialize <= '0';
        for vint_copy in 0 to 1 loop
            sint_epoch <= vint_copy;
            s_start <= '1';
            wait until falling_edge(s_clk);
            s_start <= '0';
            wait until s_done = '1' for 100 us;
            assert (s_done = '1') report "DDR copy stalled" severity failure;
            wait until falling_edge(s_clk);
            wait until falling_edge(s_clk);
            assert (sint_words = (vint_copy + 1) * 32 and sint_reads = (vint_copy + 1) * 8 and sint_dones = vint_copy + 1)
                report "DDR copy transaction counts do not match image length" severity failure;
        end loop;
        report "DDR_COPY_PASS copies=2 words=64 granules=16 delayed_replies=checked held_word_backpressure=checked warm_restart=checked";
        finish;
        wait;
    end process;
end architecture;
