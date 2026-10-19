-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rabbitpunch_m68k_state is
    generic (
        GU15_MONITOR_BASE : unsigned(23 downto 9) := to_unsigned(16#0F40#, 15)
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_phase2_enable : in std_logic;
        i_capture_request : in std_logic;
        o_cpu_parked : out std_logic;
        i_resume : in std_logic;
        iu23_cpu_word_address : in unsigned(23 downto 1);
        i_address_strobe_n : in std_logic;
        i_read : in std_logic;
        iu3_function_code : in unsigned(2 downto 0);
        iu16_cpu_write_data : in unsigned(15 downto 0);
        ou3_interrupt_level : out unsigned(2 downto 0);
        o_overlay_read : out std_logic;
        ou16_overlay_read_data : out unsigned(15 downto 0);
        iu2_state_word : in unsigned(1 downto 0);
        i_state_write : in std_logic;
        iu16_state_write_data : in unsigned(15 downto 0);
        ou16_state_read_data : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_m68k_state is
    component ss_m68k_park is
        generic (
            MON_BASE : unsigned(23 downto 9) := to_unsigned(16#0F40#, 15)
        );
        port (
            clk, reset, phi, park_req : in std_logic;
            parked : out std_logic;
            resume : in std_logic;
            eab : in unsigned(23 downto 1);
            ASn, eRWn, FC0, FC1, FC2 : in std_logic;
            oEdb : in unsigned(15 downto 0);
            ipl_park : out unsigned(2 downto 0);
            sel_mon : out std_logic;
            mon_data : out unsigned(15 downto 0);
            ss_sel : in unsigned(1 downto 0);
            ss_wr : in std_logic;
            ss_wdata : in unsigned(15 downto 0);
            ss_rdata : out unsigned(15 downto 0)
        );
    end component;
begin
    capture : ss_m68k_park
        generic map (
            MON_BASE => GU15_MONITOR_BASE
        )
        port map (
            clk => i_clk,
            reset => i_reset,
            phi => i_phase2_enable,
            park_req => i_capture_request,
            parked => o_cpu_parked,
            resume => i_resume,
            eab => iu23_cpu_word_address,
            ASn => i_address_strobe_n,
            eRWn => i_read,
            FC0 => iu3_function_code(0),
            FC1 => iu3_function_code(1),
            FC2 => iu3_function_code(2),
            oEdb => iu16_cpu_write_data,
            ipl_park => ou3_interrupt_level,
            sel_mon => o_overlay_read,
            mon_data => ou16_overlay_read_data,
            ss_sel => iu2_state_word,
            ss_wr => i_state_write,
            ss_wdata => iu16_state_write_data,
            ss_rdata => ou16_state_read_data
        );
end architecture;
