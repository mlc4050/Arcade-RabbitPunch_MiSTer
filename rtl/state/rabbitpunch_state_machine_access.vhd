-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Coherent access barrier around the existing captured CPUs and held banks.
-- Physical scanout/SDRAM clocks never pass through this block. The caller
-- supplies real idle/credit indications, not fixed settling delays. An unsafe
-- partial apply remains held for a complete retry or a drained gameplay reset.
entity rabbitpunch_state_machine_access is
    generic (
        GINT_TIMEOUT_CYCLES : positive := 48000000
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_acquire : in std_logic;
        i_cancel : in std_logic;
        i_release : in std_logic;
        i_incomplete : in std_logic;
        i_nvram_quiesced : in std_logic;
        i_nvram_ready : in std_logic;
        i_legacy_idle : in std_logic;
        i_main_bus_idle : in std_logic;
        i_sound_bus_idle : in std_logic;
        i_main_held : in std_logic;
        i_main_error : in std_logic;
        i_sound_held : in std_logic;
        i_sound_drained : in std_logic;
        i_transport_idle : in std_logic;
        i_banks_idle : in std_logic;
        i_main_return_held : in std_logic;
        i_main_resumed : in std_logic;
        i_main_resume_canceled : in std_logic;
        i_aligned : in std_logic;
        i_scores_ready_load : in std_logic;
        i_scores_ready_data : in std_logic;
        o_scores_ready : out std_logic;
        o_ready : out std_logic;
        o_busy : out std_logic;
        o_held : out std_logic;
        o_finished : out std_logic := '0';
        o_canceled : out std_logic;
        ou4_error : out unsigned(3 downto 0);
        o_reset_drained : out std_logic := '0';
        o_pause : out std_logic;
        o_nvram_quiesce : out std_logic;
        o_legacy_quiesce : out std_logic;
        o_nvram_reconcile : out std_logic;
        o_main_capture : out std_logic;
        o_sound_capture : out std_logic;
        o_capture_cancel : out std_logic;
        o_game_hold : out std_logic;
        o_video_flush : out std_logic;
        o_rom_flush : out std_logic;
        o_bank_session : out std_logic;
        o_main_resume : out std_logic;
        o_private_return : out std_logic;
        o_main_release : out std_logic;
        o_sound_resume : out std_logic;
        o_sdram_prepare : out std_logic := '0'
    );
end entity;

architecture rtl of rabbitpunch_state_machine_access is
    type t_state is (STATE_RESET_DRAIN, STATE_IDLE, STATE_NVRAM,
        STATE_CAPTURE, STATE_ACQUIRE, STATE_TRANSPORT, STATE_ENTRY_FLUSH,
        STATE_HELD, STATE_BANK_DRAIN, STATE_RETURN, STATE_RETURN_WAIT,
        STATE_RETURN_DRAIN, STATE_EXIT_FLUSH, STATE_ALIGN,
        STATE_RECONCILE, STATE_RESUMED, STATE_UNSAFE, STATE_FAILED);
    signal styp_state : t_state := STATE_RESET_DRAIN;
    signal s_hold, s_canceled, s_scores_ready : std_logic := '0';
    signal su4_error : unsigned(3 downto 0) := (others => '0');
    signal sint_age : natural range 0 to GINT_TIMEOUT_CYCLES := 0;
    signal s_timed, s_release_edge : std_logic;
    signal s_release_drained : std_logic := '0';
