-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Private single-port image RAM. Fill every byte in order before sealing;
-- sealed bytes are immutable until an explicit new session. Restore preflight
-- and application must both read this copy, avoiding a mutable external DDR
-- source between validation and RAM/CPU loads. Sealing is completeness only;
-- it does not replace CRC/identity/semantic validation.
entity rabbitpunch_state_image_buffer is
    generic (
        GINT_IMAGE_BYTES : positive
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_begin : in std_logic;
        i_cancel : in std_logic;
        i_fill_valid : in std_logic;
        o_fill_ready : out std_logic;
        iu8_fill_data : in unsigned(7 downto 0);
        i_seal : in std_logic;
        o_sealed : out std_logic;
        o_error : out std_logic;
        ou18_filled_bytes : out unsigned(17 downto 0);
        i_read_valid : in std_logic;
        iu18_read_address : in unsigned(17 downto 0);
        o_read_response : out std_logic;
        o_read_error : out std_logic;
        ou8_read_data : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_image_buffer is
    type t_memory is array(0 to GINT_IMAGE_BYTES - 1) of unsigned(7 downto 0);
    signal su8_memory : t_memory;
    signal su18_count : unsigned(17 downto 0) := (others => '0');
    signal s_filling, s_sealed, s_error : std_logic := '0';
    signal s_write_enable, s_read_enable, s_read_legal : std_logic;
begin
    assert (GINT_IMAGE_BYTES >= 64 and GINT_IMAGE_BYTES <= 262136 and
        GINT_IMAGE_BYTES mod 8 = 0) report "Invalid private state image size" severity failure;
    o_sealed <= s_sealed;
    o_error <= s_error;
    ou18_filled_bytes <= su18_count;
    o_fill_ready <= '1' when s_filling = '1' and su18_count < GINT_IMAGE_BYTES and
        i_initialize = '0' and i_cancel = '0' and i_begin = '0' else '0';
    s_write_enable <= i_fill_valid and o_fill_ready;
    s_read_enable <= i_read_valid and s_sealed and not i_initialize and not i_cancel and not i_begin;
    s_read_legal <= '1' when iu18_read_address < GINT_IMAGE_BYTES else '0';
    -- No reset/initialization on RAM or its output register. Both accesses use
    -- one synchronous port and are mutually exclusive by phase.
    storage : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (s_write_enable = '1') then
                su8_memory(to_integer(su18_count)) <= iu8_fill_data;
            elsif (s_read_enable = '1' and s_read_legal = '1') then
                ou8_read_data <= su8_memory(to_integer(iu18_read_address));
            end if;
        end if;
    end process;
    session : process(i_clk)
        variable vu18_count : unsigned(17 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_read_response <= s_read_enable;
            o_read_error <= s_read_enable and not s_read_legal;
            if (i_initialize = '1' or i_cancel = '1') then
                s_filling <= '0';
                s_sealed <= '0';
                s_error <= '0';
                su18_count <= (others => '0');
            elsif (i_begin = '1') then
                s_filling <= '1';
                s_sealed <= '0';
                s_error <= '0';
                su18_count <= (others => '0');
            elsif (s_filling = '1') then
                vu18_count := su18_count;
                if (s_write_enable = '1') then
                    vu18_count := vu18_count + 1;
                end if;
                su18_count <= vu18_count;
                if (i_seal = '1') then
                    s_filling <= '0';
                    if (vu18_count = GINT_IMAGE_BYTES) then
                        s_sealed <= '1';
                    else
                        s_error <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
