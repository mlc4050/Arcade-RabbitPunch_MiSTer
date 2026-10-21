-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_sdram_types.all;

entity state_sdram_phase_tb is
    generic (
        GBOOL_CONCURRENT_CLIENTS : boolean := false
    );
end entity;

architecture test of state_sdram_phase_tb is
    component sdram_chip_model_wide is
        port (
            clk : in std_logic;
            SDRAM_DQ : inout unsigned(15 downto 0);
            SDRAM_A : in unsigned(12 downto 0);
            SDRAM_BA : in unsigned(1 downto 0);
            SDRAM_nCS : in std_logic;
            SDRAM_nWE : in std_logic;
            SDRAM_nRAS : in std_logic;
            SDRAM_nCAS : in std_logic
        );
    end component;
    constant CU64_PATTERN : unsigned(63 downto 0) := x"CAFEBABE76543210";
    type t_wave is array(0 to 255) of unsigned(8 downto 0);
    type t_counts is array(0 to 2) of natural;
    type t_ages is array(0 to 1023) of boolean;
    signal s_clk, s_chip_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_initialized, s_prepare, s_aligned, s_phase_idle, s_anchor, s_refresh : std_logic := '0';
    signal s_request, s_write : std_logic := '0';
    signal s_ready, s_valid : std_logic;
    signal su27_address : unsigned(26 downto 0) := (others => '0');
    signal su16_data : unsigned(15 downto 0) := (others => '0');
    signal su64_data : unsigned(63 downto 0);
    signal su3_requests, su3_writes : unsigned(2 downto 0) := (others => '0');
    signal su3_ready, su3_valid : unsigned(2 downto 0);
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su16_backend_data : t_sdram_write_data := (others => (others => '0'));
    signal su2_bytes : t_sdram_byte_enables := (others => "00");
    signal su64_read_data : t_sdram_read_data;
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_cs, s_we, s_ras, s_cas, s_cke : std_logic;
    signal sint_anchor_phase : natural range 0 to 2047 := 0;
    signal sint_refresh_age : natural range 0 to 1023 := 0;
