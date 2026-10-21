-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity state_memory_tb is
end entity;

architecture test of state_memory_tb is
    constant CINT_BYTES : positive := 106496;
    type t_image is array(0 to CINT_BYTES - 1) of unsigned(7 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize, s_session, s_drained, s_valid, s_write : std_logic := '0';
    signal s_pause, s_idle, s_ready, s_response, s_error : std_logic;
    signal su17_address : unsigned(16 downto 0) := (others => '0');
    signal su8_write, su8_read : unsigned(7 downto 0) := (others => '0');
    signal s_main_request, s_main_write, s_main_response, s_main_supported, s_rom_request : std_logic;
    signal su24_main_address : unsigned(23 downto 0);
    signal su16_main_write, su16_main_read : unsigned(15 downto 0);
    signal su2_main_bytes : unsigned(1 downto 0);
    signal s_sound_request, s_sound_write, s_sound_response, s_sound_rom, s_ym_write : std_logic;
    signal s_command_read, s_control_write, s_command_write : std_logic;
    signal su16_sound_address : unsigned(15 downto 0);
    signal su8_sound_write, su8_sound_read : unsigned(7 downto 0);
    function pattern(vint_address, vint_round : natural) return unsigned is
        variable vu17_address : unsigned(16 downto 0);
    begin
        vu17_address := to_unsigned(vint_address, 17);
        return vu17_address(7 downto 0) xor resize(vu17_address(16 downto 8), 8) xor to_unsigned(vint_round, 8);
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    access_port : entity work.rabbitpunch_state_memory
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_session => s_session,
            i_drained => s_drained,
            o_pause => s_pause,
            o_idle => s_idle,
            i_byte_valid => s_valid,
            o_byte_ready => s_ready,
            i_byte_write => s_write,
            iu17_byte_address => su17_address,
            iu8_byte_data => su8_write,
            o_byte_response => s_response,
            o_byte_error => s_error,
            ou8_byte_data => su8_read,
            o_main_request => s_main_request,
            o_main_write => s_main_write,
            ou24_main_address => su24_main_address,
            ou16_main_data => su16_main_write,
            ou2_main_bytes => su2_main_bytes,
            i_main_response => s_main_response,
            iu16_main_data => su16_main_read,
            o_sound_request => s_sound_request,
            o_sound_write => s_sound_write,
            ou16_sound_address => su16_sound_address,
            ou8_sound_data => su8_sound_write,
            i_sound_response => s_sound_response,
            iu8_sound_data => su8_sound_read
        );
    main_ram : entity work.rabbitpunch_memory
        port map (
            i_clk => s_clk,
            i_request => s_main_request,
            i_request_write => s_main_write,
            iu24_request_address => su24_main_address,
            iu16_request_data => su16_main_write,
            iu2_request_bytes => su2_main_bytes,
            o_request_supported => s_main_supported,
            o_response_valid => s_main_response,
            ou16_response_data => su16_main_read,
            o_rom_request => s_rom_request,
            ou18_rom_byte_address => open,
            i_rom_response_valid => '0',
            iu16_rom_response_data => x"DEAD",
            i_view_enable => '0',
            iu5_view_target => CU5_TARGET_NONE,
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open
        );
    sound_ram : entity work.rabbitpunch_sound_bus
        port map (
            i_clk => s_clk,
            i_request => s_sound_request,
            i_request_write => s_sound_write,
            iu16_request_address => su16_sound_address,
            iu8_request_data => su8_sound_write,
            o_response_valid => s_sound_response,
            ou8_response_data => su8_sound_read,
            o_rom_request => s_sound_rom,
            ou16_rom_address => open,
            i_rom_ready => '1',
            i_rom_response_valid => '0',
            iu8_rom_response_data => x"DE",
            i_ym_write_enable => '1',
            iu8_ym_status => x"00",
            o_ym_write => s_ym_write,
            o_ym_data_register => open,
            ou8_ym_write_data => open,
            iu8_command => x"00",
            o_command_read => s_command_read,
            o_adpcm_control_write => s_control_write,
            o_adpcm_command_write => s_command_write,
            ou8_adpcm_data => open,
            i_view_enable => '0',
            iu11_view_address => (others => '0'),
            ou8_view_data => open
        );
    safety : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            assert (s_rom_request /= '1' and s_sound_rom /= '1' and s_ym_write /= '1' and
                s_command_read /= '1' and s_control_write /= '1' and s_command_write /= '1')
                report "State RAM access escaped into ROM or I/O" severity failure;
            if (s_main_request = '1') then
                assert (s_main_supported = '1') report "State RAM mapping unsupported" severity failure;
            end if;
        end if;
    end process;
    stimulus : process
        variable vu8_snapshot : t_image;
        procedure cycle is
        begin
            wait until rising_edge(s_clk);
            wait until falling_edge(s_clk);
        end procedure;
        procedure access_byte(vint_address : natural; v_write : std_logic; vu8_data : unsigned(7 downto 0)) is
        begin
            su17_address <= to_unsigned(vint_address, 17);
            su8_write <= vu8_data;
            s_write <= v_write;
            s_valid <= '1';
            wait for 1 ns;
            assert (s_ready = '1') report "State RAM adapter not ready" severity failure;
            cycle;
            s_valid <= '0';
            -- Payload may change as soon as accepted. Outstanding debt owns copies.
            su17_address <= (others => '1');
            su8_write <= x"DE";
            for vint_wait in 0 to 31 loop
                exit when (s_response = '1');
                cycle;
            end loop;
            assert (s_response = '1') report "State RAM response timed out" severity failure;
            if (vint_address < CINT_BYTES) then
                assert (s_error = '0') report "Legal state RAM access rejected" severity failure;
            else
                assert (s_error = '1') report "Illegal state RAM access accepted" severity failure;
            end if;
        end procedure;
        procedure canceled_access(vint_address : natural; v_initialize : boolean) is
        begin
            s_valid <= '1';
            s_write <= '0';
            su17_address <= to_unsigned(vint_address, 17);
            cycle;
            s_valid <= '0';
            s_session <= '0';
            if (v_initialize) then
                s_initialize <= '1';
            end if;
            wait for 1 ns;
            assert (s_pause = '1' and s_idle = '0') report "Cancellation discarded backend debt" severity failure;
            for vint_wait in 0 to 31 loop
                cycle;
                assert (s_response = '0') report "Canceled response escaped to new session" severity failure;
                exit when (s_idle = '1');
                assert (s_pause = '1') report "Pause released before backend drained" severity failure;
            end loop;
            assert (s_idle = '1') report "Canceled state access never drained" severity failure;
            assert (s_pause = '0') report "Drained canceled session retained pause" severity failure;
            s_initialize <= '0';
            s_session <= '1';
            cycle;
        end procedure;
    begin
        cycle;
        cycle;
        s_session <= '1';
        cycle;
        assert (s_pause = '1' and s_ready = '0') report "State request ignored drain boundary" severity failure;
        s_drained <= '1';
        cycle;
        for vint_address in 0 to CINT_BYTES - 1 loop
            access_byte(vint_address, '1', pattern(vint_address, 16#A5#));
        end loop;
        for vint_address in 0 to CINT_BYTES - 1 loop
            access_byte(vint_address, '0', x"00");
            assert (su8_read = pattern(vint_address, 16#A5#))
                report "RAM capture differs at byte " & integer'image(vint_address) severity failure;
            vu8_snapshot(vint_address) := su8_read;
        end loop;
        for vint_address in 0 to CINT_BYTES - 1 loop
            access_byte(vint_address, '1', not vu8_snapshot(vint_address));
        end loop;
        for vint_address in 0 to CINT_BYTES - 1 loop
            access_byte(vint_address, '0', x"00");
            assert (su8_read = not vu8_snapshot(vint_address)) report "RAM perturbation missing" severity failure;
            access_byte(vint_address, '1', vu8_snapshot(vint_address));
        end loop;
        for vint_address in 0 to CINT_BYTES - 1 loop
            access_byte(vint_address, '0', x"00");
            assert (su8_read = vu8_snapshot(vint_address))
                report "RAM restore differs at byte " & integer'image(vint_address) severity failure;
        end loop;
        access_byte(CINT_BYTES, '1', x"EE");
        access_byte(131071, '0', x"00");
        canceled_access(0, false);
        canceled_access(65535, true);
        canceled_access(104448, false);
        canceled_access(106495, true);
        access_byte(0, '0', x"00");
        assert (su8_read = vu8_snapshot(0)) report "New session consumed stale reply" severity failure;
        s_session <= '0';
        cycle;
        assert (s_pause = '0') report "Final state session did not release" severity failure;
        report "STATE_MEMORY_PASS full_bytes=106496 capture_restore=exact canceled_main_sound_debt=drained invalid_addresses=rejected";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 100 ms;
        assert (false) report "State memory test timed out" severity failure;
        wait;
    end process;
end architecture;
