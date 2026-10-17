-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The inherited MAME-default key decoder remains unchanged. The game's J1/MRA
-- pads six action slots before Start/Coin/Pause/Service/Test at bits 10..14.
-- F2 is the test switch (14); keyboard 9 is the separate service coin input.
entity rabbitpunch_keys is
    port (
        i_clk : in std_logic;
        iu11_key_event : in unsigned(10 downto 0);
        ou32_player1_actions : out unsigned(31 downto 0);
        ou32_player2_actions : out unsigned(31 downto 0);
        ou2_service_coins : out unsigned(1 downto 0)
    );
end entity;

architecture boundary of rabbitpunch_keys is
    component mame_keys is
        generic (
            BUTTONS : integer := 2;
            START : integer := 10;
            COIN : integer := 11;
            PAUSE : integer := 12;
            SERVICE : integer := 14
        );
        port (
            clk : in std_logic;
            ps2_key : in unsigned(10 downto 0);
            key0 : out unsigned(31 downto 0);
            key1 : out unsigned(31 downto 0);
            svc_coin : out unsigned(1 downto 0)
        );
    end component;
begin
    keyboard : mame_keys
        generic map (
            BUTTONS => 2,
            START => 10,
            COIN => 11,
            PAUSE => 12,
            SERVICE => 14
        )
        port map (
            clk => i_clk,
            ps2_key => iu11_key_event,
            key0 => ou32_player1_actions,
            key1 => ou32_player2_actions,
            svc_coin => ou2_service_coins
        );
end architecture;