begin
    s_clk <= not s_clk after 10714 ps;
    s_chip_clk <= transport s_clk after 5357 ps;
    s_anchor <= '1' when sint_anchor_phase = 0 else '0';
    s_refresh <= not s_ras and not s_cas and s_we;
    clocks : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_anchor_phase = 2047) then
                sint_anchor_phase <= 0;
            else
                sint_anchor_phase <= sint_anchor_phase + 1;
            end if;
            if (s_refresh = '1') then
                sint_refresh_age <= 0;
            elsif (sint_refresh_age < 1023) then
                sint_refresh_age <= sint_refresh_age + 1;
            end if;
        end if;
    end process;
    phase_control : entity work.rabbitpunch_state_sdram_phase
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_prepare => s_prepare,
            i_anchor => s_anchor,
            i_refresh => s_refresh,
            o_aligned => s_aligned,
            o_idle => s_phase_idle,
            i_client_request => s_request,
            i_client_write => s_write,
            iu27_client_address => su27_address,
            iu16_client_data => su16_data,
            iu2_client_bytes => "11",
            o_client_ready => s_ready,
            o_client_valid => s_valid,
            ou64_client_data => su64_data,
            o_backend_request => su3_requests(2),
            o_backend_write => su3_writes(2),
            ou27_backend_address => su27_addresses(2),
            ou16_backend_data => su16_backend_data(2),
            ou2_backend_bytes => su2_bytes(2),
            i_backend_ready => su3_ready(2),
            i_backend_valid => su3_valid(2),
            iu64_backend_data => su64_read_data(2),
            i_phase_known => '1',
            iu7_phase => to_unsigned(sint_anchor_phase mod 128, 7)
        );
    controller : entity work.rabbitpunch_sdram
        generic map (
            GINT_READ_CAPTURE_ADJUST => 1
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            o_initialized => s_initialized,
            iu3_requests => su3_requests,
            ou3_ready => su3_ready,
            iu3_writes => su3_writes,
            iu27_byte_addresses => su27_addresses,
            iu16_write_data => su16_backend_data,
            iu2_byte_enables => su2_bytes,
            ou3_response_valid => su3_valid,
            ou64_read_data => su64_read_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_sdram_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_cs,
            o_sdram_write_n => s_we,
            o_sdram_row_n => s_ras,
            o_sdram_column_n => s_cas,
            o_sdram_clock_enable => s_cke
        );
    chip : sdram_chip_model_wide
        port map (
            clk => s_chip_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_sdram_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_cs,
            SDRAM_nWE => s_we,
            SDRAM_nRAS => s_ras,
            SDRAM_nCAS => s_cas
        );
    stimulus : process
        variable vtyp_reference : t_wave;
        variable vtyp_ages : t_ages := (others => false);
        variable vu9_event : unsigned(8 downto 0);
        variable vtyp_reads : t_counts := (others => 0);
        variable vint_reads, vint_unique : natural := 0;
        variable vint_period, vint_expected : positive := 32;
        procedure P_TICK is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
    begin
        if (GBOOL_CONCURRENT_CLIENTS) then
            vint_period := 64;
            vint_expected := 4;
        else
            vint_expected := 8;
        end if;
        for vint_clock in 1 to 32 loop
            P_TICK;
        end loop;
        s_initialize <= '0';
        wait until s_initialized = '1';
        P_TICK;
        for vint_word in 0 to 3 loop
            su27_address <= to_unsigned(vint_word * 2, 27);
            su16_data <= CU64_PATTERN(vint_word * 16 + 15 downto vint_word * 16);
            s_write <= '1';
            s_request <= '1';
            P_TICK;
            s_request <= '0';
            wait until s_valid = '1';
            P_TICK;
        end loop;
        s_write <= '0';
        su27_address <= (others => '0');
        for vint_case in 0 to 162 loop
            for vint_delay in 1 to vint_case loop
                P_TICK;
            end loop;
            vtyp_ages(sint_refresh_age) := true;
            s_prepare <= '1';
            for vint_wait in 1 to 8192 loop
                P_TICK;
                assert (s_valid = '0') report "Private read leaked to normal client" severity failure;
                exit when s_aligned = '1';
            end loop;
            assert (s_aligned = '1' and s_phase_idle = '1')
                report "Read stream failed to normalize refresh" severity failure;
            P_TICK;
            s_prepare <= '0';
            wait for 1 ns;
            vint_reads := 0;
            vtyp_reads := (others => 0);
            for vint_clock in vtyp_reference'range loop
                if (vint_clock mod vint_period = 0) then
                    assert (s_ready = '1') report "Normal read not ready after alignment" severity failure;
                    s_request <= '1';
                    if (GBOOL_CONCURRENT_CLIENTS) then
                        assert (su3_ready(1 downto 0) = "11")
                            report "Concurrent clients not ready after alignment" severity failure;
                        su3_requests(1 downto 0) <= "11";
                    end if;
                else
                    s_request <= '0';
                    su3_requests(1 downto 0) <= "00";
                end if;
                P_TICK;
                vu9_event := su3_ready & su3_valid & s_we & s_ras & s_cas;
                if (vint_case = 0) then
                    vtyp_reference(vint_clock) := vu9_event;
                else
                    assert (vu9_event = vtyp_reference(vint_clock))
                        report "Normalized read timing differs case=" & integer'image(vint_case) &
                            " clock=" & integer'image(vint_clock)
                        severity failure;
                end if;
                for vint_port in 0 to 2 loop
                    if (su3_valid(vint_port) = '1') then
                        assert (su64_read_data(vint_port) = CU64_PATTERN)
                            report "Normalized read data differs" severity failure;
                        vtyp_reads(vint_port) := vtyp_reads(vint_port) + 1;
                    end if;
                end loop;
                assert (s_valid = su3_valid(2))
                    report "Normal client reply differs from owned physical port" severity failure;
            end loop;
            s_request <= '0';
            su3_requests(1 downto 0) <= "00";
            assert (vtyp_reads(2) = vint_expected) report "Read credit lost after alignment" severity failure;
            if (GBOOL_CONCURRENT_CLIENTS) then
                assert (vtyp_reads(0) = vint_expected and vtyp_reads(1) = vint_expected)
                    report "Concurrent read credit lost after alignment" severity failure;
            else
                assert (vtyp_reads(0) = 0 and vtyp_reads(1) = 0)
                    report "Unexpected inactive-port reply" severity failure;
            end if;
            P_TICK;
        end loop;
        for vint_age in vtyp_ages'range loop
            if (vtyp_ages(vint_age)) then
                vint_unique := vint_unique + 1;
            end if;
        end loop;
        for vint_age in 0 to 161 loop
            assert (vtyp_ages(vint_age))
                report "Missing initial refresh age=" & integer'image(vint_age) severity failure;
        end loop;
        for vint_cancel in 0 to 15 loop
            s_prepare <= '1';
            for vint_wait in 1 to 8192 loop
                P_TICK;
                exit when su3_requests(2) = '1';
            end loop;
            assert (su3_requests(2) = '1' and su3_ready(2) = '1')
                report "Cancellation did not reach a dummy-read offer" severity failure;
            P_TICK;
            for vint_delay in 1 to vint_cancel loop
                P_TICK;
                assert (s_valid = '0') report "Private response escaped before cancel" severity failure;
            end loop;
            s_prepare <= '0';
            wait for 1 ns;
            for vint_wait in 1 to 64 loop
                assert (s_valid = '0') report "Canceled private response escaped" severity failure;
                exit when s_ready = '1' and s_phase_idle = '1';
                P_TICK;
            end loop;
            assert (s_ready = '1' and s_phase_idle = '1')
                report "Canceled read ownership did not retire" severity failure;
            s_request <= '1';
            P_TICK;
            s_request <= '0';
            vint_reads := 0;
            for vint_wait in 1 to 64 loop
                P_TICK;
                if (s_valid = '1') then
                    assert (su64_data = CU64_PATTERN) report "Read after cancellation corrupted" severity failure;
                    vint_reads := vint_reads + 1;
                end if;
            end loop;
            assert (vint_reads = 1) report "Normal response credit lost/duplicated after cancel" severity failure;
        end loop;
        report "STATE_SDRAM_PHASE_PASS cases=163 concurrent=" & boolean'image(GBOOL_CONCURRENT_CLIENTS) &
            " reads_per_port=" & integer'image(vint_expected) & " cancels=16 ages=" & integer'image(vint_unique);
        finish;
    end process;
    timeout : process
    begin
        wait for 100 ms;
        assert (false) report "SDRAM phase test timeout" severity failure;
    end process;
end architecture;
