-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity load_frontend_full_tb is
end entity;
architecture test of load_frontend_full_tb is
    signal s_clk : std_logic := '0';
    signal sint_cycles : natural := 0;
    signal su2_complete : unsigned(1 downto 0) := (others => '0');
begin
    s_clk <= not s_clk after 1 ns;
    modes : for vint_mode in 0 to 1 generate
        signal s_ready, s_active, s_valid : std_logic;
        signal su27_address : unsigned(26 downto 0);
        signal su16_data : unsigned(15 downto 0);
        signal sint_words : natural := 0;
    begin
        s_ready <= '1' when sint_cycles mod 11 >= 7 and sint_cycles mod 1000000 >= 97 else '0';
        source : entity work.diagnostic_load_source
            generic map (
                GBOOL_DDR_MODE => vint_mode = 1
            )
            port map (
                i_clk => s_clk,
                i_word_ready => s_ready,
                o_download_active => s_active,
                o_word_valid => s_valid,
                ou27_word_byte_address => su27_address,
                ou16_word_data => su16_data,
                o_complete => su2_complete(vint_mode)
            );
        sink : process(s_clk)
            variable vu16_expected : unsigned(15 downto 0);
        begin
            if (rising_edge(s_clk)) then
                if (s_valid = '1' and s_ready = '1') then
                    vu16_expected := to_unsigned(sint_words mod 65536, 16) xor
                        to_unsigned((sint_words / 65536) * 520, 16) xor x"A55A";
                    assert (su27_address = sint_words * 2 and su16_data = vu16_expected)
                        report "Independent full-size frontend sink mismatch" severity failure;
                    sint_words <= sint_words + 1;
                end if;
                if (su2_complete(vint_mode) = '1') then
                    assert (sint_words = CINT_ROM_IMAGE_SIZE / 2 and s_active = '0' and s_valid = '0')
                        report "Full-size frontend did not drain exactly once" severity failure;
                end if;
            end if;
        end process;
    end generate;
    monitor : process(s_clk)
        variable vint_quiet : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            sint_cycles <= sint_cycles + 1;
            if (su2_complete = "11") then
                if (vint_quiet = 40) then
                    report "LOAD_FRONTEND_FULL_PASS modes=byte,ddr bytes_each=2162688 words_each=1081344 ddr_reads=270336 ordered_pattern=checked backpressure=checked";
                    finish;
                else
                    vint_quiet := vint_quiet + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
