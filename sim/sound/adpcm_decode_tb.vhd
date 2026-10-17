-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Simulation boundary for the unchanged native JT7759 nibble decoder.
entity adpcm_decoder_probe is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_decode_enable : in std_logic;
        iu4_nibble : in unsigned(3 downto 0);
        ou9_pcm : out unsigned(8 downto 0)
    );
end entity;

architecture boundary of adpcm_decoder_probe is
    component jt7759_adpcm is
        generic (SW : integer := 9);
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen_dec : in std_logic;
            encoded : in unsigned(3 downto 0);
            sound : out unsigned(8 downto 0)
        );
    end component;
begin
    decoder : jt7759_adpcm
        port map (
            rst => i_reset,
            clk => i_clk,
            cen_dec => i_decode_enable,
            encoded => iu4_nibble,
            sound => ou9_pcm
        );
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity adpcm_decode_tb is
end entity;

architecture test of adpcm_decode_tb is
    type t_steps is array (0 to 255) of integer;
    type t_states is array (0 to 15) of integer;
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
        file vectors : text open read_mode is "adpcm_steps.txt";
        variable v_line : line;
        variable vint_steps : t_steps;
        variable vint_states : t_states;
        variable vint_state, vint_sample, vint_checks, vint_lookup_cases : integer := 0;
        procedure reset_decoder is
        begin
            wait until falling_edge(s_clk);
            s_reset <= '1';
            s_enable <= '0';
            wait until falling_edge(s_clk);
            assert (su9_pcm = 0) report "Native decoder reset failed" severity failure;
            s_reset <= '0';
            vint_state := 0;
            vint_sample := 0;
        end procedure;
        procedure nibble(vint_code : natural; v_expect_saturation : boolean := false) is
            variable vint_sum : integer;
        begin
            wait until falling_edge(s_clk);
            su4_nibble <= to_unsigned(vint_code, 4);
            s_enable <= '1';
            vint_sum := vint_sample + vint_steps(vint_state * 16 + vint_code);
            if (not v_expect_saturation) then
                assert (vint_sum >= -256 and vint_sum <= 255)
                    report "MAME comparison accidentally entered the vendor-specific saturation range" severity failure;
            end if;
            vint_sample := vint_sum;
            if (vint_sample > 255) then
                vint_sample := 255;
            elsif (vint_sample < -256) then
                vint_sample := -256;
            end if;
            vint_state := vint_state + vint_states(vint_code);
            if (vint_state > 15) then
                vint_state := 15;
            elsif (vint_state < 0) then
                vint_state := 0;
            end if;
            wait until rising_edge(s_clk);
            wait for 1 ns;
            assert (su9_pcm = to_unsigned(vint_sample mod 512, 9))
                report "Native ADPCM decoded value differs from reference" severity failure;
            wait until falling_edge(s_clk);
            s_enable <= '0';
            su4_nibble <= to_unsigned((vint_code + 7) mod 16, 4);
            for vint_delay in 0 to 2 loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
                assert (su9_pcm = to_unsigned(vint_sample mod 512, 9))
                    report "Disabled nibble clock enable changed PCM" severity failure;
            end loop;
            vint_checks := vint_checks + 1;
        end procedure;
    begin
        for vint_index in vint_steps'range loop
            readline(vectors, v_line);
            read(v_line, vint_steps(vint_index));
        end loop;
        for vint_index in vint_states'range loop
            readline(vectors, v_line);
            read(v_line, vint_states(vint_index));
        end loop;
        for vint_target in 0 to 15 loop
            for vint_code in 0 to 15 loop
                reset_decoder;
                -- Alternating signs keep every lookup test inside the shared
                -- MAME/JT7759 range while code 4/C advances state exactly one.
                for vint_walk in 0 to vint_target - 1 loop
                    if (vint_walk mod 2 = 0) then
                        nibble(4);
                    else
                        nibble(12);
                    end if;
                end loop;
                assert (vint_state = vint_target) report "Reference state walk failed" severity failure;
                nibble(vint_code);
                vint_lookup_cases := vint_lookup_cases + 1;
            end loop;
        end loop;
        -- Native saturation is intentionally a separate contract: MAME's
        -- update_adpcm adds without a nine-bit clamp. Do not call it identical.
        reset_decoder;
        for vint_repeat in 0 to 15 loop
            nibble(7, true);
        end loop;
        assert (vint_sample = 255) report "Native positive saturation failed" severity failure;
        reset_decoder;
        for vint_repeat in 0 to 15 loop
            nibble(15, true);
        end loop;
        assert (vint_sample = -256) report "Native negative saturation failed" severity failure;
        reset_decoder;
        report "ADPCM_DECODE_PASS mame_lookup_cases=" & integer'image(vint_lookup_cases) &
            " checked_nibbles=" & integer'image(vint_checks) & " native_saturation=separate enable_hold=checked reset=checked";
        finish;
        wait;
    end process;
end architecture;
