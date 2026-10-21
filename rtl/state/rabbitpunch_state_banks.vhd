-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Held register-bank packing plus the real dense main/sound RAM adapter.
-- Keep the RAM session alive through every accepted body transaction, including
-- a one-clock gameplay reset. The lower RAM adapter suppresses canceled replies;
-- canceling it before the body owner retires would strand the upper debt.
entity rabbitpunch_state_banks is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_session : in std_logic;
        i_machine_held : in std_logic;
        i_apply_begin : in std_logic;
        i_byte_request : in std_logic;
        o_byte_ready : out std_logic;
        i_byte_write : in std_logic;
        iu18_byte_address : in unsigned(17 downto 0);
        iu8_byte_data : in unsigned(7 downto 0);
        o_byte_response : out std_logic;
        o_byte_error : out std_logic;
        ou8_byte_data : out unsigned(7 downto 0);
        i_commit : in std_logic;
        o_committed : out std_logic;
        o_commit_error : out std_logic;
        o_idle : out std_logic;
        ou5_m68k_address : out unsigned(4 downto 0);
        iu32_m68k_data : in unsigned(31 downto 0);
        o_m68k_write : out std_logic;
        ou32_m68k_data : out unsigned(31 downto 0);
        iu256_t80_data : in unsigned(255 downto 0);
        ou256_t80_data : out unsigned(255 downto 0);
        o_t80_load : out std_logic;
        iu512_board_data : in unsigned(511 downto 0);
        ou512_board_data : out unsigned(511 downto 0);
        o_board_load : out std_logic;
        ou16_chip_address : out unsigned(15 downto 0);
        iu32_fm_data : in unsigned(31 downto 0);
        iu32_adpcm_data : in unsigned(31 downto 0);
        ou32_chip_data : out unsigned(31 downto 0);
        o_fm_write : out std_logic;
        o_adpcm_write : out std_logic;
        o_main_request : out std_logic;
        o_main_write : out std_logic;
        ou24_main_address : out unsigned(23 downto 0);
        ou16_main_data : out unsigned(15 downto 0);
        ou2_main_bytes : out unsigned(1 downto 0);
        i_main_response : in std_logic;
        iu16_main_data : in unsigned(15 downto 0);
        o_sound_request : out std_logic;
        o_sound_write : out std_logic;
        ou16_sound_address : out unsigned(15 downto 0);
        ou8_sound_data : out unsigned(7 downto 0);
        i_sound_response : in std_logic;
        iu8_sound_data : in unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_banks is
    signal s_body_idle, s_memory_idle, s_memory_session, s_memory_initialize : std_logic;
    signal s_memory_request, s_memory_ready, s_memory_write, s_memory_response, s_memory_error : std_logic;
    signal su17_memory_address : unsigned(16 downto 0);
    signal su8_memory_write_data, su8_memory_read_data : unsigned(7 downto 0);
begin
    o_idle <= s_body_idle and s_memory_idle;
    s_memory_session <= i_session or not s_body_idle;
    s_memory_initialize <= i_initialize and s_body_idle and s_memory_idle;
    body_banks : entity work.rabbitpunch_state_body
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_session => i_session,
            i_machine_held => i_machine_held,
            i_apply_begin => i_apply_begin,
            i_byte_request => i_byte_request,
            o_byte_ready => o_byte_ready,
            i_byte_write => i_byte_write,
            iu18_byte_address => iu18_byte_address,
            iu8_byte_data => iu8_byte_data,
            o_byte_response => o_byte_response,
            o_byte_error => o_byte_error,
            ou8_byte_data => ou8_byte_data,
            i_commit => i_commit,
            o_committed => o_committed,
            o_commit_error => o_commit_error,
            o_idle => s_body_idle,
            o_memory_request => s_memory_request,
            i_memory_ready => s_memory_ready,
            o_memory_write => s_memory_write,
            ou17_memory_address => su17_memory_address,
            ou8_memory_data => su8_memory_write_data,
            i_memory_response => s_memory_response,
            i_memory_error => s_memory_error,
            iu8_memory_data => su8_memory_read_data,
            ou5_m68k_address => ou5_m68k_address,
            iu32_m68k_data => iu32_m68k_data,
            o_m68k_write => o_m68k_write,
            ou32_m68k_data => ou32_m68k_data,
            iu256_t80_data => iu256_t80_data,
            ou256_t80_data => ou256_t80_data,
            o_t80_load => o_t80_load,
            iu512_board_data => iu512_board_data,
            ou512_board_data => ou512_board_data,
            o_board_load => o_board_load,
            ou16_chip_address => ou16_chip_address,
            iu32_fm_data => iu32_fm_data,
            iu32_adpcm_data => iu32_adpcm_data,
            ou32_chip_data => ou32_chip_data,
            o_fm_write => o_fm_write,
            o_adpcm_write => o_adpcm_write
        );
    memory_banks : entity work.rabbitpunch_state_memory
        port map (
            i_clk => i_clk,
            i_initialize => s_memory_initialize,
            i_session => s_memory_session,
            i_drained => i_machine_held,
            o_pause => open,
            o_idle => s_memory_idle,
            i_byte_valid => s_memory_request,
            o_byte_ready => s_memory_ready,
            i_byte_write => s_memory_write,
            iu17_byte_address => su17_memory_address,
            iu8_byte_data => su8_memory_write_data,
            o_byte_response => s_memory_response,
            o_byte_error => s_memory_error,
            ou8_byte_data => su8_memory_read_data,
            o_main_request => o_main_request,
            o_main_write => o_main_write,
            ou24_main_address => ou24_main_address,
            ou16_main_data => ou16_main_data,
            ou2_main_bytes => ou2_main_bytes,
            i_main_response => i_main_response,
            iu16_main_data => iu16_main_data,
            o_sound_request => o_sound_request,
            o_sound_write => o_sound_write,
            ou16_sound_address => ou16_sound_address,
            ou8_sound_data => ou8_sound_data,
            i_sound_response => i_sound_response,
            iu8_sound_data => iu8_sound_data
        );
end architecture;
