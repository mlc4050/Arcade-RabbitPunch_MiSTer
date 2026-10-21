-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity sound_state_owner_tb is
end entity;

architecture test of sound_state_owner_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_pause, s_capture, s_cancel, s_hold, s_resume : std_logic := '0';
    signal s_access, s_request, s_write : std_logic := '0';
    signal s_cpu_enable, s_paused, s_held, s_drained, s_response, s_cpu_request : std_logic;
    signal su16_address : unsigned(15 downto 0) := x"F823";
    signal su8_write, su8_read : unsigned(7 downto 0) := x"A5";
    signal su256_cpu : unsigned(255 downto 0);
    signal sint_cycle, sint_cpu_requests, sint_state_replies : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_cpu_enable <= '1' when sint_cycle mod 4 = 0 else '0';
    board : entity work.rabbitpunch_sound_board
        generic map (
            GBOOL_STATE_CAPABLE => true
        )
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_cpu_enable => s_cpu_enable,
            i_ym_enable => '0',
            i_ym_half_enable => '0',
            i_pause => s_pause,
            o_paused => s_paused,
            iu8_command => x"00",
            i_command_pending => '0',
            o_command_read => open,
            o_rom_request => open,
            ou16_rom_address => open,
            i_rom_ready => '1',
            i_rom_response_valid => '0',
            iu8_rom_response_data => x"00",
            o_adpcm_control_write => open,
            o_adpcm_command_write => open,
            ou8_adpcm_data => open,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            o_sample_marker => open,
            i_view_enable => '0',
            iu11_view_address => (others => '0'),
            ou8_view_data => open,
            o_debug_request => s_cpu_request,
            o_debug_write => open,
            ou16_debug_address => open,
            ou8_debug_data => open,
            i_capture_request => s_capture,
            i_capture_cancel => s_cancel,
            o_capture_pending => open,
            o_state_held => s_held,
            o_state_cpu_drained => s_drained,
            i_state_resume => s_resume,
            ou256_cpu_state => su256_cpu,
            i_state_hold => s_hold,
            i_state_memory_access => s_access,
            i_state_memory_request => s_request,
            i_state_memory_write => s_write,
            iu16_state_memory_address => su16_address,
            iu8_state_memory_data => su8_write,
            o_state_memory_response => s_response,
            ou8_state_memory_data => su8_read
        );
    count : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            sint_cycle <= sint_cycle + 1;
            if (s_cpu_request = '1') then
                sint_cpu_requests <= sint_cpu_requests + 1;
            end if;
            if (s_response = '1') then
                sint_state_replies <= sint_state_replies + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_cpu_before, vint_replies_before : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure park is
        begin
            s_pause <= '1';
            s_capture <= '1';
            cycles;
            s_capture <= '0';
            for vint_wait in 0 to 3999 loop
                exit when s_drained = '1';
                cycles;
                assert (vint_wait < 3999) report "Sound CPU never captured" severity failure;
            end loop;
            assert (s_held = '1' and su256_cpu(229) = '1' and not is_x(su256_cpu))
                report "Sound reset/capture missed initialized HALT fixture" severity failure;
            s_hold <= '1';
            cycles;
        end procedure;
        procedure memory_request(v_write : std_logic) is
        begin
            s_access <= '1';
            s_write <= v_write;
            cycles;
            s_request <= '1';
            cycles;
            s_request <= '0';
            -- Cancel the session mode after command acceptance. The response
            -- still belongs to state DMA, while CPU/chips remain captured.
            s_access <= '0';
        end procedure;
        procedure wait_reply is
        begin
            for vint_wait in 0 to 49 loop
                exit when s_response = '1';
                cycles;
                assert (sint_cpu_requests = vint_cpu_before)
                    report "CPU issued request before state response debt retired" severity failure;
                assert (vint_wait < 49) report "State reply lost when access mode canceled" severity failure;
            end loop;
            cycles(2);
        end procedure;
    begin
        cycles(20);
        s_reset <= '0';
        cycles(2000);
        park;
        vint_cpu_before := sint_cpu_requests;
        vint_replies_before := sint_state_replies;
        memory_request('1');
        wait_reply;
        assert (sint_state_replies = vint_replies_before + 1 and s_drained = '1') severity failure;
        memory_request('0');
        s_cancel <= '1';
        cycles;
        s_cancel <= '0';
        for vint_wait in 0 to 49 loop
            exit when s_response = '1';
            cycles;
            assert (s_held = '1' and sint_cpu_requests = vint_cpu_before) severity failure;
            assert (vint_wait < 49) severity failure;
        end loop;
        assert (su8_read = x"A5") report "State RAM readback differs" severity failure;
        cycles(2);
        assert (sint_state_replies = vint_replies_before + 2) severity failure;
        memory_request('0');
        s_reset <= '1';
        cycles;
        s_reset <= '0';
        s_hold <= '0';
        wait_reply;
        assert (sint_state_replies = vint_replies_before + 3)
            report "Gameplay reset discarded or retagged state response" severity failure;
        s_pause <= '0';
        cycles(2000);
        park;
        s_hold <= '0';
        s_resume <= '1';
        cycles;
        s_resume <= '0';
        vint_cpu_before := sint_cpu_requests;
        cycles(20);
        assert (s_held = '0' and s_paused = '1' and sint_cpu_requests = vint_cpu_before)
            report "Retired owner failed to preserve user pause" severity failure;
        report "SOUND_STATE_OWNER_PASS late read/write ownership after mode cancel,held cancel,reset debt,clean reboot,resume user pause" severity note;
        stop;
        wait;
    end process;
end architecture;
