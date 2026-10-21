-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_config.all;
use std.env.all;

entity cheats_host_tb is
end entity;

architecture test of cheats_host_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_start_ready : std_logic := '1';
    signal s_framework_reset : std_logic := '1';
    signal s_host_download, s_host_write : std_logic := '0';
    signal su16_host_index : unsigned(15 downto 0) := (others => '0');
    signal su27_host_address : unsigned(26 downto 0) := (others => '0');
    signal su8_host_data : unsigned(7 downto 0) := (others => '0');
    signal s_host_wait, s_error, s_ddr_mode : std_logic;
    signal sint_word_base : natural := 0;
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
    process
        constant CSTR_CONFIG : string := F_STATE_CONFIG(true);
        constant CSTR_EXPECTED : string := "DIP;-;C,Cheats;-;";
        variable vbool_found : boolean := false;
    begin
        for vint_index in CSTR_CONFIG'low to CSTR_CONFIG'high - CSTR_EXPECTED'length + 1 loop
            if (CSTR_CONFIG(vint_index to vint_index + CSTR_EXPECTED'length - 1) = CSTR_EXPECTED) then
                vbool_found := true;
            end if;
        end loop;
        assert (vbool_found) report "State OSD lost separated Cheats submenu" severity failure;
        wait;
    end process;
    s_clk <= not s_clk after 10417 ps;
    s_ddr_busy <= '1' when sint_cycles < 24 or sint_cycles mod 19 < 5 else '0';
    s_word_ready <= '1' when s_initialize = '0' and sint_cycles mod 11 >= 7 else '0';
    dut : entity work.rabbitpunch_load_frontend
        generic map (GINT_IMAGE_BYTES => 64)
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_framework_reset => s_framework_reset,
            i_start_ready => s_start_ready,
            i_host_download => s_host_download,
            iu16_host_index => su16_host_index,
            i_host_write => s_host_write,
            iu27_host_byte_address => su27_host_address,
            iu8_host_data => su8_host_data,
            o_host_wait => s_host_wait,
            o_download_active => s_active,
            o_error => s_error,
            o_ddr_mode => s_ddr_mode,
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
                vu16_expected := byte_value((sint_words - sint_word_base) * 2 + 1, sint_epoch) &
                    byte_value((sint_words - sint_word_base) * 2, sint_epoch);
                assert (su27_word_address = (sint_words - sint_word_base) * 2 and su16_word_data = vu16_expected)
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
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure begin_rom(vint_epoch : natural) is
        begin
            cycles(1);
            sint_epoch <= vint_epoch;
            sint_word_base <= sint_words;
            su16_host_index <= (others => '0');
            s_framework_reset <= '1';
            s_host_download <= '1';
            cycles(2);
        end procedure;
        procedure host_byte(vint_address, vint_epoch : natural) is
        begin
            if (s_host_wait /= '0') then
                wait until s_host_wait = '0' for 20 us;
            end if;
            assert (s_host_wait = '0') report "Host byte path remained blocked" severity failure;
            cycles(1);
            su27_host_address <= to_unsigned(vint_address, 27);
            su8_host_data <= byte_value(vint_address, vint_epoch);
            s_host_write <= '1';
            cycles(1);
            s_host_write <= '0';
            su27_host_address <= (others => '1');
            su8_host_data <= (others => '1');
        end procedure;
        procedure complete_transaction(v_error : std_logic) is
        begin
            wait until s_done = '1' for 100 us;
            assert (s_done = '1' and s_error = v_error) report "Frontend did not finish with expected status" severity failure;
            cycles(2);
            assert (s_active = '0') report "Frontend did not release its transaction after drain" severity failure;
        end procedure;
    begin
        wait for 2 us;
        cycles(1);
        s_initialize <= '0';
        -- Metadata and reset events alone must never copy an old DDR image.
        for vint_index in 0 to 2 loop
            if (vint_index = 2) then
                su16_host_index <= to_unsigned(255, 16);
            else
                su16_host_index <= to_unsigned(1 + vint_index * 253, 16);
            end if;
            s_host_download <= '1';
            s_host_write <= '1';
            cycles(3);
            s_host_write <= '0';
            s_host_download <= '0';
            cycles(3);
            assert (s_active = '0' and sint_reads = 0 and sint_words = 0)
                report "Non-ROM metadata armed image loading" severity failure;
        end loop;
        s_framework_reset <= '0';
        cycles(10);
        assert (sint_reads = 0) report "Reset release without a ROM download copied stale DDR" severity failure;
        s_start_ready <= '0';
        begin_rom(0);
        cycles(20);
        assert (s_active = '0' and s_host_wait = '1' and sint_reads = 0)
            report "Frontend accepted a new image before downstream drain" severity failure;
        s_start_ready <= '1';
        cycles(3);
        s_host_download <= '0';
        cycles(12);
        assert (s_active = '1' and s_ddr_mode = '1' and sint_reads = 0)
            report "DDR copy did not wait for framework reset release" severity failure;
        s_framework_reset <= '0';
        complete_transaction('0');
        assert (sint_words = 32 and sint_reads = 8) report "DDR frontend copy count mismatch" severity failure;
        s_framework_reset <= '1';
        cycles(20);
        s_framework_reset <= '0';
        cycles(20);
        assert (sint_reads = 8 and s_active = '0') report "Soft reset recopied the loaded image" severity failure;
        -- First byte arrives with download's rising edge, while reset stays high.
        cycles(1);
        sint_epoch <= 1;
        sint_word_base <= sint_words;
        s_framework_reset <= '1';
        su16_host_index <= (others => '0');
        s_host_download <= '1';
        s_host_write <= '1';
        su27_host_address <= (others => '0');
        su8_host_data <= byte_value(0, 1);
        cycles(1);
        s_host_write <= '0';
        for vint_byte in 1 to 63 loop
            host_byte(vint_byte, 1);
        end loop;
        s_host_download <= '0';
        complete_transaction('0');
        assert (sint_words = 64 and sint_reads = 8 and s_ddr_mode = '0')
            report "Byte-stream mode copied DDR or lost a pair" severity failure;
        s_framework_reset <= '0';
        cycles(20);
        assert (sint_reads = 8) report "Byte-stream reset release overwrote the image from DDR" severity failure;
        begin_rom(1);
        for vint_byte in 0 to 2 loop
            host_byte(vint_byte, 1);
        end loop;
        s_host_download <= '0';
        complete_transaction('1');
        assert (sint_words = 65 and sint_reads = 8) report "Odd image did not drain its accepted word safely" severity failure;
        begin_rom(1);
        host_byte(2, 1);
        s_host_download <= '0';
        complete_transaction('1');
        assert (sint_words = 65) report "Nonsequential byte address reached the word stream" severity failure;
        -- Overlap is rejected while the old copy continues to drain its read debt.
        begin_rom(0);
        s_host_download <= '0';
        s_framework_reset <= '0';
        wait until s_ddr_read = '1' for 20 us;
        assert (s_ddr_read = '1') report "Overlap test never started an outstanding read" severity failure;
        cycles(1);
        s_host_download <= '1';
        cycles(4);
        assert (s_error = '1') report "Overlapping ROM transaction was not rejected" severity failure;
        s_host_download <= '0';
        complete_transaction('1');
        assert (sint_reads = 16 and sint_words = 97) report "Rejected overlap canceled or repeated the old copy" severity failure;
        begin_rom(1);
        s_host_download <= '0';
        s_framework_reset <= '0';
        complete_transaction('0');
        assert (sint_reads = 24 and sint_words = 129 and sint_dones = 6)
            report "Frontend did not recover into a fresh complete DDR copy" severity failure;
        report "CHEATS_HOST_PASS ddr_copies=3 direct_images=1 rejected_images=2 overlap=checked soft_reset_no_recopy=checked metadata_filter=checked first_byte_on_start=checked";
        finish;
        wait;
    end process;
end architecture;
