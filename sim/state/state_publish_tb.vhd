-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;

entity state_publish_tb is
end entity;

architecture test of state_publish_tb is
    type t_controls is array(0 to 3) of unsigned(63 downto 0);
    signal su64_controls : t_controls := (x"000000010000000A", x"000000010000000B",
        x"000000010000000C", x"000000010000000D");
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel, s_new_case : std_logic := '0';
    signal s_valid : std_logic := '1';
    signal s_image_read, s_image_reply, s_image_error, s_ddr_read, s_ddr_write, s_ddr_reply : std_logic := '0';
    signal s_active, s_finished, s_success, s_ddr_busy : std_logic;
    signal su2_slot : unsigned(1 downto 0) := (others => '0');
    signal su18_image_address : unsigned(17 downto 0);
    signal su8_image_data : unsigned(7 downto 0);
    signal su29_ddr_address : unsigned(28 downto 0);
    signal su64_ddr_data, su64_ddr_reply : unsigned(63 downto 0);
    signal su3_error : unsigned(2 downto 0);
    signal sint_case, sint_reads, sint_payload, sint_phase, sint_slot : natural := 0;
    signal sint_image_debt, sint_ddr_debt : natural := 0;
    signal s_invalidated, s_committed : std_logic := '0';
    signal su32_previous : unsigned(31 downto 0);
    function F_BYTE(vint_address : natural) return unsigned is
    begin
        return to_unsigned((vint_address*19 + vint_address/128 + 57) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_ddr_busy <= '1' when sint_phase < 7 or
        (sint_case = 7 and sint_payload = CINT_IMAGE_BYTES/8) else '0';
    dut : entity work.rabbitpunch_state_publish
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            i_image_valid => s_valid,
            iu2_slot => su2_slot,
            o_image_read => s_image_read,
            ou18_image_address => su18_image_address,
            i_image_response => s_image_reply,
            i_image_error => s_image_error,
            iu8_image_data => su8_image_data,
            o_ddr_read => s_ddr_read,
            o_ddr_write => s_ddr_write,
            ou29_ddr_word_address => su29_ddr_address,
            ou64_ddr_write_data => su64_ddr_data,
            i_ddr_busy => s_ddr_busy,
            i_ddr_read_valid => s_ddr_reply,
            iu64_ddr_read_data => su64_ddr_reply,
            o_active => s_active,
            o_finished => s_finished,
            o_success => s_success,
            ou3_error => su3_error
        );
    endpoints : process(s_clk)
        variable vint_image_debt, vint_ddr_debt, vint_image_address : natural := 0;
        variable vu64_control : unsigned(63 downto 0);
        variable vu29_base : unsigned(28 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_image_reply <= '0';
            s_image_error <= '0';
            s_ddr_reply <= '0';
            sint_phase <= (sint_phase + 1) mod 25;
            if (s_new_case = '1') then
                assert (vint_image_debt = 0 and vint_ddr_debt = 0) severity failure;
                sint_reads <= 0;
                sint_payload <= 0;
                s_invalidated <= '0';
                s_committed <= '0';
                su32_previous <= su64_controls(sint_slot)(31 downto 0);
            end if;
            if (s_image_read = '1') then
                assert (vint_image_debt = 0 and su18_image_address = sint_reads) severity failure;
                vint_image_debt := 6;
                vint_image_address := to_integer(su18_image_address);
                sint_reads <= sint_reads + 1;
            elsif (vint_image_debt > 0) then
                vint_image_debt := vint_image_debt - 1;
                if (vint_image_debt = 0) then
                    s_image_reply <= '1';
                    su8_image_data <= F_BYTE(vint_image_address);
                    if (sint_case = 3 and vint_image_address = 40) then
                        s_image_error <= '1';
                    end if;
                end if;
            end if;
            vu29_base := to_unsigned(16#07C00000# + sint_slot*32768, 29);
            assert (not (s_ddr_read = '1' and s_ddr_write = '1')) severity failure;
            assert (s_ddr_busy = '0' or (s_ddr_read = '0' and s_ddr_write = '0')) severity failure;
            if (s_ddr_read = '1') then
                assert (vint_ddr_debt = 0 and su29_ddr_address = vu29_base) severity failure;
                vu64_control := su64_controls(sint_slot);
                vint_ddr_debt := 9;
            elsif (vint_ddr_debt > 0) then
                vint_ddr_debt := vint_ddr_debt - 1;
                if (vint_ddr_debt = 0) then
                    s_ddr_reply <= '1';
                    su64_ddr_reply <= vu64_control;
                end if;
            end if;
            if (s_ddr_write = '1') then
                if (su29_ddr_address = vu29_base) then
                    if (s_invalidated = '0') then
                        assert (su64_ddr_data = (to_unsigned(0, 32) & su32_previous) and sint_payload = 0)
                            report "Publication overwrote payload before invalidating slot" severity failure;
                        s_invalidated <= '1';
                    else
                        assert (sint_payload = CINT_IMAGE_BYTES/8 and
                            su64_ddr_data = (to_unsigned(CINT_IMAGE_BYTES/4, 32) & (su32_previous + 1)))
                            report "Publication committed wrong length/counter or incomplete payload" severity failure;
                        assert (s_committed = '0') severity failure;
                        s_committed <= '1';
                    end if;
                    su64_controls(sint_slot) <= su64_ddr_data;
                else
                    assert (s_invalidated = '1' and s_committed = '0' and
                        su29_ddr_address = vu29_base + 1 + sint_payload) severity failure;
                    for vint_lane in 0 to 7 loop
                        assert (su64_ddr_data(8*vint_lane + 7 downto 8*vint_lane) =
                            F_BYTE(sint_payload*8 + vint_lane)) report "Published payload corrupted/reordered" severity failure;
                    end loop;
                    sint_payload <= sint_payload + 1;
                end if;
            end if;
            sint_image_debt <= vint_image_debt;
            sint_ddr_debt <= vint_ddr_debt;
        end if;
    end process;
    stimulus : process
        variable vint_expected_error : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        cycles(2);
        for vint_case in 0 to 8 loop
            sint_case <= vint_case;
            sint_slot <= vint_case mod 4;
            su2_slot <= to_unsigned(vint_case mod 4, 2);
            s_new_case <= '1';
            s_valid <= '1';
            cycles;
            s_new_case <= '0';
            if (vint_case = 6) then
                s_valid <= '0';
            end if;
            s_start <= '1';
            cycles;
            s_start <= '0';
            su2_slot <= to_unsigned((vint_case + 1) mod 4, 2);
            vint_expected_error := 0;
            if (vint_case = 1 or vint_case = 4) then
                while (sint_image_debt = 0 or sint_ddr_debt = 0) loop
                    cycles;
                end loop;
                if (vint_case = 1) then
                    s_cancel <= '1';
                    vint_expected_error := 2;
                else
                    s_initialize <= '1';
                end if;
                cycles;
                s_cancel <= '0';
                s_initialize <= '0';
                assert (s_active = '1') report "Publisher discarded accepted source/DDR read debt" severity failure;
            elsif (vint_case = 2) then
                while (sint_payload < 4) loop
                    cycles;
                end loop;
                s_valid <= '0';
                vint_expected_error := 1;
            elsif (vint_case = 3) then
                vint_expected_error := 3;
            elsif (vint_case = 6) then
                vint_expected_error := 1;
            elsif (vint_case = 7) then
                while (sint_payload < CINT_IMAGE_BYTES/8) loop
                    cycles;
                end loop;
                cycles(8);
                assert (s_committed = '0') severity failure;
                s_cancel <= '1';
                cycles;
                s_cancel <= '0';
                vint_expected_error := 2;
            end if;
            for vint_timeout in 0 to 1999999 loop
                exit when s_finished = '1' or (vint_case = 4 and s_active = '0');
                cycles;
                assert (vint_timeout < 1999999) report "Publisher timeout" severity failure;
            end loop;
            assert (su3_error = vint_expected_error) report "Wrong publication error" severity failure;
            if (vint_case = 0 or vint_case = 5 or vint_case = 8) then
                assert (s_success = '1' and s_committed = '1' and sint_payload = CINT_IMAGE_BYTES/8)
                    report "Full publication failed" severity failure;
            else
                assert (s_success = '0' and s_committed = '0') severity failure;
                if (s_invalidated = '1') then
                    assert (su64_controls(sint_slot)(63 downto 32) = 0 and
                        su64_controls(sint_slot)(31 downto 0) = su32_previous)
                        report "Canceled publication exposed complete slot" severity failure;
                end if;
            end if;
            assert (sint_image_debt = 0 and sint_ddr_debt = 0) severity failure;
            cycles(12);
        end loop;
        report "STATE_PUBLISH_PASS full image,all slots,repeated publication,final counter,stalls,dual debt,cancel/reset,permission,error,retry" severity note;
        stop;
        wait;
    end process;
end architecture;
