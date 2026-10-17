-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library altera_lnsim;
use altera_lnsim.altera_lnsim_components.all;

-- Dedicated vendor clock-generation boundary. The shifted output drives only
-- the external SDRAM clock pin; board processes use o_system_clk and enables.
entity rabbitpunch_pll is
    generic (
        SDRAM_PHASE_SHIFT : string := "10714 ps"
    );
    port (
        i_reference_clk : in std_logic;
        i_reset : in std_logic;
        o_system_clk : out std_logic;
        o_sdram_clk : out std_logic;
        o_locked : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_pll is
    subtype t_output_clocks is unsigned(1 downto 0);
    signal su2_output_clocks : unsigned(1 downto 0);
begin
    o_system_clk <= su2_output_clocks(0);
    o_sdram_clk <= su2_output_clocks(1);
    clock_generator : altera_pll
        generic map (
            reference_clock_frequency => "50.0 MHz",
            fractional_vco_multiplier => "false",
            pll_type => "General",
            pll_subtype => "General",
            operation_mode => "direct",
            number_of_clocks => 2,
            output_clock_frequency0 => "46.666667 MHz",
            phase_shift0 => "0 ps",
            duty_cycle0 => 50,
            output_clock_frequency1 => "46.666667 MHz",
            phase_shift1 => SDRAM_PHASE_SHIFT,
            duty_cycle1 => 50
        )
        port map (
            refclk => i_reference_clk,
            rst => i_reset,
            t_output_clocks(outclk) => su2_output_clocks,
            locked => o_locked,
            cascade_out => open,
            fboutclk => open,
            phase_done => open,
            activeclk => open,
            clkbad => open,
            phout => open,
            lvds_clk => open,
            loaden => open,
            extclk_out => open,
            reconfig_from_pll => open,
            zdbfbclk => open
        );
end architecture;
