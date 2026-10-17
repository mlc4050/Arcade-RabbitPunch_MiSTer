-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity audio_mixer_tb is
end entity;

architecture test of audio_mixer_tb is
    type t_values is array (natural range <>) of integer;
    constant VALUES : t_values := (-32768, -32767, -16385, -16384, -2, -1, 0, 1, 2, 16383, 16384, 32766, 32767);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal su16_left, su16_right, su16_mono : unsigned(15 downto 0) := (others => '0');
    signal su9_sample : unsigned(8 downto 0) := (others => '0');
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_audio_mixer
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            iu16_left_pcm => su16_left,
            iu16_right_pcm => su16_right,
            iu9_adpcm_pcm => su9_sample,
            ou16_mono_pcm => su16_mono
        );
    process
        variable vint_checks : natural := 0;
        procedure check(vint_left, vint_right, vint_sample : integer) is
            variable vint_sum, vint_expected : integer;
        begin
            wait until falling_edge(s_clk);
            su16_left <= to_unsigned(vint_left mod 65536, 16);
            su16_right <= to_unsigned(vint_right mod 65536, 16);
            su9_sample <= to_unsigned(vint_sample mod 512, 9);
            vint_sum := vint_left + vint_right + vint_sample * 128;
            vint_expected := vint_sum / 2;
            if (vint_sum < 0 and vint_sum mod 2 = 1) then
                vint_expected := vint_expected - 1;
            end if;
            if (vint_expected > 32767) then
                vint_expected := 32767;
            elsif (vint_expected < -32768) then
                vint_expected := -32768;
            end if;
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (su16_mono = to_unsigned(vint_expected mod 65536, 16))
                report "Mono gain/sign/rounding/saturation mismatch" severity failure;
            vint_checks := vint_checks + 1;
        end procedure;
    begin
        wait until rising_edge(s_clk);
        wait for 1 ns;
        assert (su16_mono = 0) report "Mixer reset did not mute output" severity failure;
        s_reset <= '0';
        for vint_left in VALUES'range loop
            for vint_right in VALUES'range loop
                for vint_sample in -256 to 255 loop
                    check(VALUES(vint_left), VALUES(vint_right), vint_sample);
                end loop;
            end loop;
        end loop;
        for vint_value in -32768 to 32767 loop
            check(vint_value, 0, 0);
            check(0, vint_value, 0);
            if (vint_value /= -32768) then
                check(vint_value, -vint_value, 0);
            end if;
        end loop;
        s_reset <= '1';
        wait until rising_edge(s_clk);
        wait for 1 ns;
        assert (su16_mono = 0) report "Mixer reset did not clear a live output" severity failure;
        report "AUDIO_MIXER_PASS checks=" & integer'image(vint_checks);
        finish;
        wait;
    end process;
end architecture;
