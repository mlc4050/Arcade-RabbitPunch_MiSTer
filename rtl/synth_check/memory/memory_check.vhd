-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity memory_check is
    port (
        i_clk : in std_logic;
        i_request : in std_logic;
        i_request_write : in std_logic;
        iu24_request_address : in unsigned(23 downto 0);
        iu16_request_data : in unsigned(15 downto 0);
        iu2_request_bytes : in unsigned(1 downto 0);
        o_request_supported : out std_logic;
        o_response_valid : out std_logic;
        ou16_response_data : out unsigned(15 downto 0);
        o_rom_request : out std_logic;
        ou18_rom_byte_address : out unsigned(17 downto 0);
        i_rom_response_valid : in std_logic;
        iu16_rom_response_data : in unsigned(15 downto 0);
        i_view_enable : in std_logic;
        iu5_view_target : in target_t;
        iu15_view_word_address : in unsigned(14 downto 0);
        o_view_valid : out std_logic;
        ou16_view_data : out unsigned(15 downto 0)
    );
end entity;

-- Evaluation-only registers; production memory and latency are unchanged.
architecture evaluation of memory_check is
    signal s_boundary_i_request : std_logic := '0';
    signal s_boundary_i_request_write : std_logic := '0';
    signal su24_boundary_iu24_request_address : unsigned(23 downto 0) := (others => '0');
    signal su16_boundary_iu16_request_data : unsigned(15 downto 0) := (others => '0');
    signal su2_boundary_iu2_request_bytes : unsigned(1 downto 0) := (others => '0');
    signal s_boundary_o_request_supported : std_logic := '0';
    signal s_boundary_o_response_valid : std_logic := '0';
    signal su16_boundary_ou16_response_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_o_rom_request : std_logic := '0';
    signal su18_boundary_ou18_rom_byte_address : unsigned(17 downto 0) := (others => '0');
    signal s_boundary_i_rom_response_valid : std_logic := '0';
    signal su16_boundary_iu16_rom_response_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_view_enable : std_logic := '0';
    signal su5_boundary_iu5_view_target : target_t := (others => '0');
    signal su15_boundary_iu15_view_word_address : unsigned(14 downto 0) := (others => '0');
    signal s_boundary_o_view_valid : std_logic := '0';
    signal su16_boundary_ou16_view_data : unsigned(15 downto 0) := (others => '0');
begin
    boundary : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_request <= i_request;
            s_boundary_i_request_write <= i_request_write;
            su24_boundary_iu24_request_address <= iu24_request_address;
            su16_boundary_iu16_request_data <= iu16_request_data;
            su2_boundary_iu2_request_bytes <= iu2_request_bytes;
            o_request_supported <= s_boundary_o_request_supported;
            o_response_valid <= s_boundary_o_response_valid;
            ou16_response_data <= su16_boundary_ou16_response_data;
            o_rom_request <= s_boundary_o_rom_request;
            ou18_rom_byte_address <= su18_boundary_ou18_rom_byte_address;
            s_boundary_i_rom_response_valid <= i_rom_response_valid;
            su16_boundary_iu16_rom_response_data <= iu16_rom_response_data;
            s_boundary_i_view_enable <= i_view_enable;
            su5_boundary_iu5_view_target <= iu5_view_target;
            su15_boundary_iu15_view_word_address <= iu15_view_word_address;
            o_view_valid <= s_boundary_o_view_valid;
            ou16_view_data <= su16_boundary_ou16_view_data;
        end if;
    end process;
    memory : entity work.rabbitpunch_memory
        port map (
            i_clk => i_clk,
            i_request => s_boundary_i_request,
            i_request_write => s_boundary_i_request_write,
            iu24_request_address => su24_boundary_iu24_request_address,
            iu16_request_data => su16_boundary_iu16_request_data,
            iu2_request_bytes => su2_boundary_iu2_request_bytes,
            o_request_supported => s_boundary_o_request_supported,
            o_response_valid => s_boundary_o_response_valid,
            ou16_response_data => su16_boundary_ou16_response_data,
            o_rom_request => s_boundary_o_rom_request,
            ou18_rom_byte_address => su18_boundary_ou18_rom_byte_address,
            i_rom_response_valid => s_boundary_i_rom_response_valid,
            iu16_rom_response_data => su16_boundary_iu16_rom_response_data,
            i_view_enable => s_boundary_i_view_enable,
            iu5_view_target => su5_boundary_iu5_view_target,
            iu15_view_word_address => su15_boundary_iu15_view_word_address,
            o_view_valid => s_boundary_o_view_valid,
            ou16_view_data => su16_boundary_ou16_view_data
        );
end architecture;
