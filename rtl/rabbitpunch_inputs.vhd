-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Pinned rpunch.cpp uses ACTIVE HIGH inputs. Do not invert the MiSTer pad bits.
-- The first two index-254 bytes form the raw DIP word, low byte first. The MRA
-- supplies per-set defaults (Japan 0000, US 2000); gameplay reset preserves them.
entity rabbitpunch_inputs is
    generic (
        DIP_DEFAULT : unsigned(15 downto 0) := x"0000"
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
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
        o_pause_pressed : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_inputs is
    signal su32_keys0, su32_keys1, su32_actions0, su32_actions1 : unsigned(31 downto 0);
    signal su2_service_coins : unsigned(1 downto 0);
    signal su16_dips : unsigned(15 downto 0) := DIP_DEFAULT;
    function player_port(vu32_actions : unsigned(31 downto 0)) return unsigned is
        variable vu8_result : unsigned(7 downto 0) := (others => '0');
    begin
        vu8_result(0) := vu32_actions(3);
        vu8_result(1) := vu32_actions(2);
        vu8_result(2) := vu32_actions(1);
        vu8_result(3) := vu32_actions(0);
        vu8_result(4) := vu32_actions(4);
        vu8_result(5) := vu32_actions(5);
        return vu8_result;
    end function;
begin
    keyboard : entity work.rabbitpunch_keys
        port map (
            i_clk => i_clk,
            iu11_key_event => iu11_key_event,
            ou32_player1_actions => su32_keys0,
            ou32_player2_actions => su32_keys1,
            ou2_service_coins => su2_service_coins
        );
    su32_actions0 <= iu32_joystick0 or su32_keys0;
    su32_actions1 <= iu32_joystick1 or su32_keys1;
    ou8_player1 <= player_port(su32_actions0);
    ou8_player2 <= player_port(su32_actions1);
    ou8_service <= (
        0 => su32_actions0(13) or su32_actions1(13) or su2_service_coins(0),
        1 => su32_actions0(14) or su32_actions1(14),
        3 => su32_actions1(11),
        4 => su32_actions0(11),
        5 => su32_actions0(10),
        6 => su32_actions1(10),
        others => '0'
    );
    o_pause_pressed <= su32_actions0(12) or su32_actions1(12);
    ou16_dips <= su16_dips;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                su16_dips <= DIP_DEFAULT;
            elsif (i_file_write = '1') then
                if (iu16_file_index = 254) then
                    if (iu27_file_byte_address = 0) then
                        su16_dips(7 downto 0) <= iu8_file_data;
                    elsif (iu27_file_byte_address = 1) then
                        su16_dips(15 downto 8) <= iu8_file_data;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
