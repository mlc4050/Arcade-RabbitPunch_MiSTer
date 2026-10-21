-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;

entity state_apply_tb is
end entity;

architecture test of state_apply_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_reset_completed, s_start, s_cancel : std_logic := '0';
    signal s_valid, s_held : std_logic := '1';
    signal s_hold, s_read, s_image_reply, s_image_error : std_logic := '0';
    signal s_write, s_ready, s_body_reply, s_body_error, s_commit, s_committed : std_logic := '0';
    signal s_commit_error : std_logic;
    signal s_active, s_finished, s_success, s_incomplete : std_logic;
    signal su18_image_address, su18_body_address : unsigned(17 downto 0);
    signal su8_image_data, su8_body_data : unsigned(7 downto 0);
    signal su4_error : unsigned(3 downto 0);
    signal sint_case : natural := 0;
    signal sint_reads, sint_writes, sint_commits : natural := 0;
    signal s_new_case : std_logic := '0';
    function F_BYTE(vint_address : natural) return unsigned is
    begin
        return to_unsigned((vint_address*37 + vint_address/256 + 91) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_commit_error <= '1' when sint_case = 14 else '0';
    dut : entity work.rabbitpunch_state_apply
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_reset_completed => s_reset_completed,
            i_start => s_start,
            i_cancel => s_cancel,
            i_image_valid => s_valid,
            i_machine_held => s_held,
            o_machine_hold_request => s_hold,
            o_image_read => s_read,
            ou18_image_address => su18_image_address,
            i_image_response => s_image_reply,
            i_image_error => s_image_error,
            iu8_image_data => su8_image_data,
            o_body_request => s_write,
            i_body_ready => s_ready,
            ou18_body_address => su18_body_address,
            ou8_body_data => su8_body_data,
            i_body_response => s_body_reply,
            i_body_error => s_body_error,
            o_body_commit => s_commit,
            i_body_committed => s_committed,
            i_body_commit_error => s_commit_error,
            o_active => s_active,
            o_finished => s_finished,
            o_success => s_success,
            o_incomplete => s_incomplete,
            ou4_error => su4_error
        );
    -- Accepted transactions retire despite cancel/reset. The fixture checks
    -- every byte against an independent address-based oracle, including RAM
    -- boundaries and the final sound-chip word, rather than echoing DUT data.
    backend : process(s_clk)
        variable vint_read_debt, vint_write_debt, vint_commit_debt : natural := 0;
        variable vint_read_address, vint_write_address : natural := 0;
        variable vint_phase : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            s_image_reply <= '0';
            s_body_reply <= '0';
            s_committed <= '0';
            s_image_error <= '0';
            s_body_error <= '0';
            vint_phase := (vint_phase + 1) mod 5;
            s_ready <= '1';
            if (vint_phase < 2) then
                s_ready <= '0';
            end if;
            if (s_new_case = '1') then
                assert (vint_read_debt = 0 and vint_write_debt = 0 and vint_commit_debt = 0)
                    report "New application started with backend debt" severity failure;
                sint_reads <= 0;
                sint_writes <= 0;
                sint_commits <= 0;
            end if;
            if (s_read = '1') then
                assert (vint_read_debt = 0 and vint_write_debt = 0) severity failure;
                assert (su18_image_address = sint_reads + 64) severity failure;
                vint_read_address := to_integer(su18_image_address) - 64;
                vint_read_debt := 6;
                sint_reads <= sint_reads + 1;
            elsif (vint_read_debt > 0) then
                vint_read_debt := vint_read_debt - 1;
                if (vint_read_debt = 0) then
                    s_image_reply <= '1';
                    su8_image_data <= F_BYTE(vint_read_address);
                    if (sint_case = 6 and vint_read_address = 16) then
                        s_image_error <= '1';
                    end if;
                end if;
            end if;
            if (s_write = '1' and s_ready = '1') then
                assert (vint_write_debt = 0 and vint_read_debt = 0) severity failure;
                assert (su18_body_address = sint_writes and su8_body_data = F_BYTE(sint_writes))
                    report "Application skipped/reordered/corrupted a body byte" severity failure;
                vint_write_address := to_integer(su18_body_address);
                vint_write_debt := 7;
                sint_writes <= sint_writes + 1;
            elsif (vint_write_debt > 0) then
                vint_write_debt := vint_write_debt - 1;
                if (vint_write_debt = 0) then
                    s_body_reply <= '1';
                    if (sint_case = 7 and vint_write_address = 16) then
                        s_body_error <= '1';
                    end if;
                end if;
            end if;
            if (s_commit = '1') then
                assert (sint_writes = CINT_BODY_BYTES and vint_write_debt = 0 and
                    vint_commit_debt = 0) report "Premature/repeated body commit" severity failure;
                vint_commit_debt := 9;
                sint_commits <= sint_commits + 1;
            elsif (vint_commit_debt > 0) then
                vint_commit_debt := vint_commit_debt - 1;
                if (vint_commit_debt = 0) then
                    s_committed <= '1';
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_expected_error : natural;
        variable s_expected_incomplete : std_logic;
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
        for vint_case in 0 to 14 loop
            sint_case <= vint_case;
            s_new_case <= '1';
            s_valid <= '1';
            s_held <= '1';
            cycles;
            s_new_case <= '0';
            if (vint_case = 1) then
                s_valid <= '0';
            elsif (vint_case = 2) then
                s_held <= '0';
            end if;
            s_start <= '1';
            cycles;
            s_start <= '0';
            vint_expected_error := 0;
            s_expected_incomplete := '0';
            case vint_case is
                when 1 => vint_expected_error := 2;
                when 2 => vint_expected_error := 3;
                when 3 | 8 =>
                    while (sint_reads < 1) loop
                        cycles;
                    end loop;
                    if (vint_case = 3) then
                        s_cancel <= '1';
                        vint_expected_error := 1;
                    else
                        s_valid <= '0';
                        vint_expected_error := 2;
                    end if;
                    cycles;
                    s_cancel <= '0';
                    assert (s_active = '1' and s_hold = '1') severity failure;
                when 4 | 5 | 9 =>
                    while (sint_writes < 64) loop
                        cycles;
                    end loop;
                    if (vint_case = 4) then
                        s_cancel <= '1';
                        vint_expected_error := 1;
                    elsif (vint_case = 5) then
                        s_initialize <= '1';
                    else
                        s_held <= '0';
                        vint_expected_error := 3;
                    end if;
                    cycles;
                    s_cancel <= '0';
                    s_initialize <= '0';
                    s_expected_incomplete := '1';
                    assert (s_active = '1' and s_hold = '1') severity failure;
                when 6 =>
                    vint_expected_error := 4;
                    s_expected_incomplete := '1';
                when 7 =>
                    vint_expected_error := 5;
                    s_expected_incomplete := '1';
                when 14 =>
                    vint_expected_error := 6;
                    s_expected_incomplete := '1';
                when 10 | 11 =>
                    while (sint_commits = 0) loop
                        cycles;
                    end loop;
                    if (vint_case = 10) then
                        s_cancel <= '1';
                        vint_expected_error := 1;
                    else
                        s_initialize <= '1';
                    end if;
                    cycles;
                    s_cancel <= '0';
                    s_initialize <= '0';
                    s_expected_incomplete := '1';
                    assert (s_active = '1' and s_hold = '1') severity failure;
                when others => null;
            end case;
            for vint_timeout in 0 to 2999999 loop
                exit when s_finished = '1' or ((vint_case = 5 or vint_case = 11) and s_active = '0');
                cycles;
                assert (vint_timeout < 2999999) report "Application timeout" severity failure;
            end loop;
            assert (su4_error = vint_expected_error) report "Wrong application error" severity failure;
            if (vint_case = 0 or vint_case = 12 or vint_case = 13) then
                assert (s_success = '1' and sint_writes = CINT_BODY_BYTES and sint_commits = 1)
                    report "Complete application failed" severity failure;
            else
                assert (s_success = '0') severity failure;
            end if;
            -- Earlier failed writes can carry an incomplete lease into a
            -- subsequent read-only cancellation. It must never clear itself.
            if (vint_case >= 4 and vint_case <= 11) then
                s_expected_incomplete := '1';
            end if;
            assert (s_incomplete = s_expected_incomplete and s_hold = s_expected_incomplete)
                report "Application released an incomplete machine" severity failure;
            if (vint_case = 11 or vint_case = 14) then
                s_reset_completed <= '1';
                cycles;
                s_reset_completed <= '0';
                assert (s_incomplete = '0' and s_hold = '0')
                    report "Completed game reset did not release partial restore" severity failure;
            end if;
            cycles(12);
        end loop;
        report "STATE_APPLY_PASS full ordered body,stalls,admission,read/write/commit debt,cancel/reset,permission/hold loss,errors,retries" severity note;
        stop;
        wait;
    end process;
end architecture;
