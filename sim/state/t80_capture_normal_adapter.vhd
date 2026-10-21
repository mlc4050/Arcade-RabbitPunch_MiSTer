-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Substitute for rtl/rabbitpunch_t80.vhd in isolated normal-mode sound tests.
-- This keeps the production board interface while selecting the state donor.
entity rabbitpunch_t80 is
    port (
        i_clk : in std_logic;
        i_reset_n : in std_logic;
        i_clock_enable : in std_logic;
        i_wait_n : in std_logic;
        i_interrupt_n : in std_logic;
        i_nonmaskable_interrupt_n : in std_logic;
        i_bus_request_n : in std_logic;
        o_opcode_fetch_n : out std_logic;
        o_memory_request_n : out std_logic;
        o_io_request_n : out std_logic;
        o_read_n : out std_logic;
        o_write_n : out std_logic;
        o_refresh_n : out std_logic;
        o_halted_n : out std_logic;
        o_bus_acknowledge_n : out std_logic;
        ou16_address : out unsigned(15 downto 0);
        iu8_read_data : in unsigned(7 downto 0);
        ou8_write_data : out unsigned(7 downto 0)
    );
end entity;

architecture evaluation of rabbitpunch_t80 is
begin
    o_bus_acknowledge_n <= '1';
    assert (i_nonmaskable_interrupt_n = '1' and i_bus_request_n = '1')
        report "State T80 normal adapter requires RabbitPunch inactive NMI/BUSRQ" severity failure;
    cpu : entity work.rabbitpunch_t80_capture
        port map (
            i_clk => i_clk,
            i_reset_n => i_reset_n,
            i_clock_enable => i_clock_enable,
            i_wait_n => i_wait_n,
            i_interrupt_n => i_interrupt_n,
            o_opcode_fetch_n => o_opcode_fetch_n,
            o_memory_request_n => o_memory_request_n,
            o_io_request_n => o_io_request_n,
            o_read_n => o_read_n,
            o_write_n => o_write_n,
            o_refresh_n => o_refresh_n,
            o_halted_n => o_halted_n,
            ou16_address => ou16_address,
            iu8_read_data => iu8_read_data,
            ou8_write_data => ou8_write_data,
            i_capture_request => '0',
            i_cancel => '0',
            i_bus_drained => '1',
            o_capture_pending => open,
            o_held => open,
            i_resume => '0',
            i_state_write => '0',
            iu256_state_data => (others => '0'),
            ou256_state_data => open,
            o_clean_boundary => open,
            ou3_machine_cycle => open,
            ou3_clock_phase => open
        );
end architecture;
