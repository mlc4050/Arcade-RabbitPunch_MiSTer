-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rabbitpunch_controls is
    generic (
        GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000"
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_reset : in std_logic;
        i_osd_open : in std_logic;
        i_pause_on_osd : in std_logic;
        i_debug_pause : in std_logic;
        i_state_pause : in std_logic;
        iu32_joystick0 : in unsigned(31 downto 0);
        iu32_joystick1 : in unsigned(31 downto 0);
        iu11_key_event : in unsigned(10 downto 0);
        i_file_write : in std_logic;
        iu16_file_index : in unsigned(15 downto 0);
        iu27_file_byte_address : in unsigned(26 downto 0);
        iu8_file_data : in unsigned(7 downto 0);
        ou8_player1 : out unsigned(7 downto 0);
        ou8_player2 : out unsigned(7 downto 0);
        ou8_service : out unsigned(7 downto 0);
        ou16_dips : out unsigned(15 downto 0);
        o_pause_request : out std_logic;
        o_user_paused : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_controls is
    signal s_pause_pressed : std_logic;
begin
    inputs : entity work.rabbitpunch_inputs
        generic map (GU16_DIP_DEFAULT => GU16_DIP_DEFAULT)
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            iu32_joystick0 => iu32_joystick0,
            iu32_joystick1 => iu32_joystick1,
            iu11_key_event => iu11_key_event,
            i_file_write => i_file_write,
            iu16_file_index => iu16_file_index,
            iu27_file_byte_address => iu27_file_byte_address,
            iu8_file_data => iu8_file_data,
            ou8_player1 => ou8_player1,
            ou8_player2 => ou8_player2,
            ou8_service => ou8_service,
            ou16_dips => ou16_dips,
            o_pause_pressed => s_pause_pressed
        );
    pause_control : entity work.rabbitpunch_pause
        port map (
            i_clk => i_clk,
            i_reset => i_initialize or i_game_reset,
            i_pause_pressed => s_pause_pressed,
            i_osd_open => i_osd_open,
            i_pause_on_osd => i_pause_on_osd,
            i_debug_pause => i_debug_pause,
            i_state_pause => i_state_pause,
            o_pause_request => o_pause_request,
            o_user_paused => o_user_paused
        );
end architecture;
