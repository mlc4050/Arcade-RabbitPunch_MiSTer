-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Evaluation boundary for the pinned state-enabled JT51 donor. Its persistent
-- vector is exposed honestly; omitted operator/accumulator state is not rebuilt
-- by this wrapper. This component is intentionally outside production files.qip.
entity rabbitpunch_fm_state is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_chip_enable : in std_logic;
        i_half_chip_enable : in std_logic;
        i_write : in std_logic;
        i_data_register : in std_logic;
        iu8_write_data : in unsigned(7 downto 0);
        ou8_status : out unsigned(7 downto 0);
        o_interrupt_n : out std_logic;
        o_sample : out std_logic;
        ou16_left_pcm : out unsigned(15 downto 0);
        ou16_right_pcm : out unsigned(15 downto 0);
        ou16_full_left_pcm : out unsigned(15 downto 0);
        ou16_full_right_pcm : out unsigned(15 downto 0);
        iu2820_state : in unsigned(2819 downto 0);
        ou2820_state : out unsigned(2819 downto 0);
        i_state_load : in std_logic
    );
end entity;

architecture rtl of rabbitpunch_fm_state is
    component jt51 is
        port (
            rst, clk, cen, cen_p1, cs_n, wr_n, a0 : in std_logic;
            din : in unsigned(7 downto 0);
            dout : out unsigned(7 downto 0);
            ct1, ct2, irq_n, sample : out std_logic;
            left, right, xleft, xright : out unsigned(15 downto 0);
            auto_ss_in : in unsigned(2819 downto 0);
            auto_ss_out : out unsigned(2819 downto 0);
            auto_ss_wr : in std_logic
        );
    end component;
begin
    chip : jt51
        port map (
            rst => i_reset,
            clk => i_clk,
            cen => i_chip_enable,
            cen_p1 => i_half_chip_enable,
            cs_n => '0',
            wr_n => not i_write,
            a0 => i_data_register,
            din => iu8_write_data,
            dout => ou8_status,
            ct1 => open,
            ct2 => open,
            irq_n => o_interrupt_n,
            sample => o_sample,
            left => ou16_left_pcm,
            right => ou16_right_pcm,
            xleft => ou16_full_left_pcm,
            xright => ou16_full_right_pcm,
            auto_ss_in => iu2820_state,
            auto_ss_out => ou2820_state,
            auto_ss_wr => i_state_load
        );
end architecture;
