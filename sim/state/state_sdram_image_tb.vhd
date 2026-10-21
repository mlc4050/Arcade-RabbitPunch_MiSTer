-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.rabbitpunch_sdram_types.all;

-- Native controller/chip readback of every supplied ROM byte. Only normal
-- adapter transactions populate SDRAM; there are no memory/register deposits.
entity state_sdram_image_tb is
    generic (
        GINT_IMAGE_BYTES : positive := 16#210000#
    );
end entity;

architecture test of state_sdram_image_tb is
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
    signal s_clk, s_chip_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_initialized : std_logic;
    signal su3_requests, su3_writes : unsigned(2 downto 0) := (others => '0');
    signal su3_ready, su3_valid : unsigned(2 downto 0);
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su16_data : t_sdram_write_data := (others => (others => '0'));
    signal su2_bytes : t_sdram_byte_enables := (others => "11");
    signal su64_read_data : t_sdram_read_data;
    signal su16_dq : unsigned(15 downto 0);
    signal su13_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_cs, s_we, s_ras, s_cas, s_cke : std_logic;
begin
    s_clk <= not s_clk after 10714 ps;
    s_chip_clk <= transport s_clk after 5357 ps;
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
            iu16_write_data => su16_data,
            iu2_byte_enables => su2_bytes,
            ou3_response_valid => su3_valid,
            ou64_read_data => su64_read_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_address,
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
            SDRAM_A => su13_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_cs,
            SDRAM_nWE => s_we,
            SDRAM_nRAS => s_ras,
            SDRAM_nCAS => s_cas
        );
    stimulus : process
        file v_input : text;
        variable v_line : line;
        variable vu64_expected : unsigned(63 downto 0);
        variable vint_reads, vint_writes : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure transaction(vint_client, vint_address : natural;
                              vbool_write : boolean;
                              vu16_data : unsigned(15 downto 0)) is
            variable vbool_received : boolean := false;
        begin
            for vint_wait in 0 to 127 loop
                exit when su3_ready(vint_client) = '1';
                tick;
            end loop;
            assert (su3_ready(vint_client) = '1') report "SDRAM client not ready" severity failure;
            su27_addresses(vint_client) <= to_unsigned(vint_address, 27);
            su16_data(vint_client) <= vu16_data;
            if (vbool_write) then
                su3_writes(vint_client) <= '1';
            else
                su3_writes(vint_client) <= '0';
            end if;
            su3_requests(vint_client) <= '1';
            tick;
            su3_requests(vint_client) <= '0';
            for vint_wait in 0 to 127 loop
                tick;
                if (su3_valid(vint_client) = '1') then
                    vbool_received := true;
                    exit;
                end if;
            end loop;
            assert (vbool_received) report "SDRAM response timeout" severity failure;
            if (not vbool_write) then
                assert (su64_read_data(vint_client) = vu64_expected)
                    report "Real-image SDRAM readback differs at byte " & integer'image(vint_address) &
                        " expected " & to_hstring(vu64_expected) & " received " & to_hstring(su64_read_data(vint_client))
                    severity failure;
            end if;
            tick;
        end procedure;
    begin
        assert (GINT_IMAGE_BYTES mod 8 = 0) severity failure;
        for vint_cycle in 1 to 32 loop
            tick;
        end loop;
        s_initialize <= '0';
        for vint_cycle in 1 to 10000 loop
            exit when s_initialized = '1';
            tick;
        end loop;
        assert (s_initialized = '1') report "SDRAM initialization timeout" severity failure;
        file_open(v_input, "rom64.hex", read_mode);
        for vint_burst in 0 to GINT_IMAGE_BYTES / 8 - 1 loop
            readline(v_input, v_line);
            hread(v_line, vu64_expected);
            for vint_lane in 0 to 3 loop
                transaction(2, vint_burst * 8 + vint_lane * 2, true,
                    vu64_expected(vint_lane * 16 + 15 downto vint_lane * 16));
                vint_writes := vint_writes + 1;
            end loop;
        end loop;
        file_close(v_input);
        file_open(v_input, "rom64.hex", read_mode);
        for vint_burst in 0 to GINT_IMAGE_BYTES / 8 - 1 loop
            readline(v_input, v_line);
            hread(v_line, vu64_expected);
            transaction(vint_burst mod 3, vint_burst * 8, false, x"0000");
            vint_reads := vint_reads + 1;
        end loop;
        assert (endfile(v_input)) report "ROM fixture contains unchecked data" severity failure;
        file_close(v_input);
        report "STATE_SDRAM_IMAGE_PASS bytes=" & integer'image(GINT_IMAGE_BYTES) &
            " writes=" & integer'image(vint_writes) & " bursts=" & integer'image(vint_reads);
        finish;
    end process;
    bound : process
    begin
        wait for 2 sec;
        assert (false) report "Native image readback simulation bound" severity failure;
    end process;
end architecture;
