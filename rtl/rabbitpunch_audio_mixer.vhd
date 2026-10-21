-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MAME rpunch.cpp routes both YM channels and uPD7759 to mono at gain 0.50.
-- Inputs/outputs contain raw two's-complement bits. JT7759's own raw logger
-- expands its nine-bit sample by seven bits to the sixteen-bit PCM scale.
-- Sum before halving, round negative odd sums down, then saturate to 16 bits.
entity rabbitpunch_audio_mixer is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        iu16_left_pcm : in unsigned(15 downto 0);
        iu16_right_pcm : in unsigned(15 downto 0);
        iu9_adpcm_pcm : in unsigned(8 downto 0);
        ou16_mono_pcm : out unsigned(15 downto 0);
        i_state_hold : in std_logic := '0';
        i_state_load : in std_logic := '0';
        iu16_state : in unsigned(15 downto 0) := (others => '0');
        ou16_state : out unsigned(15 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_audio_mixer is
begin
    ou16_state <= ou16_mono_pcm;
    process(i_clk)
        variable vu18_left, vu18_right, vu18_sample, vu18_sum : unsigned(17 downto 0);
    begin
        if (rising_edge(i_clk)) then
            if (i_reset = '1') then
                ou16_mono_pcm <= (others => '0');
            elsif (i_state_hold = '1') then
                if (i_state_load = '1') then
                    ou16_mono_pcm <= iu16_state;
                end if;
            else
                assert (i_state_load = '0') report "Mixer state load requires hold" severity failure;
                vu18_left := (17 downto 16 => iu16_left_pcm(15)) & iu16_left_pcm;
                vu18_right := (17 downto 16 => iu16_right_pcm(15)) & iu16_right_pcm;
                vu18_sample := (17 downto 9 => iu9_adpcm_pcm(8)) & iu9_adpcm_pcm;
                vu18_sum := vu18_left + vu18_right + shift_left(vu18_sample, 7);
                vu18_sum := vu18_sum(17) & vu18_sum(17 downto 1);
                if (vu18_sum(17 downto 15) = "000" or vu18_sum(17 downto 15) = "111") then
                    ou16_mono_pcm <= vu18_sum(15 downto 0);
                elsif (vu18_sum(17) = '0') then
                    ou16_mono_pcm <= x"7FFF";
                else
                    ou16_mono_pcm <= x"8000";
                end if;
            end if;
        end if;
    end process;
end architecture;
