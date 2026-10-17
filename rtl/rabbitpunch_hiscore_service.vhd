-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standard MiSTer hiscore configuration index 3 and byte dump index 4.
-- ROM index 0 begins a new generation; metadata precedes an optional dump.
-- o_memory_initialize must reach the maintenance adapter, whose backend drain
-- is independent of the canceled score-client state.
entity rabbitpunch_hiscore_service is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_reset : in std_logic;
        i_osd_open : in std_logic;
        i_autosave : in std_logic;
        i_download : in std_logic;
        i_upload : in std_logic;
        iu16_file_index : in unsigned(15 downto 0);
        i_write : in std_logic;
        iu27_byte_address : in unsigned(26 downto 0);
        iu8_data : in unsigned(7 downto 0);
        ou8_data : out unsigned(7 downto 0);
        o_wait : out std_logic;
        o_upload_request : out std_logic;
        o_enabled : out std_logic;
        o_config_error : out std_logic;
        o_initialized : out std_logic;
        o_saved_valid : out std_logic;
        o_dirty : out std_logic;
        o_memory_initialize : out std_logic;
        o_memory_access : out std_logic;
        o_memory_valid : out std_logic;
        o_memory_write : out std_logic;
        ou14_memory_address : out unsigned(13 downto 0);
        ou8_memory_data : out unsigned(7 downto 0);
        i_memory_ready : in std_logic;
        i_memory_response : in std_logic;
        iu8_memory_data : in unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_hiscore_service is
    signal s_profile_valid, s_us, s_cold_reset, s_dump_download, s_dump_upload, s_wait : std_logic;
    signal su32_start_wait : unsigned(31 downto 0);
    signal su16_check_wait : unsigned(15 downto 0);
begin
    s_cold_reset <= '1' when i_initialize = '1' or
        (i_download = '1' and (iu16_file_index = 0 or iu16_file_index = 3)) else '0';
    o_memory_initialize <= s_cold_reset or i_game_reset;
    s_dump_download <= '1' when i_download = '1' and iu16_file_index = 4 else '0';
    s_dump_upload <= '1' when i_upload = '1' and iu16_file_index = 4 else '0';
    o_wait <= s_wait when iu16_file_index = 4 else '0';
    o_enabled <= s_profile_valid;
    metadata : entity work.rabbitpunch_hiscore_config
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_download => i_download,
            iu16_file_index => iu16_file_index,
            i_write => i_write,
            iu27_byte_address => iu27_byte_address,
            iu8_data => iu8_data,
            o_profile_valid => s_profile_valid,
            o_us_set => s_us,
            ou32_start_wait => su32_start_wait,
            ou16_check_wait => su16_check_wait,
            o_error => o_config_error
        );
    scores : entity work.rabbitpunch_hiscore
        port map (
            i_clk => i_clk,
            i_initialize => s_cold_reset,
            i_game_reset => i_game_reset,
            i_profile_valid => s_profile_valid,
            i_us_set => s_us,
            iu32_start_wait => su32_start_wait,
            iu16_check_wait => su16_check_wait,
            i_osd_open => i_osd_open,
            i_autosave => i_autosave,
            i_dump_download => s_dump_download,
            i_dump_write => i_write,
            i_dump_upload => s_dump_upload,
            iu27_dump_address => iu27_byte_address,
            iu8_dump_data => iu8_data,
            ou8_dump_data => ou8_data,
            o_dump_wait => s_wait,
            o_upload_request => o_upload_request,
            o_initialized => o_initialized,
            o_saved_valid => o_saved_valid,
            o_dirty => o_dirty,
            o_memory_access => o_memory_access,
            o_memory_valid => o_memory_valid,
            o_memory_write => o_memory_write,
            ou14_memory_address => ou14_memory_address,
            ou8_memory_data => ou8_memory_data,
            i_memory_ready => i_memory_ready,
            i_memory_response => i_memory_response,
            iu8_memory_data => iu8_memory_data
        );
end architecture;
