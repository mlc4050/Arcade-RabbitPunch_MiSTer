-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity state_maincpu_compat_tb is
    generic (
        GBOOL_EXTERNAL_PHASE_ENABLE : boolean := true;
        GINT_INITIAL_RESET_CYCLES : positive := 100;
        GINT_WARM_RESET_CYCLES : positive := 100
    );
end entity;

architecture test of state_maincpu_compat_tb is
    type t_rom is array (0 to 511) of unsigned(15 downto 0);
    type t_ram is array (0 to 8191) of unsigned(15 downto 0);
    function program_image return t_rom is
        variable vu16_words : t_rom := (others => x"4E71");
        variable vint_pc : natural := 128;
        procedure emit(vu16_word : unsigned(15 downto 0)) is
        begin
            vu16_words(vint_pc) := vu16_word;
            vint_pc := vint_pc + 1;
        end procedure;
        procedure move_immediate(v_byte : boolean; vu16_value, vu16_address : unsigned(15 downto 0)) is
        begin
            if (v_byte) then
                emit(x"13FC");
            else
                emit(x"33FC");
            end if;
            emit(vu16_value);
            emit(x"000F");
            emit(vu16_address);
        end procedure;
        procedure copy_word(v_byte : boolean; vu16_source, vu16_destination : unsigned(15 downto 0)) is
        begin
            if (v_byte) then
                emit(x"1039");
            else
                emit(x"3039");
            end if;
            emit(x"000F");
            emit(vu16_source);
            if (v_byte) then
                emit(x"13C0");
            else
                emit(x"33C0");
            end if;
            emit(x"000F");
            emit(vu16_destination);
        end procedure;
    begin
        vu16_words(0) := x"000F";
        vu16_words(1) := x"FFFC";
        vu16_words(2) := x"0000";
        vu16_words(3) := x"0100";
        vu16_words(50) := x"0000";
        vu16_words(51) := x"0300";
        move_immediate(false, x"A55A", x"C000");
        move_immediate(true, x"0012", x"C000");
        move_immediate(true, x"0034", x"C001");
        copy_word(false, x"C000", x"C002");
        copy_word(true, x"C000", x"C004");
        copy_word(true, x"C001", x"C005");
        move_immediate(false, x"600D", x"C006");
        emit(x"46FC");
        emit(x"2000");
        emit(x"4E72");
        emit(x"2000");
        emit(x"60FA");
        vint_pc := 384;
        move_immediate(false, x"BEEF", x"C008");
        emit(x"4E73");
        return vu16_words;
    end function;
    constant CU16_PROGRAM : t_rom := program_image;
    signal s_clk : std_logic := '0';
    signal s_reset, s_enable_reset : std_logic := '1';
    signal s_pause, s_interrupt : std_logic := '0';
    signal s_phase_enable, s_acknowledge, s_request, s_write, s_paused : std_logic;
    signal s_response : std_logic := '0';
    signal su24_address : unsigned(23 downto 0);
    signal su16_write_data, su16_response_data : unsigned(15 downto 0);
    signal su2_bytes : unsigned(1 downto 0);
    signal su16_ram : t_ram := (others => (others => '0'));
    signal sint_accesses, sint_writes, sint_completions, sint_interrupts, sint_vector_reads : natural := 0;
    signal s_candidate_request, s_candidate_write, s_candidate_acknowledge, s_candidate_paused : std_logic;
    signal su24_candidate_address : unsigned(23 downto 0);
    signal su16_candidate_data : unsigned(15 downto 0);
    signal su2_candidate_bytes : unsigned(1 downto 0);
    signal sint_compared_clocks : natural := 0;
