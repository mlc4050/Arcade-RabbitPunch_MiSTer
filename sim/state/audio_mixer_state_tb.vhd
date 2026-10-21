-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity audio_mixer_state_tb is
end entity;

architecture test of audio_mixer_state_tb is
    type t_values is array (natural range <>) of integer;
    constant CINT_VALUES : t_values := (-32768, -32767, -16385, -16384, -2, -1, 0, 1, 2, 16383, 16384, 32766, 32767);
    signal s_hold, s_load : std_logic := '0';
    signal su16_state, su16_load : unsigned(15 downto 0) := (others => '0');
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
            ou16_mono_pcm => su16_mono,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu16_state => su16_load,
            ou16_state => su16_state
        );
    process
        variable vint_checks : natural := 0;
        variable vu16_image : unsigned(15 downto 0);
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
        for vint_left in CINT_VALUES'range loop
            for vint_right in CINT_VALUES'range loop
                for vint_sample in -256 to 255 loop
                    check(CINT_VALUES(vint_left), CINT_VALUES(vint_right), vint_sample);
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
        check(12345, -4321, -39);
        vu16_image := su16_state;
        assert (vu16_image /= 0 and vu16_image = su16_mono) severity failure;
        s_hold <= '1';
        for vint_round in 0 to 2 loop
            su16_left <= x"8000";
            su16_right <= x"7FFF";
            su9_sample <= to_unsigned(255, 9);
            for vint_cycle in 1 to 8 loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
                assert (su16_mono = vu16_image) report "Mixer advanced while held" severity failure;
            end loop;
            su16_load <= not vu16_image;
            s_load <= '1';
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (su16_mono = not vu16_image and su16_state = not vu16_image) severity failure;
            su16_load <= vu16_image;
            wait until rising_edge(s_clk);
            wait for 1 ns;
            s_load <= '0';
            assert (su16_mono = vu16_image) severity failure;
            su16_left <= to_unsigned(2000, 16);
            su16_right <= to_unsigned((-1000) mod 65536, 16);
            su9_sample <= to_unsigned(1, 9);
            s_hold <= '0';
            wait for 1 ns;
            assert (su16_mono = vu16_image) report "First resumed PCM sample differs" severity failure;
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (su16_mono = 564) report "Mixer resumed at wrong sample phase" severity failure;
            s_hold <= '1';
            su16_load <= vu16_image;
            s_load <= '1';
            wait until rising_edge(s_clk);
            wait for 1 ns;
            s_load <= '0';
        end loop;
        s_reset <= '1';
        s_load <= '1';
        su16_load <= x"FFFF";
        wait until rising_edge(s_clk);
        wait for 1 ns;
        assert (su16_mono = 0 and su16_state = 0) report "Reset did not override held mixer load" severity failure;
        s_reset <= '0';
        s_load <= '0';
        s_hold <= '0';
        check(-32768, 32767, 0);
        s_reset <= '1';
        wait until rising_edge(s_clk);
        wait for 1 ns;
        assert (su16_mono = 0) report "Mixer reset did not clear a live output" severity failure;
        report "AUDIO_MIXER_STATE_PASS checks=" & integer'image(vint_checks);
        finish;
        wait;
    end process;
end architecture;