begin
    o_ready <= '1' when styp_state = STATE_IDLE and i_reset = '0' else '0';
    o_busy <= not o_ready;
    o_held <= '1' when (styp_state = STATE_HELD or styp_state = STATE_BANK_DRAIN or
        styp_state = STATE_UNSAFE) and i_reset = '0' else '0';
    o_canceled <= s_canceled;
    ou4_error <= su4_error;
    o_scores_ready <= s_scores_ready;
    s_release_edge <= '1' when styp_state = STATE_ALIGN and i_aligned = '1' and
        sint_age < GINT_TIMEOUT_CYCLES and i_incomplete = '0' and i_main_error = '0' and
        s_release_drained = '1' and i_reset = '0' else '0';
    o_pause <= '0' when styp_state = STATE_IDLE or s_release_edge = '1' or
        styp_state = STATE_RESUMED else '1';
    o_nvram_quiesce <= '0' when styp_state = STATE_IDLE else '1';
    o_legacy_quiesce <= o_nvram_quiesce;
    o_nvram_reconcile <= '1' when styp_state = STATE_RECONCILE else '0';
    o_main_capture <= '1' when styp_state = STATE_CAPTURE else '0';
    o_sound_capture <= o_main_capture;
    o_capture_cancel <= i_reset or s_canceled;
    o_game_hold <= s_hold and not s_release_edge when i_reset = '0' else '0';
    o_video_flush <= '0' when styp_state = STATE_IDLE or s_release_edge = '1' or
        styp_state = STATE_RESUMED else '1';
    o_rom_flush <= '1' when styp_state = STATE_ENTRY_FLUSH or
        styp_state = STATE_EXIT_FLUSH else '0';
    -- Retain an accepted bank credit through cancellation/reset. The bank
    -- parent independently keeps its lower RAM session until its reply retires.
    o_bank_session <= '1' when o_held = '1' or i_banks_idle = '0' else '0';
    o_main_resume <= '1' when styp_state = STATE_RETURN else '0';
    o_private_return <= '1' when (styp_state = STATE_RETURN or
        styp_state = STATE_RETURN_WAIT or styp_state = STATE_RETURN_DRAIN or
        styp_state = STATE_EXIT_FLUSH or styp_state = STATE_ALIGN or
        styp_state = STATE_RECONCILE) and s_release_edge = '0' else '0';
    o_main_release <= s_release_edge;
    o_sound_resume <= o_main_release;
    o_sdram_prepare <= '1' when styp_state = STATE_ALIGN else '0';
    s_timed <= '0' when styp_state = STATE_IDLE or styp_state = STATE_HELD or
        styp_state = STATE_UNSAFE or styp_state = STATE_FAILED or
        styp_state = STATE_RESET_DRAIN else '1';
    control : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_reset_drained <= '0';
            -- Producers are held or leased until GO. Record that epoch's
            -- empty ownership before GO can unhold an autonomous ROM reader;
            -- its next request must not feed back into this release decision.
            s_release_drained <= i_banks_idle and i_main_bus_idle and
                i_sound_bus_idle and i_transport_idle and i_legacy_idle;
            assert (i_reset = '1' or i_scores_ready_load = '0' or o_held = '1')
                report "Score readiness load requires held machine banks" severity failure;
            if (i_reset = '1') then
                s_release_drained <= '0';
                styp_state <= STATE_RESET_DRAIN;
                s_hold <= '0';
                s_canceled <= '0';
                s_scores_ready <= '0';
                su4_error <= (others => '0');
                sint_age <= 0;
            else
                if (i_cancel = '1' and styp_state /= STATE_IDLE) then
                    s_canceled <= '1';
                end if;
                if (i_scores_ready_load = '1' and o_held = '1') then
                    s_scores_ready <= i_scores_ready_data;
                end if;
                if (s_timed = '0') then
                    sint_age <= 0;
                elsif (sint_age < GINT_TIMEOUT_CYCLES) then
                    sint_age <= sint_age + 1;
                end if;
                case styp_state is
                    when STATE_RESET_DRAIN =>
                        if (i_banks_idle = '1' and i_transport_idle = '1' and
                            i_main_bus_idle = '1' and i_sound_bus_idle = '1' and
                            i_legacy_idle = '1' and i_nvram_quiesced = '1') then
                            styp_state <= STATE_IDLE;
                            o_reset_drained <= '1';
                        end if;
                    when STATE_IDLE =>
                        if (i_acquire = '1') then
                            styp_state <= STATE_NVRAM;
                            s_canceled <= '0';
                            su4_error <= (others => '0');
                            sint_age <= 0;
                        end if;
                    when STATE_NVRAM =>
                        if (i_cancel = '1' or s_canceled = '1') then
                            styp_state <= STATE_IDLE;
                            o_finished <= '1';
                        elsif (i_nvram_quiesced = '1' and i_legacy_idle = '1' and
                            i_main_bus_idle = '1' and i_sound_bus_idle = '1') then
                            s_scores_ready <= i_nvram_ready;
                            styp_state <= STATE_CAPTURE;
                            sint_age <= 0;
                        end if;
                    when STATE_CAPTURE =>
                        styp_state <= STATE_ACQUIRE;
                    when STATE_ACQUIRE =>
                        if (i_main_error = '1') then
                            styp_state <= STATE_FAILED;
                            su4_error <= to_unsigned(1, 4);
                            o_finished <= '1';
                        elsif (i_main_held = '1' and i_sound_held = '1' and
                            i_sound_drained = '1' and i_main_bus_idle = '1') then
                            s_hold <= '1';
                            styp_state <= STATE_TRANSPORT;
                            sint_age <= 0;
                        end if;
                    when STATE_TRANSPORT =>
                        if (i_transport_idle = '1' and i_banks_idle = '1') then
                            styp_state <= STATE_ENTRY_FLUSH;
                            sint_age <= 0;
                        end if;
                    when STATE_ENTRY_FLUSH =>
                        assert (i_transport_idle = '1') report "Entry cache flush lost drained transport" severity failure;
                        styp_state <= STATE_HELD;
                    when STATE_HELD =>
                        if (i_release = '1' or i_cancel = '1' or s_canceled = '1') then
                            styp_state <= STATE_BANK_DRAIN;
                            sint_age <= 0;
                        end if;
                    when STATE_BANK_DRAIN =>
                        if (i_banks_idle = '1' and i_main_bus_idle = '1' and i_sound_bus_idle = '1') then
                            if (i_incomplete = '1') then
                                styp_state <= STATE_UNSAFE;
                                su4_error <= to_unsigned(6, 4);
                                o_finished <= '1';
                            else
                                styp_state <= STATE_RETURN;
                                sint_age <= 0;
                            end if;
                        end if;
                    when STATE_RETURN =>
                        assert (i_banks_idle = '1') report "Private return started with bank debt" severity failure;
                        styp_state <= STATE_RETURN_WAIT;
                    when STATE_RETURN_WAIT =>
                        if (i_main_error = '1') then
                            styp_state <= STATE_FAILED;
                            su4_error <= to_unsigned(1, 4);
                            o_finished <= '1';
                        elsif (i_main_return_held = '1') then
                            styp_state <= STATE_RETURN_DRAIN;
                            sint_age <= 0;
                        end if;
                    when STATE_RETURN_DRAIN =>
                        if (i_transport_idle = '1' and i_main_bus_idle = '1' and i_sound_bus_idle = '1') then
                            styp_state <= STATE_EXIT_FLUSH;
                            sint_age <= 0;
                        end if;
                    when STATE_EXIT_FLUSH =>
                        assert (i_transport_idle = '1') report "Return cache flush lost drained transport" severity failure;
                        styp_state <= STATE_RECONCILE;
                        sint_age <= 0;
                    when STATE_ALIGN =>
                        if (s_release_edge = '1') then
                            styp_state <= STATE_RESUMED;
                            s_hold <= '0';
                            sint_age <= 0;
                        end if;
                    when STATE_RECONCILE =>
                        -- Reconcile while held, then release combinationally
                        -- on the exact matching edge, not a clock after it.
                        styp_state <= STATE_ALIGN;
                        sint_age <= 0;
                    when STATE_RESUMED =>
                        if (i_main_resumed = '1' or i_main_resume_canceled = '1') then
                            styp_state <= STATE_IDLE;
                            o_finished <= '1';
                        end if;
                    when STATE_UNSAFE =>
                        if (i_release = '1' and i_incomplete = '0' and i_banks_idle = '1') then
                            su4_error <= (others => '0');
                            s_canceled <= '0';
                            styp_state <= STATE_BANK_DRAIN;
                            sint_age <= 0;
                        end if;
                    when STATE_FAILED =>
                        null;
                end case;
                if (i_main_error = '1' and styp_state /= STATE_IDLE and
                    styp_state /= STATE_RESET_DRAIN and styp_state /= STATE_NVRAM and
                    styp_state /= STATE_FAILED) then
                    styp_state <= STATE_FAILED;
                    su4_error <= to_unsigned(1, 4);
                    o_finished <= '1';
                elsif (i_incomplete = '1' and (styp_state = STATE_RETURN or
                    styp_state = STATE_RETURN_WAIT or styp_state = STATE_RETURN_DRAIN or
                    styp_state = STATE_EXIT_FLUSH or styp_state = STATE_RECONCILE or styp_state = STATE_ALIGN)) then
                    styp_state <= STATE_FAILED;
                    su4_error <= to_unsigned(6, 4);
                    o_finished <= '1';
                elsif (s_timed = '1' and sint_age = GINT_TIMEOUT_CYCLES) then
                    if (styp_state = STATE_NVRAM) then
                        styp_state <= STATE_IDLE;
                    else
                        styp_state <= STATE_FAILED;
                    end if;
                    su4_error <= to_unsigned(2, 4);
                    o_finished <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
