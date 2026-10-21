-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_sdram_types.all;

entity state_read_arbiter_tb is
    generic (
        GBOOL_INVALID_NORMALIZE : boolean := false
    );
end entity;

architecture test of state_read_arbiter_tb is
    signal s_clk : std_logic := '0';
    signal s_normalize, s_idle, s_backend_request, s_backend_valid, s_backend_ready : std_logic := '0';
    signal su3_requests : unsigned(2 downto 0) := "000";
    signal su3_ready, su3_valid : unsigned(2 downto 0);
    signal su27_addresses : t_sdram_addresses := (to_unsigned(0, 27), to_unsigned(8, 27), to_unsigned(16, 27));
    signal su64_data : t_sdram_read_data;
    signal su27_backend_address : unsigned(26 downto 0);
    signal su64_backend_data : unsigned(63 downto 0) := (others => '0');
    signal s_backend_pending, s_check_order, s_group_start : std_logic := '0';
    signal sint_phase : natural range 0 to 6 := 0;
    signal sint_delay : natural range 0 to 8 := 0;
    signal sint_owner, sint_first : natural range 0 to 2 := 0;
    signal sint_accepted : natural range 0 to 3 := 0;
    constant CU64_BASE : unsigned(63 downto 0) := x"12345678ABCDEF00";
begin
    s_clk <= not s_clk after 5 ns;
    s_backend_ready <= '1' when s_backend_pending = '0' and sint_phase /= 2 and sint_phase /= 3 else '0';
    candidate : entity work.rabbitpunch_read_arbiter
        port map (
            i_clk => s_clk,
            i_enable => not s_normalize,
            o_idle => s_idle,
            iu3_requests => su3_requests,
            ou3_ready => su3_ready,
            iu27_byte_addresses => su27_addresses,
            ou3_response_valid => su3_valid,
            ou64_read_data => su64_data,
            o_backend_request => s_backend_request,
            ou27_backend_byte_address => su27_backend_address,
            i_backend_ready => s_backend_ready,
            i_backend_response_valid => s_backend_valid,
            iu64_backend_read_data => su64_backend_data,
            i_state_normalize => s_normalize
        );
    backend : process(s_clk)
        variable vint_client, vint_expected : natural;
    begin
        if (rising_edge(s_clk)) then
            if (sint_phase = 6) then
                sint_phase <= 0;
            else
                sint_phase <= sint_phase + 1;
            end if;
            s_backend_valid <= '0';
            if (s_group_start = '1') then
                sint_accepted <= 0;
            end if;
            if (s_backend_pending = '1') then
                if (sint_delay = 0) then
                    s_backend_pending <= '0';
                    s_backend_valid <= '1';
                    su64_backend_data <= CU64_BASE + sint_owner;
                else
                    sint_delay <= sint_delay - 1;
                end if;
            elsif (s_backend_request = '1' and s_backend_ready = '1') then
                vint_client := to_integer(su27_backend_address) / 8;
                assert (vint_client < 3) severity failure;
                sint_owner <= vint_client;
                sint_delay <= 3 + vint_client;
                s_backend_pending <= '1';
                if (s_check_order = '1') then
                    vint_expected := (sint_first + sint_accepted) mod 3;
                    assert (vint_client = vint_expected) report "Round-robin state not normalized" severity failure;
                    sint_accepted <= sint_accepted + 1;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_responses : natural;
        procedure P_TICK is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
    begin
        P_TICK;
        for vint_normalized in 0 to 1 loop
            for vint_seed in 0 to 2 loop
                su3_requests(vint_seed) <= '1';
                P_TICK;
                su3_requests <= "000";
                for vint_wait in 1 to 64 loop
                    P_TICK;
                    exit when su3_valid(vint_seed) = '1';
                end loop;
                assert (su3_valid(vint_seed) = '1' and su64_data(vint_seed) = CU64_BASE + vint_seed)
                    report "Seed response lost" severity failure;
                P_TICK;
                assert (s_idle = '1') severity failure;
                if (vint_normalized = 1) then
                    s_normalize <= '1';
                    P_TICK;
                    s_normalize <= '0';
                    sint_first <= 0;
                else
                    sint_first <= (vint_seed + 1) mod 3;
                end if;
                s_check_order <= '1';
                s_group_start <= '1';
                su3_requests <= "111";
                P_TICK;
                su3_requests <= "000";
                s_group_start <= '0';
                if (GBOOL_INVALID_NORMALIZE) then
                    s_normalize <= '1';
                end if;
                vint_responses := 0;
                for vint_wait in 1 to 128 loop
                    P_TICK;
                    for vint_client in 0 to 2 loop
                        if (su3_valid(vint_client) = '1') then
                            assert (su64_data(vint_client) = CU64_BASE + vint_client)
                                report "Response owner/data changed" severity failure;
                            vint_responses := vint_responses + 1;
                        end if;
                    end loop;
                    exit when vint_responses = 3 and s_idle = '1';
                end loop;
                assert (vint_responses = 3 and sint_accepted = 3 and s_idle = '1')
                    report "Read arbiter lost or duplicated a credit" severity failure;
                s_check_order <= '0';
                P_TICK;
            end loop;
        end loop;
        report "STATE_READ_ARBITER_PASS seeds=3 normal_and_normalized replies=24";
        finish;
    end process;
    timeout : process
    begin
        wait for 100 us;
        assert (false) report "Read arbiter test timeout" severity failure;
    end process;
end architecture;
