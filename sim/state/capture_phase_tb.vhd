-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity capture_phase_tb is
    generic (
        GBOOL_EXTERNAL_PHASE_ENABLE : boolean := false
    );
end entity;

architecture test of capture_phase_tb is
    type t_trace is array(0 to 199) of unsigned(2 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize, s_user_pause : std_logic := '1';
    signal s_capture, s_monitor_held, s_resume : std_logic := '0';
    signal s_phi1, s_phi2, s_paused, s_held, s_enable : std_logic;
    signal s_e : std_logic := '0';
    signal sint_e_counter : natural range 0 to 9 := 0;
    signal sint_external_phase : natural range 0 to 6 := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when sint_external_phase = 0 or sint_external_phase = 3 else '0';
    controller : entity work.rabbitpunch_capture_phase
        generic map (
            GINT_PHASE_DIVIDER => 3,
            GBOOL_EXTERNAL_PHASE_ENABLE => GBOOL_EXTERNAL_PHASE_ENABLE
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_phase_enable => s_enable,
            i_user_pause => s_user_pause,
            i_bus_inactive => '1',
            i_capture_active => s_capture,
            i_monitor_held => s_monitor_held,
            i_peripheral_clock => s_e,
            i_resume => s_resume,
            o_enable_phase1 => s_phi1,
            o_enable_phase2 => s_phi2,
            o_paused => s_paused,
            o_capture_held => s_held
        );
    -- Exact E/eCntr recurrence from unchanged fx68k: enPhi2 advances modulo10,
    -- E rises at old count5 and falls at old count9. Full CPU integration is
    -- a separate test; this model checks the phase-controller contract only.
    peripheral_clock : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_initialize = '1') then
                sint_e_counter <= 0;
                s_e <= '0';
            elsif (s_phi2 = '1') then
                if (sint_e_counter = 9) then
                    sint_e_counter <= 0;
                    s_e <= '0';
                else
                    sint_e_counter <= sint_e_counter + 1;
                    if (sint_e_counter = 5) then
                        s_e <= '1';
                    end if;
                end if;
            end if;
            if (s_initialize = '1' or s_resume = '1') then
                sint_external_phase <= 0;
            elsif (sint_external_phase = 6) then
                sint_external_phase <= 0;
            else
                sint_external_phase <= sint_external_phase + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu3_trace : t_trace;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        for vint_case in 0 to 59 loop
            s_initialize <= '1';
            s_capture <= '0';
            s_monitor_held <= '0';
            cycles;
            s_initialize <= '0';
            cycles(10);
            assert (s_paused = '1' and s_phi1 = '0' and s_phi2 = '0') severity failure;
            s_capture <= '1';
            cycles(1 + vint_case);
            s_monitor_held <= '1';
            for vint_timeout in 0 to 499 loop
                exit when s_held = '1';
                cycles;
                assert (vint_timeout < 499) report "E canonicalization stalled" severity failure;
            end loop;
            assert (sint_e_counter = 0 and s_e = '0' and s_phi1 = '0' and s_phi2 = '0')
                report "Captured phase is not E-counter zero" severity failure;
            cycles(20);
            assert (sint_e_counter = 0 and s_held = '1') severity failure;
            s_resume <= '1';
            cycles;
            s_resume <= '0';
            s_monitor_held <= '0';
            wait for 1 ns;
            for vint_cycle in vu3_trace'range loop
                if (vint_case = 0) then
                    vu3_trace(vint_cycle) := unsigned'(s_phi1 & s_phi2 & s_e);
                else
                    assert (unsigned'(s_phi1 & s_phi2 & s_e) = vu3_trace(vint_cycle))
                        report "Post-capture phase depends on acquisition timing" severity failure;
                end if;
                cycles;
            end loop;
            s_capture <= '0';
            cycles;
            assert (s_paused = '1' and s_phi1 = '0' and s_phi2 = '0') severity failure;
        end loop;
        report "CAPTURE_PHASE_PASS sixty acquisition phases,12000 identical resume clocks,user pause,internal/external enable contract" severity note;
        stop;
        wait;
    end process;
end architecture;
