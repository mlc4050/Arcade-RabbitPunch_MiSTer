-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity rabbitpunch_z80_state is
    port (
        i_clk : in std_logic;
        i_clock_enable : in std_logic;
        i_reset_n : in std_logic;
        i_capture_request : in std_logic;
        o_cpu_parked : out std_logic;
        i_resume : in std_logic;
        iu16_cpu_address : in unsigned(15 downto 0);
        i_opcode_fetch_n : in std_logic;
        i_memory_request_n : in std_logic;
        i_io_request_n : in std_logic;
        i_read_n : in std_logic;
        i_write_n : in std_logic;
        i_wait_n : in std_logic;
        iu8_cpu_write_data : in unsigned(7 downto 0);
        iu8_bus_read_data : in unsigned(7 downto 0);
        o_nonmaskable_request : out std_logic;
        o_overlay_read : out std_logic;
        ou8_overlay_read_data : out unsigned(7 downto 0);
        i_state_word : in std_logic;
        i_state_write : in std_logic;
        iu16_state_write_data : in unsigned(15 downto 0);
        ou16_state_read_data : out unsigned(15 downto 0)
    );
end entity;
architecture rtl of rabbitpunch_z80_state is
    component ss_z80_park is
        port (
            clk, cen, reset_n, park_req : in std_logic;
            parked : out std_logic;
            resume : in std_logic;
            a : in unsigned(15 downto 0);
            m1_n, mreq_n, iorq_n, rd_n, wr_n, wait_n : in std_logic;
            dout, din_bus : in unsigned(7 downto 0);
            nmi_park, sel_mon : out std_logic;
            mon_data : out unsigned(7 downto 0);
            ss_sel, ss_wr : in std_logic;
            ss_wdata : in unsigned(15 downto 0);
            ss_rdata : out unsigned(15 downto 0)
        );
    end component;
begin
    capture : ss_z80_park
        port map (
            clk => i_clk,
            cen => i_clock_enable,
            reset_n => i_reset_n,
            park_req => i_capture_request,
            parked => o_cpu_parked,
            resume => i_resume,
            a => iu16_cpu_address,
            m1_n => i_opcode_fetch_n,
            mreq_n => i_memory_request_n,
            iorq_n => i_io_request_n,
            rd_n => i_read_n,
            wr_n => i_write_n,
            wait_n => i_wait_n,
            dout => iu8_cpu_write_data,
            din_bus => iu8_bus_read_data,
            nmi_park => o_nonmaskable_request,
            sel_mon => o_overlay_read,
            mon_data => ou8_overlay_read_data,
            ss_sel => i_state_word,
            ss_wr => i_state_write,
            ss_wdata => iu16_state_write_data,
            ss_rdata => ou16_state_read_data
        );
end architecture;
