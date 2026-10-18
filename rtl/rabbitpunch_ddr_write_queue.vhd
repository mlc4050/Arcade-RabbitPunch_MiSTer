-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Presentation-only write queue. Input pulses cannot be stalled by the legacy
-- rotation donor. Overflow is sticky and requires the owner to discard that
-- frame; this queue is not yet connected to production DDR or the ROM loader.
entity rabbitpunch_ddr_write_queue is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_write : in std_logic;
        iu29_word_address : in unsigned(28 downto 0);
        iu64_data : in unsigned(63 downto 0);
        iu8_byte_enables : in unsigned(7 downto 0);
        o_full : out std_logic;
        o_empty : out std_logic;
        o_overflow : out std_logic;
        i_ddr_busy : in std_logic;
        o_ddr_write : out std_logic;
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_ddr_write_queue is
    type t_memory is array(0 to 511) of unsigned(100 downto 0);
    signal su101_memory : t_memory;
    signal su101_output : unsigned(100 downto 0) := (others => '0');
    signal su9_write_pointer, su9_read_pointer : unsigned(8 downto 0) := (others => '0');
    signal su9_memory_entries : unsigned(8 downto 0) := (others => '0');
    signal s_output_valid, s_overflow : std_logic := '0';
begin
    -- Reserve one RAM slot to avoid simultaneous read/write of the same RAM
    -- address at full occupancy. The output register is the 512th queue slot.
    o_full <= '1' when su9_memory_entries = 511 else '0';
    o_empty <= '1' when su9_memory_entries = 0 and s_output_valid = '0' else '0';
    o_overflow <= s_overflow;
    o_ddr_write <= s_output_valid and not i_ddr_busy and not i_initialize;
    ou29_ddr_word_address <= su101_output(100 downto 72);
    ou64_ddr_data <= su101_output(71 downto 8);
    ou8_ddr_byte_enables <= su101_output(7 downto 0);
    queue : process(i_clk)
        variable v_output_available, v_read_memory, v_write_memory, v_direct : boolean;
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                su9_write_pointer <= (others => '0');
                su9_read_pointer <= (others => '0');
                su9_memory_entries <= (others => '0');
                s_output_valid <= '0';
                s_overflow <= '0';
            else
                v_output_available := s_output_valid = '0' or i_ddr_busy = '0';
                v_read_memory := v_output_available and su9_memory_entries /= 0;
                v_direct := v_output_available and su9_memory_entries = 0 and i_write = '1';
                v_write_memory := i_write = '1' and not v_direct and
                    (su9_memory_entries /= 511 or v_read_memory);
                if (v_output_available) then
                    s_output_valid <= '0';
                    if (v_read_memory) then
                        su101_output <= su101_memory(to_integer(su9_read_pointer));
                        su9_read_pointer <= su9_read_pointer + 1;
                        s_output_valid <= '1';
                    elsif (v_direct) then
                        su101_output <= iu29_word_address & iu64_data & iu8_byte_enables;
                        s_output_valid <= '1';
                    end if;
                end if;
                if (v_write_memory) then
                    su101_memory(to_integer(su9_write_pointer)) <=
                        iu29_word_address & iu64_data & iu8_byte_enables;
                    su9_write_pointer <= su9_write_pointer + 1;
                end if;
                if (v_write_memory and not v_read_memory) then
                    su9_memory_entries <= su9_memory_entries + 1;
                elsif (v_read_memory and not v_write_memory) then
                    su9_memory_entries <= su9_memory_entries - 1;
                end if;
                if (i_write = '1' and not v_direct and not v_write_memory) then
                    s_overflow <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
