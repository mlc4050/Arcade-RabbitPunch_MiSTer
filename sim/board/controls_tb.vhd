-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity controls_tb is
end entity;

architecture test of controls_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_reset, s_osd_open, s_osd_pause, s_debug, s_state : std_logic := '0';
    signal su32_joy0, su32_joy1 : unsigned(31 downto 0) := (others => '0');
    signal su11_key : unsigned(10 downto 0) := (others => '0');
    signal s_write : std_logic := '0';
    signal su16_index : unsigned(15 downto 0) := to_unsigned(254, 16);
    signal su27_address : unsigned(26 downto 0) := (others => '0');
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal su8_player1, su8_player2, su8_service : unsigned(7 downto 0);
    signal su16_dips : unsigned(15 downto 0);
    signal s_pause, s_user : std_logic;
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_controls
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_reset => s_reset,
            i_osd_open => s_osd_open,
            i_pause_on_osd => s_osd_pause,
            i_debug_pause => s_debug,
            i_state_pause => s_state,
            iu32_joystick0 => su32_joy0,
            iu32_joystick1 => su32_joy1,
            iu11_key_event => su11_key,
            i_file_write => s_write,
            iu16_file_index => su16_index,
            iu27_file_byte_address => su27_address,
            iu8_file_data => su8_data,
            ou8_player1 => su8_player1,
            ou8_player2 => su8_player2,
            ou8_service => su8_service,
            ou16_dips => su16_dips,
            o_pause_request => s_pause,
            o_user_paused => s_user
        );
    process
        variable vu11_event : unsigned(10 downto 0);
        procedure tick(vint_count : positive := 1) is
        begin
            for vint_clock in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure key(vint_code : natural; v_pressed : std_logic) is
        begin
            vu11_event := su11_key;
            vu11_event(10) := not vu11_event(10);
            vu11_event(9) := v_pressed;
            vu11_event(8 downto 0) := to_unsigned(vint_code, 9);
            su11_key <= vu11_event;
            tick(3);
        end procedure;
    begin
        tick;
        s_initialize <= '0';
        su32_joy0(12) <= '1';
        tick(4);
        assert (s_pause = '1' and s_user = '1' and su8_service(2) = '0')
            report "Pad pause did not latch independently of original freeze pin" severity failure;
        su32_joy0(12) <= '0';
        tick(2);
        key(16#4D#, '1');
        assert (s_pause = '0' and s_user = '0') report "Keyboard pause did not resume pad pause" severity failure;
        su32_joy1(10) <= '1';
        tick(5);
        assert (s_user = '0' and su8_service = x"40")
            report "Held pause key toggled on unrelated controller input" severity failure;
        key(16#4D#, '0');
        su32_joy1 <= (others => '0');
        s_osd_open <= '1';
        s_osd_pause <= '1';
        tick;
        assert (s_pause = '1' and s_user = '0') report "Combined OSD pause failed" severity failure;
        s_osd_open <= '0';
        s_write <= '1';
        su8_data <= x"34";
        tick;
        su27_address <= to_unsigned(1, 27);
        su8_data <= x"12";
        tick;
        s_write <= '0';
        tick;
        assert (su16_dips = x"1234") report "Combined controls lost DIP lanes" severity failure;
        key(16#4D#, '1');
        assert (s_user = '1') report "Combined controls lost fresh pause press" severity failure;
        s_reset <= '1';
        tick(2);
        s_reset <= '0';
        tick(3);
        assert (s_user = '0' and su16_dips = x"1234")
            report "Game reset cleared downloaded DIPs or retriggered held pause" severity failure;
        s_state <= '1';
        tick;
        assert (s_pause = '1') report "State owner did not pause combined controls" severity failure;
        s_state <= '0';
        key(16#4D#, '0');
        assert (s_pause = '0') report "Combined pause owners did not release" severity failure;
        report "CONTROLS_PASS pad_keyboard_pause=checked osd_state_owners=checked gameplay_reset_preserves_dips=checked freeze_pin_unused=checked";
        finish;
        wait;
    end process;
end architecture;
