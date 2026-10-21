-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_board_tb is
end entity;

architecture test of state_board_tb is
    type t_words is array(natural range <>) of unsigned(15 downto 0);
    type t_bank is array(0 to 22) of unsigned(31 downto 0);
    type t_addresses is array(0 to 4) of natural;
    constant CINT_BASES : t_addresses := (16#40000#, 16#60000#, 16#80000#, 16#A0000#, 16#FC000#);
    constant CU16_PROGRAM : t_words := (
        x"203C", x"1111", x"1111", x"227C", x"000F", x"C000",
        x"46FC", x"2700", x"5280", x"22C0", x"60FA"
    );
    type t_trace is record
        su24_address : unsigned(23 downto 0);
        su16_data : unsigned(15 downto 0);
        su2_bytes : unsigned(1 downto 0);
    end record;
    type t_traces is array(0 to 399) of t_trace;
    type t_clocks is array(0 to 511) of unsigned(51 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize, s_reset : std_logic := '1';
    signal s_pause, s_capture, s_resume, s_release, s_hold, s_load : std_logic := '0';
    signal s_paused, s_held, s_error, s_return_held, s_idle, s_maintenance_idle : std_logic;
    signal s_rom_request, s_rom_response : std_logic := '0';
    signal su18_rom_address : unsigned(17 downto 0);
    signal su16_rom_data : unsigned(15 downto 0) := (others => '0');
    signal s_cpu_request, s_cpu_write, s_sound_write : std_logic;
    signal su24_cpu_address : unsigned(23 downto 0);
    signal su16_cpu_data : unsigned(15 downto 0);
    signal su2_cpu_bytes : unsigned(1 downto 0);
    signal su52_cpu_bus : unsigned(51 downto 0);
    signal s_bank_write : std_logic := '0';
    signal su5_bank_address : unsigned(4 downto 0) := (others => '0');
    signal su32_bank_write, su32_bank_read : unsigned(31 downto 0) := (others => '0');
    signal su224_io, su224_io_load : unsigned(223 downto 0) := (others => '0');
    signal su4_irq, su4_irq_load : unsigned(3 downto 0) := (others => '0');
    signal s_memory_access, s_memory_request, s_memory_write : std_logic := '0';
    signal s_memory_response : std_logic;
    signal su24_memory_address : unsigned(23 downto 0) := (others => '0');
    signal su16_memory_write, su16_memory_read : unsigned(15 downto 0) := (others => '0');
    signal su2_memory_bytes : unsigned(1 downto 0) := "11";
    signal s_record, s_compare : std_logic := '0';
    signal sint_writes, sint_recorded, sint_compared : natural := 0;
    function F_ROM(vint_address : natural) return unsigned is
    begin
        if (vint_address = 0) then
            return x"000F";
        elsif (vint_address = 2) then
            return x"F800";
        elsif (vint_address = 4) then
            return x"0000";
        elsif (vint_address = 6) then
            return x"0400";
        elsif (vint_address >= 16#400# and vint_address < 16#400# + CU16_PROGRAM'length * 2) then
            return CU16_PROGRAM((vint_address - 16#400#) / 2);
        end if;
        return x"4E71";
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    board : entity work.rabbitpunch_board
        generic map (
            GINT_PHASE_DIVIDER => 1,
            GBOOL_EXTERNAL_PHASE_ENABLE => true,
            GBOOL_STATE_CAPABLE => true
        )
        port map (
            i_clk => s_clk,
            i_main_phase_enable => '1',
            i_initialize => s_initialize,
            i_reset => s_reset,
            i_pause => s_pause,
            o_paused => s_paused,
            i_maintenance_initialize => '0',
            i_maintenance_access => '0',
            i_maintenance_valid => '0',
            i_maintenance_write => '0',
            iu14_maintenance_byte_address => (others => '0'),
            iu8_maintenance_data => (others => '0'),
            o_maintenance_ready => open,
            o_maintenance_response_valid => open,
            ou8_maintenance_response_data => open,
            o_maintenance_pause => open,
            i_maintenance_permitted => '0',
            o_transport_idle => s_idle,
            i_vblank_start => '0',
            i_half_frame => '0',
            i_line_valid => '0',
            o_line_ready => open,
            i_render_bank => '0',
            iu9_line_y => (others => '0'),
            o_line_done => open,
            o_sprite_rom_request => open,
            ou17_sprite_rom_word_address => open,
            i_sprite_rom_response_valid => '0',
            iu32_sprite_rom_response_data => (others => '0'),
            o_tile_rom_request => open,
            ou17_tile_rom_word_address => open,
            o_tile_rom_foreground => open,
            i_tile_rom_response_valid => '0',
            iu32_tile_rom_response_data => (others => '0'),
            i_pixel_valid => '0',
            o_pixel_ready => open,
            i_pixel_bank => '0',
            iu9_pixel_x => (others => '0'),
            iu8_pixel_y => (others => '0'),
            o_pixel_valid => open,
            o_pixel_error => open,
            ou9_pixel_x => open,
            ou8_pixel_y => open,
            ou8_red => open,
            ou8_green => open,
            ou8_blue => open,
            o_rom_request => s_rom_request,
            ou18_rom_byte_address => su18_rom_address,
            i_rom_response_valid => s_rom_response,
            iu16_rom_response_data => su16_rom_data,
            i_view_enable => '0',
            iu5_view_target => (others => '0'),
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => (others => '0'),
            i_sound_command_read => '0',
            o_sound_command_write => s_sound_write,
            ou8_sound_command => open,
            o_sound_pending => open,
            ou16_video_flags => open,
            ou9_scroll0_y => open,
            ou9_scroll0_x => open,
            ou9_scroll1_y => open,
            ou9_scroll1_x => open,
            ou6_sprite_count => open,
            ou6_sprite_priority => open,
            ou4_gga_selected => open,
            iu4_gga_view_address => (others => '0'),
            ou8_gga_view_data => open,
            o_gga_write => open,
            ou4_gga_write_address => open,
            ou8_gga_write_data => open,
            o_cpu_request => s_cpu_request,
            o_cpu_request_write => s_cpu_write,
            ou24_cpu_request_address => su24_cpu_address,
            ou16_cpu_request_data => su16_cpu_data,
            ou2_cpu_request_bytes => su2_cpu_bytes,
            i_state_capture => s_capture,
            i_state_cancel => '0',
            o_state_pending => open,
            o_state_held => s_held,
            o_state_error => s_error,
            i_state_resume => s_resume,
            o_state_return_held => s_return_held,
            i_state_release => s_release,
            o_state_resumed => open,
            o_state_canceled => open,
            iu5_state_cpu_address => su5_bank_address,
            i_state_cpu_write => s_bank_write,
            iu32_state_cpu_data => su32_bank_write,
            ou32_state_cpu_data => su32_bank_read,
            o_state_cpu_stopped => open,
            ou52_state_cpu_bus => su52_cpu_bus,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu224_state_io => su224_io_load,
            ou224_state_io => su224_io,
            iu4_state_irq => su4_irq_load,
            ou4_state_irq => su4_irq,
            i_state_memory_access => s_memory_access,
            i_state_memory_request => s_memory_request,
            i_state_memory_write => s_memory_write,
            iu24_state_memory_address => su24_memory_address,
            iu16_state_memory_data => su16_memory_write,
            iu2_state_memory_bytes => su2_memory_bytes,
            o_state_memory_response => s_memory_response,
            ou16_state_memory_data => su16_memory_read,
            o_state_memory_busy => open,
            o_maintenance_idle => s_maintenance_idle,
            i_state_video_flush => s_hold
        );
    rom_and_scoreboard : process(s_clk)
        variable vint_delay : natural := 0;
        variable v_pending : boolean := false;
        variable vu16_reply : unsigned(15 downto 0);
        variable vu_trace : t_traces;
    begin
        if (rising_edge(s_clk)) then
            s_rom_response <= '0';
            if (v_pending) then
                if (vint_delay = 0) then
                    s_rom_response <= '1';
                    su16_rom_data <= vu16_reply;
                    v_pending := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (s_rom_request = '1') then
                assert (not v_pending) report "Board overlapped program ROM debt" severity failure;
                v_pending := true;
                vint_delay := 17;
                vu16_reply := F_ROM(to_integer(su18_rom_address));
            end if;
            if (s_cpu_request = '1' and s_cpu_write = '1' and
                su24_cpu_address >= 16#FC000# and su24_cpu_address < 16#FF000#) then
                sint_writes <= sint_writes + 1;
                if (s_record = '1' and sint_recorded < 400) then
                    vu_trace(sint_recorded) := (su24_cpu_address, su16_cpu_data, su2_cpu_bytes);
                    sint_recorded <= sint_recorded + 1;
                end if;
                if (s_compare = '1' and sint_compared < 1200) then
                    assert (vu_trace(sint_compared mod 400) = t_trace'(su24_cpu_address, su16_cpu_data, su2_cpu_bytes))
                        report "Real board continuation write differs" severity failure;
                    sint_compared <= sint_compared + 1;
                end if;
            end if;
            if (s_hold = '1') then
                assert (s_sound_write = '0') report "Register restore emitted a sound command" severity failure;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu16_work : t_words(0 to 8191);
        variable vu32_bank : t_bank;
        variable vu52_clocks : t_clocks;
        variable vu224_io : unsigned(223 downto 0);
        variable vu4_irq : unsigned(3 downto 0);
        variable vu16_read : unsigned(15 downto 0);
        variable vint_before : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_index in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure memory(vint_address : natural; v_write : std_logic;
            vu16_data : unsigned(15 downto 0); variable vu16_read : out unsigned(15 downto 0)) is
        begin
            su24_memory_address <= to_unsigned(vint_address, 24);
            su16_memory_write <= vu16_data;
            s_memory_write <= v_write;
            s_memory_request <= '1';
            cycles;
            s_memory_request <= '0';
            for vint_wait in 0 to 100 loop
                exit when (s_memory_response = '1');
                cycles;
            end loop;
            assert (s_memory_response = '1') report "Board state RAM reply missing" severity failure;
            vu16_read := su16_memory_read;
            cycles;
        end procedure;
        procedure park is
        begin
            s_pause <= '1';
            s_capture <= '1';
            cycles;
            s_capture <= '0';
            for vint_wait in 0 to 10000 loop
                cycles;
                exit when (s_held = '1');
            end loop;
            assert (s_held = '1' and s_error = '0' and s_idle = '1' and s_maintenance_idle = '1')
                report "Board did not drain and hold" severity failure;
            s_hold <= '1';
            s_memory_access <= '1';
            cycles;
        end procedure;
        procedure resume is
        begin
            s_memory_access <= '0';
            cycles(3);
            s_resume <= '1';
            cycles;
            s_resume <= '0';
            for vint_wait in 0 to 10000 loop
                cycles;
                exit when (s_return_held = '1');
            end loop;
            assert (s_return_held = '1' and s_error = '0') report "Board private return failed" severity failure;
            s_hold <= '0';
            s_release <= '1';
            cycles;
            s_release <= '0';
            for vint_wait in 0 to 1000 loop
                exit when (s_paused = '1');
                cycles;
            end loop;
            cycles(20);
            assert (s_paused = '1') report "Board lost user pause" severity failure;
            s_pause <= '0';
            wait for 1 ns;
        end procedure;
    begin
        cycles(100);
        s_initialize <= '0';
        s_memory_access <= '1';
        cycles(2);
        memory(16#FF7FE#, '1', x"A55A", vu16_read);
        s_memory_access <= '0';
        cycles(3);
        s_reset <= '0';
        wait until sint_writes >= 100;
        park;
        -- Load a pending masked interrupt and nonzero registers without MMIO.
        su224_io_load <= (205 downto 0 => '1', others => '0');
        su4_irq_load <= "1111";
        s_load <= '1';
        cycles;
        s_load <= '0';
        cycles;
        vu224_io := su224_io;
        vu4_irq := su4_irq;
        assert (vu224_io = su224_io_load and vu4_irq = "1111") report "Board register load differs" severity failure;
        for vint_word in vu32_bank'range loop
            su5_bank_address <= to_unsigned(vint_word, 5);
            cycles;
            vu32_bank(vint_word) := su32_bank_read;
        end loop;
        for vint_word in vu16_work'range loop
            memory(16#FC000# + 2 * vint_word, '0', x"0000", vu16_work(vint_word));
        end loop;
        assert (vu16_work(16#1BFF#) = x"A55A") report "Board capture corrupted stack sentinel" severity failure;
        -- Exercise both byte lanes at every real RAM bank through the same owner.
        for vint_bank in CINT_BASES'range loop
            su2_memory_bytes <= "10";
            memory(CINT_BASES(vint_bank) + 16#100#, '1', x"A500", vu16_read);
            su2_memory_bytes <= "01";
            memory(CINT_BASES(vint_bank) + 16#100#, '1', x"005A", vu16_read);
            su2_memory_bytes <= "11";
            memory(CINT_BASES(vint_bank) + 16#100#, '0', x"0000", vu16_read);
            assert (vu16_read = x"A55A") report "Board bank byte lanes differ" severity failure;
        end loop;
        -- Restore the work-bank probe before establishing the saved continuation.
        memory(16#FC100#, '1', vu16_work(16#80#), vu16_read);
        s_record <= '1';
        resume;
        for vint_clock in vu52_clocks'range loop
            vu52_clocks(vint_clock) := su52_cpu_bus;
            cycles;
        end loop;
        wait until sint_recorded = 400;
        s_record <= '0';
        for vint_round in 1 to 3 loop
            vint_before := sint_writes;
            wait until sint_writes >= vint_before + 200;
            park;
            for vint_word in vu16_work'range loop
                memory(16#FC000# + 2 * vint_word, '1', vu16_work(vint_word), vu16_read);
            end loop;
            for vint_word in vu32_bank'range loop
                su5_bank_address <= to_unsigned(vint_word, 5);
                su32_bank_write <= vu32_bank(vint_word);
                s_bank_write <= '1';
                cycles;
                s_bank_write <= '0';
            end loop;
            su224_io_load <= vu224_io;
            su4_irq_load <= vu4_irq;
            s_load <= '1';
            cycles;
            s_load <= '0';
            cycles;
            assert (su224_io = vu224_io and su4_irq = vu4_irq) report "Board register restore differs" severity failure;
            s_compare <= '1';
            resume;
            for vint_clock in vu52_clocks'range loop
                assert (su52_cpu_bus = vu52_clocks(vint_clock))
                    report "Real board CPU clock continuation differs" severity failure;
                cycles;
            end loop;
            wait until sint_compared = 400 * vint_round;
            s_compare <= '0';
        end loop;
        report "STATE_BOARD_PASS: actual CPU, bus owner, five RAM banks, registers and pending IRQ; three exact continuations";
        finish;
    end process;
end architecture;
