-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_config.all;

-- Isolated actual-HPS/control evaluation. Enabled configuration is local to
-- this protocol test; the production shell still advertises no savestates.
entity state_host_check is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        iu16_host_data : in unsigned(15 downto 0);
        i_host_strobe : in std_logic;
        i_uio_select : in std_logic;
        i_file_select : in std_logic;
        ou16_host_response : out unsigned(15 downto 0);
        o_host_wait : out std_logic;
        o_wide_mode : out std_logic;
        iu16_menu_mask : in unsigned(15 downto 0);
        ou128_status : out unsigned(127 downto 0);
        i_service_ready : in std_logic;
        i_service_busy : in std_logic;
        i_service_finished : in std_logic;
        i_service_success : in std_logic;
        o_save : out std_logic;
        o_restore : out std_logic;
        ou2_slot : out unsigned(1 downto 0)
    );
end entity;

architecture evaluation of state_host_check is
    signal su46_hps_bus : unsigned(45 downto 0);
    signal su128_status, su128_status_data : unsigned(127 downto 0);
    signal su16_menu_mask : unsigned(15 downto 0);
    signal s_status_set, s_unavailable : std_logic;
begin
    su46_hps_bus(45 downto 44) <= "00";
    su46_hps_bus(43) <= i_clk;
    su46_hps_bus(42) <= i_clk;
    su46_hps_bus(41 downto 38) <= "0000";
    su46_hps_bus(35) <= i_file_select;
    su46_hps_bus(34) <= i_uio_select;
    su46_hps_bus(33) <= i_host_strobe;
    su46_hps_bus(31 downto 16) <= iu16_host_data;
    ou16_host_response <= su46_hps_bus(15 downto 0);
    o_host_wait <= su46_hps_bus(37);
    o_wide_mode <= su46_hps_bus(32);
    ou128_status <= su128_status;
    su16_menu_mask <= iu16_menu_mask or (15 downto 9 => '0') & s_unavailable & (7 downto 0 => '0');
    host : entity work.rabbitpunch_host
        generic map (
            GSTR_CONFIG_STRING => F_STATE_CONFIG(true)
        )
        port map (
            i_clk => i_clk,
            iou46_hps_bus => su46_hps_bus,
            iu16_menu_mask => su16_menu_mask,
            i_status_set => s_status_set,
            iu128_status_data => su128_status_data,
            ou128_status => su128_status,
            ou2_audio_mix => open,
            ou32_joystick0 => open,
            ou32_joystick1 => open,
            ou11_key_event => open,
            ou2_buttons => open,
            o_forced_scandoubler => open,
            o_direct_video => open,
            ou16_sdram_configuration => open,
            o_file_download => open,
            ou16_file_index => open,
            o_file_write => open,
            ou27_file_byte_address => open,
            ou8_file_data => open,
            i_file_wait => '0',
            o_file_upload => open,
            o_file_read => open
        );
    controls : entity work.rabbitpunch_state_controls
        generic map (
            GBOOL_ENABLE => true
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            iu128_status => su128_status,
            i_service_ready => i_service_ready,
            i_service_busy => i_service_busy,
            i_service_finished => i_service_finished,
            i_service_success => i_service_success,
            i_service_incomplete => '0',
            o_save => o_save,
            o_restore => o_restore,
            ou2_slot => ou2_slot,
            o_unavailable => s_unavailable,
            o_save_unavailable => open,
            o_status_set => s_status_set,
            ou128_status_data => su128_status_data
        );
end architecture;
