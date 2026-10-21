-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity board_register_state_tb is
end entity;

architecture test of board_register_state_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_hold, s_load, s_request, s_command_read : std_logic := '0';
    signal s_response, s_command_write, s_gga_write, s_configure, s_twice : std_logic;
    signal s_vblank, s_half_frame, s_acknowledge, s_pending : std_logic := '0';
    signal su24_address : unsigned(23 downto 0) := (others => '0');
    signal su16_data : unsigned(15 downto 0) := (others => '0');
    signal su224_state, su224_restore : unsigned(223 downto 0) := (others => '0');
    signal su4_irq_state, su4_irq_restore : unsigned(3 downto 0) := (others => '0');
    signal su4_gga_view : unsigned(3 downto 0) := (others => '0');
    signal su8_gga_data : unsigned(7 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    registers : entity work.rabbitpunch_io
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_request => s_request,
            i_request_write => '1',
            iu24_request_address => su24_address,
            iu16_request_data => su16_data,
            iu2_request_bytes => "11",
            o_response_valid => s_response,
            ou16_response_data => open,
            iu8_player1 => x"FF",
            iu8_player2 => x"FF",
            iu8_service => x"FF",
            iu16_dips => x"FFFF",
            i_sound_command_read => s_command_read,
            o_sound_command_write => s_command_write,
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
            iu4_gga_view_address => su4_gga_view,
            ou8_gga_view_data => su8_gga_data,
            o_gga_write => s_gga_write,
            ou4_gga_write_address => open,
            ou8_gga_write_data => open,
            o_irq_configure => s_configure,
            o_irq_twice_per_frame => s_twice,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu224_state => su224_restore,
            ou224_state => su224_state
        );
    interrupts : entity work.rabbitpunch_irq
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_configure => s_configure,
            i_twice_per_frame => s_twice,
            i_vblank_start => s_vblank,
            i_half_frame => s_half_frame,
            i_acknowledge => s_acknowledge,
            o_level1_pending => s_pending,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu4_state => su4_irq_restore,
            ou4_state => su4_irq_state
        );
    stimulus : process
        variable vu224_saved : unsigned(223 downto 0);
        variable vu4_saved_irq : unsigned(3 downto 0);
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure bus_write(vint_address, vint_data : natural) is
        begin
            su24_address <= to_unsigned(vint_address, 24);
            su16_data <= to_unsigned(vint_data, 16);
            s_request <= '1';
            cycles;
            assert (s_response = '1') report "Missing register write reply" severity failure;
            s_request <= '0';
            cycles(2);
        end procedure;
        procedure check_quiet is
        begin
            assert (s_command_write = '0' and s_gga_write = '0' and s_configure = '0' and s_response = '0')
                report "State restore replayed a bus side effect" severity failure;
        end procedure;
    begin
        cycles(2);
        s_initialize <= '0';
        cycles;
        for vint_round in 0 to 7 loop
            s_acknowledge <= '1';
            cycles;
            s_acknowledge <= '0';
            -- Exercise real decoded writes, including each GGA byte and selection.
            bus_write(16#0C000C#, 16#A580# + vint_round);
            for vint_scroll in 0 to 3 loop
                bus_write(16#0C0000# + vint_scroll + vint_scroll, 16#101# + vint_scroll + vint_round);
            end loop;
            bus_write(16#0C0010#, 37 + vint_round);
            bus_write(16#0C0012#, 19 + vint_round);
            for vint_register in 0 to 15 loop
                bus_write(16#0C0028#, vint_register);
                bus_write(16#0C0008#, 16#81# + vint_register + vint_round);
            end loop;
            bus_write(16#0C0028#, 11);
            bus_write(16#0C0008#, 16#C0#);
            bus_write(16#0C0028#, 7);
            bus_write(16#0C000E#, 16#50# + vint_round);
            assert (su224_state(204) = '1') report "Command pending not captured" severity failure;
            assert (su224_state(195 downto 192) = 7) report "GGA selected index missing" severity failure;
            assert (su4_irq_state = "1010") report "IRQ first-event state missing" severity failure;
            if (vint_round mod 2 = 1) then
                s_vblank <= '1';
                cycles;
                s_vblank <= '0';
                cycles;
                assert (s_pending = '1') report "Vblank failed to pend IRQ" severity failure;
            end if;
            vu224_saved := su224_state;
            vu4_saved_irq := su4_irq_state;
            -- Perturb all fields by initialization and prove restoration is complete.
            s_initialize <= '1';
            cycles;
            s_initialize <= '0';
            cycles;
            assert (su224_state /= vu224_saved) report "Missing destructive perturbation" severity failure;
            s_hold <= '1';
            su224_restore <= vu224_saved;
            su4_irq_restore <= vu4_saved_irq;
            s_load <= '1';
            s_command_read <= '1';
            s_acknowledge <= '1';
            s_vblank <= '1';
            cycles;
            s_load <= '0';
            assert (su224_state = vu224_saved and su4_irq_state = vu4_saved_irq)
                report "Board state round trip differs" severity failure;
            check_quiet;
            cycles(20);
            assert (su224_state = vu224_saved and su4_irq_state = vu4_saved_irq)
                report "Held state advanced" severity failure;
            check_quiet;
            for vint_register in 0 to 15 loop
                su4_gga_view <= to_unsigned(vint_register, 4);
                cycles;
                if (vint_register = 11) then
                    assert (su8_gga_data = x"C0") report "GGA timer byte differs" severity failure;
                else
                    assert (su8_gga_data = 16#81# + vint_register + vint_round) report "GGA byte differs" severity failure;
                end if;
            end loop;
            s_command_read <= '0';
            s_acknowledge <= '0';
            s_vblank <= '0';
            s_hold <= '0';
            cycles;
            s_half_frame <= '1';
            cycles;
            s_half_frame <= '0';
            assert (s_pending = vu4_saved_irq(2)) report "Restored first-event gate differs" severity failure;
            s_vblank <= '1';
            cycles;
            s_vblank <= '0';
            s_acknowledge <= '1';
            cycles;
            s_acknowledge <= '0';
            s_half_frame <= '1';
            cycles;
            s_half_frame <= '0';
            assert (s_pending = '1') report "Restored twice-per-frame IRQ did not continue" severity failure;
            s_command_read <= '1';
            cycles;
            s_command_read <= '0';
            assert (su224_state(204) = '0') report "Restored command did not acknowledge" severity failure;
        end loop;
        report "BOARD_REGISTER_STATE_PASS repeated_roundtrips=8 gga=all irq_history=checked side_effects=none";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 100 us;
        assert (false) report "Board register state test timed out" severity failure;
        wait;
    end process;
end architecture;
