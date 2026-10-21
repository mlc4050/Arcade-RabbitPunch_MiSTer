-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_machine_access_tb is
    generic (
        GBOOL_RESUME_REQUEST : boolean := false
    );
end entity;

architecture test of state_machine_access_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_acquire, s_cancel, s_release, s_incomplete : std_logic := '0';
    signal s_nvram_quiesced, s_nvram_ready, s_legacy_idle : std_logic := '0';
    signal s_main_idle, s_sound_idle, s_transport_idle, s_banks_idle : std_logic := '1';
    signal s_main_held, s_main_error, s_sound_held, s_sound_drained : std_logic := '0';
    signal s_return_held, s_main_resumed, s_main_canceled, s_aligned : std_logic := '0';
    signal s_scores_load, s_scores_data, s_scores_ready : std_logic := '0';
    signal s_ready, s_busy, s_held, s_finished, s_canceled, s_reset_drained : std_logic;
    signal su4_error : unsigned(3 downto 0);
    signal s_pause, s_quiesce, s_reconcile, s_main_capture, s_sound_capture, s_capture_cancel : std_logic;
    signal s_hold, s_video_flush, s_rom_flush, s_bank_session, s_main_resume : std_logic;
    signal s_private, s_main_release, s_sound_resume : std_logic;
    signal s_sdram_prepare, s_effective_transport_idle : std_logic;
    signal sint_captures, sint_flushes, sint_reconciles, sint_releases : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_effective_transport_idle <= s_transport_idle and s_hold when
        GBOOL_RESUME_REQUEST and s_sdram_prepare = '1' else s_transport_idle;
    access_barrier : entity work.rabbitpunch_state_machine_access
        generic map (
            GINT_TIMEOUT_CYCLES => 32
        )
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_acquire => s_acquire,
            i_cancel => s_cancel,
            i_release => s_release,
            i_incomplete => s_incomplete,
            i_nvram_quiesced => s_nvram_quiesced,
            i_nvram_ready => s_nvram_ready,
            i_legacy_idle => s_legacy_idle,
            i_main_bus_idle => s_main_idle,
            i_sound_bus_idle => s_sound_idle,
            i_main_held => s_main_held,
            i_main_error => s_main_error,
            i_sound_held => s_sound_held,
            i_sound_drained => s_sound_drained,
            i_transport_idle => s_effective_transport_idle,
            i_banks_idle => s_banks_idle,
            i_main_return_held => s_return_held,
            i_main_resumed => s_main_resumed,
            i_main_resume_canceled => s_main_canceled,
            i_aligned => s_aligned,
            i_scores_ready_load => s_scores_load,
            i_scores_ready_data => s_scores_data,
            o_scores_ready => s_scores_ready,
            o_ready => s_ready,
            o_busy => s_busy,
            o_held => s_held,
            o_finished => s_finished,
            o_canceled => s_canceled,
            ou4_error => su4_error,
            o_reset_drained => s_reset_drained,
            o_pause => s_pause,
            o_nvram_quiesce => s_quiesce,
            o_legacy_quiesce => open,
            o_nvram_reconcile => s_reconcile,
            o_main_capture => s_main_capture,
            o_sound_capture => s_sound_capture,
            o_capture_cancel => s_capture_cancel,
            o_game_hold => s_hold,
            o_video_flush => s_video_flush,
            o_rom_flush => s_rom_flush,
            o_bank_session => s_bank_session,
            o_main_resume => s_main_resume,
            o_private_return => s_private,
            o_main_release => s_main_release,
            o_sound_resume => s_sound_resume,
            o_sdram_prepare => s_sdram_prepare
        );
    protocol : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            assert (s_main_capture = s_sound_capture) report "CPU capture requests were not paired" severity failure;
            assert (s_main_release = s_sound_resume) report "CPU release was not common" severity failure;
            if (s_main_capture = '1') then
                assert (s_nvram_quiesced = '1' and s_legacy_idle = '1') report "Capture stole a legacy session" severity failure;
                sint_captures <= sint_captures + 1;
            end if;
            if (s_rom_flush = '1') then
                assert (s_transport_idle = '1' and s_hold = '1') report "Cache flush lost drained hold" severity failure;
                sint_flushes <= sint_flushes + 1;
            end if;
            if (s_reconcile = '1') then
                assert (s_hold = '1' and s_quiesce = '1' and s_main_release = '0')
                    report "NVRAM reconciliation escaped held lease" severity failure;
                sint_reconciles <= sint_reconciles + 1;
            end if;
            if (s_main_release = '1') then
                assert (s_aligned = '1' and s_hold = '0' and s_private = '0' and s_pause = '0' and
                    s_video_flush = '0' and s_bank_session = '0' and s_incomplete = '0')
                    report "Machine release missed its exact alignment edge" severity failure;
                sint_releases <= sint_releases + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_before, vint_flushes, vint_releases, vint_reconciles : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure cold_reset is
        begin
            s_reset <= '1';
            s_main_held <= '0';
            s_sound_held <= '0';
            s_sound_drained <= '0';
            s_main_error <= '0';
            s_return_held <= '0';
            s_main_resumed <= '0';
            s_main_canceled <= '0';
            s_cancel <= '0';
            s_incomplete <= '0';
            s_main_idle <= '1';
            s_sound_idle <= '1';
            s_banks_idle <= '1';
            s_transport_idle <= '1';
            s_legacy_idle <= '1';
            s_nvram_quiesced <= '1';
            s_aligned <= '0';
            cycles;
            s_reset <= '0';
            cycles;
            assert (s_ready = '1' and s_reset_drained = '1') report "Drained reset never released" severity failure;
        end procedure;
        procedure acquire is
        begin
            s_acquire <= '1';
            cycles;
            s_acquire <= '0';
            for vint_wait in 0 to 20 loop
                exit when (s_main_capture = '1');
                cycles;
            end loop;
            assert (s_main_capture = '1' and s_hold = '0') report "Capture request missing or premature freeze" severity failure;
            cycles;
        end procedure;
        procedure hold_machine is
        begin
            s_main_held <= '1';
            s_sound_held <= '1';
            s_sound_drained <= '1';
            for vint_wait in 0 to 20 loop
                exit when (s_held = '1');
                cycles;
            end loop;
            assert (s_held = '1' and s_hold = '1' and s_bank_session = '1') report "Machine banks never became accessible" severity failure;
        end procedure;
        procedure begin_return is
        begin
            for vint_wait in 0 to 20 loop
                exit when (s_main_resume = '1');
                cycles;
            end loop;
            assert (s_main_resume = '1' and s_private = '1' and s_bank_session = '0') report "Private return did not get drained ownership" severity failure;
            cycles;
            s_return_held <= '1';
        end procedure;
        procedure align_and_finish(v_canceled : std_logic := '0') is
        begin
            for vint_wait in 0 to 20 loop
                exit when (s_reconcile = '1');
                cycles;
            end loop;
            assert (s_reconcile = '1' and s_main_release = '0') report "Reconciliation missing before alignment" severity failure;
            cycles(3);
            assert (s_hold = '1' and s_main_release = '0') report "Physical beam wait was skipped" severity failure;
            -- Alignment is one clock per frame, not a persistent ready level.
            s_aligned <= '1';
            wait for 1 ns;
            assert (s_main_release = '1' and s_hold = '0' and s_private = '0')
                report "Release was delayed beyond the matching clock" severity failure;
            cycles;
            s_aligned <= '0';
            s_main_held <= '0';
            s_sound_held <= '0';
            s_sound_drained <= '0';
            s_return_held <= '0';
            s_main_resumed <= not v_canceled;
            s_main_canceled <= v_canceled;
            cycles;
            s_main_resumed <= '0';
            s_main_canceled <= '0';
            assert (s_ready = '1' and s_finished = '1' and s_quiesce = '0' and s_pause = '0')
                report "Completed machine continuation did not release its lease" severity failure;
        end procedure;
    begin
        cold_reset;
        -- Cancellation before any CPU request is safe and needs no RTE.
        s_nvram_quiesced <= '0';
        s_acquire <= '1';
        cycles;
        s_acquire <= '0';
        cycles(3);
        s_cancel <= '1';
        cycles;
        s_cancel <= '0';
        assert (s_ready = '1' and s_finished = '1' and s_canceled = '1' and sint_captures = 0)
            report "Early cancellation disturbed CPUs" severity failure;
        s_acquire <= '1';
        cycles;
        s_acquire <= '0';
        cycles(36);
        assert (s_ready = '1' and su4_error = 2 and sint_captures = 0) report "NVRAM timeout did not safely release" severity failure;
        s_nvram_quiesced <= '1';
        s_nvram_ready <= '1';
        s_legacy_idle <= '0';
        s_acquire <= '1';
        cycles;
        s_acquire <= '0';
        cycles(4);
        assert (s_main_capture = '0' and s_hold = '0') report "Capture stole accepted maintenance debt" severity failure;
        s_legacy_idle <= '1';
        s_sound_idle <= '0';
        cycles(3);
        assert (s_main_capture = '0') report "Capture ignored sound debt" severity failure;
        s_sound_idle <= '1';
        cycles;
        assert (s_main_capture = '1') report "Drained capture did not start" severity failure;
        cycles;
        s_main_held <= '1';
        cycles(3);
        assert (s_hold = '0') report "Chips froze before sound CPU drained" severity failure;
        s_transport_idle <= '0';
        s_sound_held <= '1';
        s_sound_drained <= '1';
        cycles(4);
        assert (s_hold = '1' and s_held = '0' and s_rom_flush = '0') report "Pending ROM read did not retain drain barrier" severity failure;
        s_transport_idle <= '1';
        cycles(2);
        assert (s_held = '1' and s_scores_ready = '1' and sint_flushes = 1) report "Entry normalization/readiness capture failed" severity failure;
        -- Cancel with an accepted bank reply still pending.
        s_banks_idle <= '0';
        s_cancel <= '1';
        cycles;
        s_cancel <= '0';
        cycles(4);
        assert (s_bank_session = '1' and s_main_resume = '0') report "Cancellation dropped bank debt" severity failure;
        s_banks_idle <= '1';
        begin_return;
        s_transport_idle <= '0';
        cycles(4);
        assert (s_private = '1' and s_hold = '1' and s_main_release = '0') report "Return ignored pending transport" severity failure;
        s_transport_idle <= '1';
        align_and_finish('1');
        assert (s_canceled = '1' and sint_flushes = 2 and sint_releases = 1) report "Canceled continuation counts differ" severity failure;
        -- Complete retries can repair an unsafe partially applied image.
        for vint_round in 1 to 3 loop
            vint_flushes := sint_flushes;
            vint_releases := sint_releases;
            vint_reconciles := sint_reconciles;
            s_nvram_ready <= '0';
            acquire;
            hold_machine;
            s_scores_data <= '1';
            s_scores_load <= '1';
            cycles;
            s_scores_load <= '0';
            s_incomplete <= '1';
            s_release <= '1';
            cycles;
            s_release <= '0';
            cycles(4);
            assert (s_held = '1' and s_hold = '1' and su4_error = 6 and s_main_resume = '0') report "Partial application escaped held banks" severity failure;
            cycles(40);
            assert (s_held = '1' and s_main_release = '0') report "Unsafe hold expired into execution" severity failure;
            s_incomplete <= '0';
            s_release <= '1';
            cycles;
            s_release <= '0';
            begin_return;
            align_and_finish;
            assert (s_scores_ready = '1' and sint_flushes = vint_flushes + 2 and
                sint_releases = vint_releases + 1 and sint_reconciles = vint_reconciles + 1 and su4_error = 0)
                report "Repeated retry/normalization/release differs" severity failure;
        end loop;
        -- Failed acquisition cannot release a partially captured machine.
        acquire;
        s_main_error <= '1';
        cycles;
        assert (s_ready = '0' and su4_error = 1 and s_pause = '1' and s_main_release = '0') report "Capture error released CPUs" severity failure;
        cold_reset;
        acquire;
        cycles(36);
        assert (s_ready = '0' and su4_error = 2 and s_pause = '1') report "Acquisition timeout released a taken monitor" severity failure;
        cold_reset;
        acquire;
        hold_machine;
        s_release <= '1';
        cycles;
        s_release <= '0';
        begin_return;
        cycles(40);
        assert (s_ready = '0' and su4_error = 2 and s_hold = '1' and s_main_release = '0')
            report "Alignment timeout released the held game" severity failure;
        cold_reset;
        -- Reset completion also waits for every old accepted credit.
        s_banks_idle <= '0';
        s_main_idle <= '0';
        s_reset <= '1';
        cycles;
        s_reset <= '0';
        cycles(4);
        assert (s_ready = '0' and s_bank_session = '1' and s_reset_drained = '0') report "Reset erased bank debt" severity failure;
        s_banks_idle <= '1';
        cycles(3);
        assert (s_ready = '0') report "Reset ignored main owner debt" severity failure;
        s_main_idle <= '1';
        cycles;
        assert (s_ready = '1' and s_reset_drained = '1') report "Reset failed to retire all owners" severity failure;
        report "STATE_MACHINE_ACCESS_PASS: paired acquisition, debt drains, two cache barriers, exact alignment release, readiness, unsafe retry, cancellation, timeouts and reset";
        finish;
    end process;
end architecture;
