-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Provisional 46 2/3 MHz system clock. These are enables, never new clocks.
-- Pixel cadence is a steady /7; fractional enables preserve MAME chip rates.
entity rabbitpunch_clock_enables is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        o_pixel_enable : out std_logic;
        o_main_phase_enable : out std_logic;
        o_sound_cpu_enable : out std_logic;
        o_ym_enable : out std_logic;
        o_ym_half_enable : out std_logic;
        o_adpcm_enable : out std_logic;
        i_state_hold : in std_logic := '0';
        i_state_load : in std_logic := '0';
        iu32_state : in unsigned(31 downto 0) := (others => '0');
        ou32_state : out unsigned(31 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_clock_enables is
    signal sint_pixel_phase : natural range 0 to 6 := 0;
    signal sint_main_accumulator : natural range 0 to 34 := 0;
    signal sint_sound_accumulator : natural range 0 to 34 := 0;
    signal sint_adpcm_accumulator : natural range 0 to 874 := 0;
    signal s_sound_half_phase : std_logic := '0';
    signal s_sound_enable : std_logic;
begin
    ou32_state <= "000000" & s_sound_half_phase & to_unsigned(sint_adpcm_accumulator, 10) &
        to_unsigned(sint_sound_accumulator, 6) & to_unsigned(sint_main_accumulator, 6) &
        to_unsigned(sint_pixel_phase, 3);
    o_pixel_enable <= '1' when sint_pixel_phase = 6 and i_reset = '0' and i_state_hold = '0' else '0';
    o_main_phase_enable <= '1' when sint_main_accumulator >= 23 and i_reset = '0' and i_state_hold = '0' else '0';
    s_sound_enable <= '1' when sint_sound_accumulator >= 32 and i_reset = '0' and i_state_hold = '0' else '0';
    o_sound_cpu_enable <= s_sound_enable;
    o_ym_enable <= s_sound_enable;
    o_ym_half_enable <= s_sound_enable and s_sound_half_phase;
    o_adpcm_enable <= '1' when sint_adpcm_accumulator >= 863 and i_reset = '0' and i_state_hold = '0' else '0';

    cadence : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_reset = '1') then
                sint_pixel_phase <= 0;
                sint_main_accumulator <= 0;
                sint_sound_accumulator <= 0;
                sint_adpcm_accumulator <= 0;
                s_sound_half_phase <= '0';
            elsif (i_state_hold = '1') then
                if (i_state_load = '1') then
                    assert (iu32_state(2 downto 0) < 7 and iu32_state(8 downto 3) < 35 and
                        iu32_state(14 downto 9) < 35 and iu32_state(24 downto 15) < 875 and
                        iu32_state(31 downto 26) = 0)
                        report "Invalid clock-enable state" severity failure;
                    sint_pixel_phase <= to_integer(iu32_state(2 downto 0));
                    sint_main_accumulator <= to_integer(iu32_state(8 downto 3));
                    sint_sound_accumulator <= to_integer(iu32_state(14 downto 9));
                    sint_adpcm_accumulator <= to_integer(iu32_state(24 downto 15));
                    s_sound_half_phase <= iu32_state(25);
                end if;
            else
                if (sint_pixel_phase = 6) then
                    sint_pixel_phase <= 0;
                else
                    sint_pixel_phase <= sint_pixel_phase + 1;
                end if;
                if (sint_main_accumulator >= 23) then
                    sint_main_accumulator <= sint_main_accumulator + 12 - 35;
                else
                    sint_main_accumulator <= sint_main_accumulator + 12;
                end if;
                if (sint_sound_accumulator >= 32) then
                    sint_sound_accumulator <= sint_sound_accumulator + 3 - 35;
                    s_sound_half_phase <= not s_sound_half_phase;
                else
                    sint_sound_accumulator <= sint_sound_accumulator + 3;
                end if;
                if (sint_adpcm_accumulator >= 863) then
                    sint_adpcm_accumulator <= sint_adpcm_accumulator + 12 - 875;
                else
                    sint_adpcm_accumulator <= sint_adpcm_accumulator + 12;
                end if;
            end if;
        end if;
    end process;
end architecture;