begin
    s_clk <= not s_clk after 10714 ps;
    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => s_clk,
            i_reset => s_enable_reset,
            o_pixel_enable => open,
            o_main_phase_enable => s_phase_enable,
            o_sound_cpu_enable => open,
            o_ym_enable => open,
            o_ym_half_enable => open,
            o_adpcm_enable => open
        );
    reference_cpu : entity work.rabbitpunch_maincpu_reference
        generic map (
            GBOOL_EXTERNAL_PHASE_ENABLE => GBOOL_EXTERNAL_PHASE_ENABLE
        )
        port map (
            i_clk => s_clk,
            i_phase_enable => s_phase_enable,
            i_reset => s_reset,
            i_pause => s_pause,
            i_interrupt_level1 => s_interrupt,
            o_interrupt_acknowledge => s_acknowledge,
            o_request => s_request,
            o_request_write => s_write,
            ou24_request_address => su24_address,
            ou16_request_data => su16_write_data,
            ou2_request_bytes => su2_bytes,
            i_response_valid => s_response,
            iu16_response_data => su16_response_data,
            o_paused => s_paused
        );
    candidate_cpu : entity work.rabbitpunch_state_maincpu
        generic map (
            GBOOL_EXTERNAL_PHASE_ENABLE => GBOOL_EXTERNAL_PHASE_ENABLE
        )
        port map (
            i_clk => s_clk,
            i_phase_enable => s_phase_enable,
            i_reset => s_reset,
            i_pause => s_pause,
            i_interrupt_level1 => s_interrupt,
            o_interrupt_acknowledge => s_candidate_acknowledge,
            o_request => s_candidate_request,
            o_request_write => s_candidate_write,
            ou24_request_address => su24_candidate_address,
            ou16_request_data => su16_candidate_data,
            ou2_request_bytes => su2_candidate_bytes,
            i_response_valid => s_response,
            iu16_response_data => su16_response_data,
            o_paused => s_candidate_paused,
            i_capture_request => '0',
            i_capture_cancel => '0',
            o_capture_pending => open,
            o_capture_held => open,
            o_capture_error => open,
            i_state_resume => '0',
            o_return_held => open,
            i_return_release => '0',
            o_resume_completed => open,
            o_resume_canceled => open,
            iu5_state_address => (others => '0'),
            i_state_write => '0',
            iu32_state_data => (others => '0'),
            ou32_state_data => open,
            ou24_journal_address => open,
            o_stopped => open,
            ou52_debug_bus => open
        );
    exact_clock_comparison : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_reset = '0') then
                assert (s_request = s_candidate_request)
                    report "Normal 68000 request clock differs at" & integer'image(sint_compared_clocks) severity failure;
                assert (s_acknowledge = s_candidate_acknowledge and s_paused = s_candidate_paused)
                    report "Normal 68000 IRQ/pause clock differs" severity failure;
                if (s_request = '1') then
                    assert (s_write = s_candidate_write and su24_address = su24_candidate_address and
                        su2_bytes = su2_candidate_bytes) report "Normal 68000 packet differs" severity failure;
                    if (s_write = '1') then
                        assert (su16_write_data = su16_candidate_data) report "Normal 68000 write data differs" severity failure;
                    end if;
                end if;
                sint_compared_clocks <= sint_compared_clocks + 1;
            end if;
        end if;
    end process;
    backend : process(s_clk)
        variable v_pending : boolean := false;
        variable v_writing : std_logic;
        variable vu24_address : unsigned(23 downto 0);
        variable vu16_data, vu16_word : unsigned(15 downto 0);
        variable vu2_bytes : unsigned(1 downto 0);
        variable vint_delay, vint_accesses, vint_word : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            s_response <= '0';
            if (s_request = '1') then
                assert (not v_pending) report "CPU issued overlapping requests" severity failure;
                vu24_address := su24_address;
                vu16_data := su16_write_data;
                vu2_bytes := su2_bytes;
                v_writing := s_write;
                case vint_accesses mod 3 is
                    when 0 =>
                        vint_delay := 0;
                    when 1 =>
                        vint_delay := 17;
                    when others =>
                        vint_delay := 65;
                end case;
                vint_accesses := vint_accesses + 1;
                sint_accesses <= vint_accesses;
                v_pending := true;
            elsif (v_pending) then
                if (vint_delay /= 0) then
                    vint_delay := vint_delay - 1;
                else
                    if (vu24_address < 1024 and v_writing = '0') then
                        su16_response_data <= CU16_PROGRAM(to_integer(vu24_address(9 downto 1)));
                        if (vu24_address < 8) then
                            sint_vector_reads <= sint_vector_reads + 1;
                        end if;
                    elsif (vu24_address >= 16#FC000# and vu24_address <= 16#FFFFE#) then
                        vint_word := (to_integer(vu24_address) - 16#FC000#) / 2;
                        vu16_word := su16_ram(vint_word);
                        if (v_writing = '1') then
                            if (vu2_bytes(1) = '1') then
                                vu16_word(15 downto 8) := vu16_data(15 downto 8);
                            end if;
                            if (vu2_bytes(0) = '1') then
                                vu16_word(7 downto 0) := vu16_data(7 downto 0);
                            end if;
                            su16_ram(vint_word) <= vu16_word;
                            sint_writes <= sint_writes + 1;
                            if (vu24_address = 16#FC006#) then
                                assert (su16_ram(0) = x"1234" and su16_ram(1) = x"1234" and
                                    su16_ram(2) = x"1234" and vu16_word = x"600D")
                                    report "CPU byte-lane/readback diagnostic failed" severity failure;
                                sint_completions <= sint_completions + 1;
                            elsif (vu24_address = 16#FC008#) then
                                assert (vu16_word = x"BEEF") report "CPU interrupt handler wrote wrong data" severity failure;
                                sint_interrupts <= sint_interrupts + 1;
                            end if;
                        end if;
                        su16_response_data <= vu16_word;
                    else
                        assert false report "Unexpected CPU access: " & to_hstring(vu24_address) severity failure;
                    end if;
                    v_pending := false;
                    s_response <= '1';
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_saved_accesses : natural;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
    begin
        cycles(5);
        s_enable_reset <= '0';
        cycles(GINT_INITIAL_RESET_CYCLES - 5);
        s_reset <= '0';
        wait until sint_writes = 2 for 1 ms;
        assert (sint_writes = 2) report "CPU did not reach pause point" severity failure;
        wait until falling_edge(s_clk);
        s_pause <= '1';
        wait until s_paused = '1' for 100 us;
        assert (s_paused = '1') report "CPU did not pause after draining" severity failure;
        cycles(100);
        vint_saved_accesses := sint_accesses;
        cycles(200);
        assert (s_paused = '1' and sint_accesses = vint_saved_accesses)
            report "CPU advanced during pause with enable source running" severity failure;
        s_pause <= '0';
        for vint_pass in 1 to 2 loop
            wait until sint_completions = vint_pass for 1 ms;
            assert (sint_completions = vint_pass) report "CPU diagnostic did not finish" severity failure;
            wait until falling_edge(s_clk);
            s_interrupt <= '1';
            wait until s_acknowledge = '1' for 100 us;
            assert (s_acknowledge = '1') report "CPU did not acknowledge level-one interrupt" severity failure;
            wait until falling_edge(s_clk);
            s_interrupt <= '0';
            wait until sint_interrupts = vint_pass for 100 us;
            assert (sint_interrupts = vint_pass) report "CPU interrupt handler did not execute" severity failure;
            cycles(300);
            if (vint_pass = 1) then
                s_reset <= '1';
                cycles(GINT_WARM_RESET_CYCLES);
                s_reset <= '0';
            end if;
        end loop;
        assert (sint_vector_reads = 8 and sint_writes = 22)
            report "CPU replay or interrupt stack traffic differs: writes=" & integer'image(sint_writes) &
                " reset_vectors=" & integer'image(sint_vector_reads) severity failure;
        report "STATE_MAINCPU_COMPAT_PASS exact-cycle original-control/GX vs state adapter: two byte/readback diagnostics, delayed memory, pause, reset and two autovectored handlers";
        std.env.finish;
        wait;
    end process;
    process
    begin
        wait for 3 ms;
        assert false report "CPU phase test timeout" severity failure;
    end process;
end architecture;
