-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity adpcm_samples_tb is
end entity;

architecture test of adpcm_samples_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_enable : std_logic := '0';
    signal su4_nibble : unsigned(3 downto 0) := (others => '0');
    signal su9_pcm : unsigned(8 downto 0);
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.adpcm_decoder_probe
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_decode_enable => s_enable,
            iu4_nibble => su4_nibble,
            ou9_pcm => su9_pcm
        );
    process
        file vectors : text open read_mode is "sample_nibbles.txt";
        variable v_line : line;
        variable vint_operation, vint_code, vint_expected : integer;
        variable vint_nibbles, vint_resets : natural := 0;
    begin
        while (not endfile(vectors)) loop
            readline(vectors, v_line);
            read(v_line, vint_operation);
            read(v_line, vint_code);
            read(v_line, vint_expected);
            wait until falling_edge(s_clk);
            if (vint_operation = 0) then
                s_reset <= '1';
                s_enable <= '0';
                vint_resets := vint_resets + 1;
            else
                assert (vint_operation = 1 and vint_code >= 0 and vint_code < 16 and
                    vint_expected >= -256 and vint_expected < 256)
                    report "Invalid real-sample reference vector" severity failure;
                s_reset <= '0';
                s_enable <= '1';
                su4_nibble <= to_unsigned(vint_code, 4);
                vint_nibbles := vint_nibbles + 1;
            end if;
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (su9_pcm = to_unsigned(vint_expected mod 512, 9))
                report "Real ROM ADPCM value mismatch at nibble " & integer'image(vint_nibbles)
                severity failure;
        end loop;
        assert (vint_nibbles = 237330) report "Real sample vector set incomplete" severity failure;
        report "ADPCM_SAMPLES_PASS samples=38 decoded_nibbles=" & integer'image(vint_nibbles) &
            " reset_events=" & integer'image(vint_resets);
        finish;
        wait;
    end process;
end architecture;
