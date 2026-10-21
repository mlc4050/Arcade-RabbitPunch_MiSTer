-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Isolated complete 68000 capture adapter. The unchanged GX CPU and monitor
-- are selected only in its evaluation source profile. Normal memory requests
-- use the existing acknowledged board contract. Before-IACK stack writes are
-- journaled only in decoded writable RAM, never in MMIO. Both entry and the
-- private return end at an E-counter-zero stall. The parent must keep other
-- game state held, normalize ROM caches on BOTH save/restore, and explicitly
-- release the restored CPU together with the machine's saved enable phases.
entity rabbitpunch_state_maincpu is
    generic (
        GINT_PHASE_DIVIDER : positive := 3;
        GBOOL_EXTERNAL_PHASE_ENABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_phase_enable : in std_logic;
        i_reset : in std_logic;
        i_pause : in std_logic;
        i_interrupt_level1 : in std_logic;
        o_interrupt_acknowledge : out std_logic;
        o_request : out std_logic;
        o_request_write : out std_logic;
        ou24_request_address : out unsigned(23 downto 0);
        ou16_request_data : out unsigned(15 downto 0);
        ou2_request_bytes : out unsigned(1 downto 0);
        i_response_valid : in std_logic;
        iu16_response_data : in unsigned(15 downto 0);
        o_paused : out std_logic;
        i_capture_request : in std_logic;
        i_capture_cancel : in std_logic;
        o_capture_pending : out std_logic;
        o_capture_held : out std_logic;
        o_capture_error : out std_logic;
        i_state_resume : in std_logic;
        o_return_held : out std_logic;
        i_return_release : in std_logic;
        o_resume_completed : out std_logic;
        o_resume_canceled : out std_logic;
        iu5_state_address : in unsigned(4 downto 0);
        i_state_write : in std_logic;
        iu32_state_data : in unsigned(31 downto 0);
        ou32_state_data : out unsigned(31 downto 0);
        ou24_journal_address : out unsigned(23 downto 0);
        o_stopped : out std_logic;
        ou52_debug_bus : out unsigned(51 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_maincpu is
    type t_state is (STATE_IDLE, STATE_ACQUIRE, STATE_HELD, STATE_RETURN, STATE_RETURN_HELD, STATE_FAILED);
    signal styp_state : t_state := STATE_IDLE;
    signal s_phase1, s_phase2, s_e_clock, s_phase_held, s_phase_paused : std_logic;
    signal s_cpu_phase1, s_cpu_phase2 : std_logic;
    signal s_read, s_address_n, s_upper_n, s_lower_n, s_stopped : std_logic;
    signal su23_address : unsigned(23 downto 1);
    signal su24_address : unsigned(23 downto 0);
    signal su16_read, su16_write, su16_overlay : unsigned(15 downto 0);
    signal su3_fc, su3_interrupt_n : unsigned(2 downto 0);
    signal s_iack, s_iack7, s_previous_iack, s_access, s_take : std_logic := '0';
    signal s_ready, s_sent : std_logic := '0';
    signal s_capture_active, s_monitor_request, s_irq7, s_overlay, s_overlay_ready : std_logic;
    signal s_monitor_held, s_monitor_done, s_monitor_returned, s_return_stall : std_logic := '0';
    signal s_go, s_release, s_cancel_pending, s_expected_stop : std_logic := '0';
    signal s_ram_request, s_ram_ready, s_ram_response, s_ram_idle, s_ram_capture_write : std_logic;
    signal s_undo_done, s_undo_error, s_stack_clean : std_logic := '0';
    signal su16_ram_data : unsigned(15 downto 0);
    signal su24_journal : unsigned(23 downto 0);
    signal su5_bank_address : unsigned(4 downto 0);
    signal su32_bank_data : unsigned(31 downto 0);
    function F_WRITABLE_RAM(vu24_address : unsigned(23 downto 0)) return boolean is
        variable vu20_address : unsigned(19 downto 0);
    begin
        -- Same global20-bit mask and all five RAM ranges as board decode.
        vu20_address := vu24_address(19 downto 0);
        return (vu20_address >= x"40000" and vu20_address <= x"4FFFE") or
            (vu20_address >= x"60000" and vu20_address <= x"60FFE") or
            (vu20_address >= x"80000" and vu20_address <= x"83FFE") or
            (vu20_address >= x"A0000" and vu20_address <= x"A07FE") or
            vu20_address >= x"FC000";
    end function;
begin
    su24_address <= su23_address & '0';
    s_capture_active <= '0' when styp_state = STATE_IDLE else '1';
    s_monitor_request <= i_capture_request when styp_state = STATE_IDLE else '0';
    o_capture_pending <= '1' when styp_state = STATE_ACQUIRE else '0';
    o_capture_held <= '1' when styp_state = STATE_HELD else '0';
    o_return_held <= '1' when styp_state = STATE_RETURN_HELD else '0';
    o_capture_error <= '1' when styp_state = STATE_FAILED else '0';
    o_paused <= '1' when s_phase_paused = '1' or styp_state = STATE_FAILED else '0';
    o_stopped <= s_stopped;
    ou24_journal_address <= su24_journal;
    ou32_state_data <= su32_bank_data;
    -- Cancellation never releases a held or partially loaded machine. The
    -- monitor cannot withdraw a taken level7; finish parking, then let the
    -- parent explicitly choose a safe private return and machine release.
    s_go <= '1' when styp_state = STATE_HELD and i_state_resume = '1' else '0';
    s_release <= '1' when styp_state = STATE_RETURN_HELD and
        i_return_release = '1' else '0';
    su5_bank_address <= to_unsigned(18, 5) when styp_state = STATE_ACQUIRE else
        to_unsigned(22, 5) when s_go = '1' else iu5_state_address;
    su3_interrupt_n <= "000" when s_irq7 = '1' else "110" when
        i_interrupt_level1 = '1' and s_capture_active = '0' else "111";
    s_iack <= '1' when s_address_n = '0' and su3_fc = 7 else '0';
    s_iack7 <= s_iack and su23_address(3) and su23_address(2) and su23_address(1);
    s_access <= not s_address_n and not s_iack and not (s_upper_n and s_lower_n);
    -- A running return stalls before its first real bus access. STOP returns
    -- execute their private STOP instruction first, then settle with no bus.
    s_return_stall <= '1' when (styp_state = STATE_RETURN or styp_state = STATE_RETURN_HELD) and
        s_monitor_returned = '1' and ((s_expected_stop = '0' and s_access = '1' and s_overlay = '0') or
        (s_expected_stop = '1' and s_stopped = '1' and s_address_n = '1')) else '0';
    s_take <= s_access and not s_ready and ((s_overlay and s_overlay_ready) or
        (not s_overlay and s_ram_response));
    s_ram_request <= s_access and not s_overlay and not s_ready and not s_sent and s_ram_ready and
        not s_return_stall;
    s_ram_capture_write <= '1' when s_capture_active = '1' and s_read = '0' and
        F_WRITABLE_RAM(su24_address) else '0';
    s_cpu_phase1 <= s_phase1 when styp_state /= STATE_FAILED else '0';
    s_cpu_phase2 <= s_phase2 when styp_state /= STATE_FAILED else '0';
    clock_phase : entity work.rabbitpunch_capture_phase
        generic map (
            GINT_PHASE_DIVIDER => GINT_PHASE_DIVIDER,
            GBOOL_EXTERNAL_PHASE_ENABLE => GBOOL_EXTERNAL_PHASE_ENABLE
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_reset,
            i_phase_enable => i_phase_enable,
            i_user_pause => i_pause,
            i_bus_inactive => s_address_n,
            i_capture_active => s_capture_active or i_capture_request,
            i_monitor_held => s_monitor_held or s_return_stall,
            i_peripheral_clock => s_e_clock,
            i_resume => s_go or s_release,
            o_enable_phase1 => s_phase1,
            o_enable_phase2 => s_phase2,
            o_paused => s_phase_paused,
            o_capture_held => s_phase_held
        );
    cpu : entity work.rabbitpunch_state_fx68k
        port map (
            i_clk => i_clk,
            i_external_reset => i_reset,
            i_powerup_reset => i_reset,
            i_enable_phase1 => s_cpu_phase1,
            i_enable_phase2 => s_cpu_phase2,
            i_run => '1',
            o_read => s_read,
            o_address_strobe_n => s_address_n,
            o_upper_byte_strobe_n => s_upper_n,
            o_lower_byte_strobe_n => s_lower_n,
            ou23_word_address => su23_address,
            ou16_write_data => su16_write,
            iu16_read_data => su16_read,
            i_transfer_acknowledge_n => not s_ready,
            i_peripheral_transfer_n => not s_iack,
            i_bus_error_n => '1',
            i_bus_request_n => '1',
            i_bus_grant_acknowledge_n => '1',
            iu3_interrupt_level_n => su3_interrupt_n,
            ou3_function_code => su3_fc,
            o_peripheral_clock => s_e_clock,
            o_peripheral_address_valid_n => open,
            o_bus_grant_n => open,
            o_external_reset_out_n => open,
            o_halted_out_n => open,
            o_stopped => s_stopped
        );
    monitor : entity work.rabbitpunch_m68k_capture
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_bus_active => s_access,
            i_bus_complete => s_take,
            iu24_byte_address => su24_address,
            i_write => not s_read,
            iu3_function_code => su3_fc,
            iu16_write_data => su16_write,
            i_level7_acknowledge => s_iack7,
            i_stopped => s_stopped,
            i_capture_request => s_monitor_request,
            o_level7_request => s_irq7,
            o_overlay_selected => s_overlay,
            o_overlay_ready => s_overlay_ready,
            ou16_overlay_data => su16_overlay,
            o_held => s_monitor_held,
            i_resume => s_go,
            o_completed => s_monitor_done,
            iu5_state_address => su5_bank_address,
            i_state_write => i_state_write,
            iu32_state_data => iu32_state_data,
            ou32_state_data => su32_bank_data
        );
    stack_undo : entity work.rabbitpunch_capture_stack_undo
        port map (
            i_clk => i_clk,
            i_initialize => i_reset,
            i_request => s_ram_request,
            o_ready => s_ram_ready,
            i_write => not s_read,
            i_capture_ram_write => s_ram_capture_write,
            iu24_address => su24_address,
            iu16_write_data => su16_write,
            iu2_bytes => not (s_upper_n & s_lower_n),
            o_response => s_ram_response,
            ou16_read_data => su16_ram_data,
            i_level7_acknowledge => s_iack7,
            i_discard_journal => '0',
            o_journal_valid => open,
            ou24_journal_address => su24_journal,
            o_undo_completed => s_undo_done,
            o_undo_error => s_undo_error,
            o_idle => s_ram_idle,
            o_backend_request => o_request,
            o_backend_write => o_request_write,
            ou24_backend_address => ou24_request_address,
            ou16_backend_data => ou16_request_data,
            ou2_backend_bytes => ou2_request_bytes,
            i_backend_response => i_response_valid,
            iu16_backend_data => iu16_response_data
        );
    transaction : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_interrupt_acknowledge <= '0';
            if (i_reset = '1') then
                s_ready <= '0';
                s_sent <= '0';
                s_previous_iack <= '0';
                su16_read <= (others => '1');
            else
                s_previous_iack <= s_iack;
                if (s_iack = '1' and s_previous_iack = '0' and s_iack7 = '0') then
                    o_interrupt_acknowledge <= '1';
                end if;
                if (s_address_n = '1') then
                    s_ready <= '0';
                    s_sent <= '0';
                else
                    if (s_ram_request = '1') then
                        s_sent <= '1';
                    end if;
                    if (s_take = '1') then
                        s_ready <= '1';
                        if (s_overlay = '1') then
                            su16_read <= su16_overlay;
                        else
                            su16_read <= su16_ram_data;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    capture_session : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_resume_completed <= '0';
            o_resume_canceled <= '0';
            assert (i_state_write = '0' or styp_state = STATE_HELD)
                report "68000 register load requires validated canonical hold" severity failure;
            assert (i_state_write = '0' or s_go = '0')
                report "68000 bank write and private return cannot share an edge" severity failure;
            if (i_reset = '1') then
                styp_state <= STATE_IDLE;
                s_cancel_pending <= '0';
                s_stack_clean <= '0';
                s_monitor_returned <= '0';
                s_expected_stop <= '0';
            else
                if (i_capture_cancel = '1' and styp_state /= STATE_IDLE) then
                    s_cancel_pending <= '1';
                end if;
                if (s_undo_done = '1') then
                    s_stack_clean <= '1';
                end if;
                if (s_monitor_done = '1') then
                    s_monitor_returned <= '1';
                end if;
                case styp_state is
                    when STATE_IDLE =>
                        if (i_capture_request = '1') then
                            styp_state <= STATE_ACQUIRE;
                            s_stack_clean <= '0';
                            s_cancel_pending <= '0';
                            s_monitor_returned <= '0';
                        end if;
                    when STATE_ACQUIRE =>
                        if (s_phase_held = '1' and s_stack_clean = '1' and s_ram_idle = '1') then
                            if (su24_journal = su32_bank_data(23 downto 0) + 4) then
                                styp_state <= STATE_HELD;
                            else
                                styp_state <= STATE_FAILED;
                            end if;
                        end if;
                    when STATE_HELD =>
                        if (s_go = '1') then
                            s_expected_stop <= su32_bank_data(0);
                            s_monitor_returned <= '0';
                            styp_state <= STATE_RETURN;
                        end if;
                    when STATE_RETURN =>
                        if (s_return_stall = '1' and s_phase_held = '1') then
                            styp_state <= STATE_RETURN_HELD;
                        end if;
                    when STATE_RETURN_HELD =>
                        if (s_release = '1') then
                            o_resume_completed <= '1';
                            o_resume_canceled <= s_cancel_pending;
                            s_cancel_pending <= '0';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_FAILED =>
                        null;
                end case;
                if (s_undo_error = '1') then
                    styp_state <= STATE_FAILED;
                end if;
            end if;
        end if;
    end process;
    debug_bus : process(all)
        variable vu24_address : unsigned(23 downto 0);
        variable vu16_data : unsigned(15 downto 0);
        variable vu3_fc : unsigned(2 downto 0);
    begin
        vu24_address := (others => '0');
        vu16_data := (others => '0');
        vu3_fc := (others => '0');
        if (s_address_n = '0') then
            vu24_address := su24_address;
            vu3_fc := su3_fc;
            if (s_read = '1') then
                vu16_data := su16_read;
            else
                vu16_data := su16_write;
            end if;
        end if;
        ou52_debug_bus <= unsigned'(s_address_n & s_upper_n & s_lower_n & s_read & vu3_fc &
            s_e_clock & s_cpu_phase1 & s_cpu_phase2 & s_ready & s_stopped & vu24_address & vu16_data);
    end process;
end architecture;
