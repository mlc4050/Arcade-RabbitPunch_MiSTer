-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical host-bus tester. Video telemetry clocks are both tied to i_clk;
-- no measurement of real video/100-MHz telemetry is claimed by this profile.
entity host_check is
    port (
        i_clk : in std_logic;
        iu16_host_data : in unsigned(15 downto 0);
        i_host_strobe : in std_logic;
        i_uio_select : in std_logic;
        i_file_select : in std_logic;
        ou16_host_response : out unsigned(15 downto 0);
        o_host_wait : out std_logic;
        o_wide_mode : out std_logic;
        iu16_menu_mask : in unsigned(15 downto 0);
        ou128_status : out unsigned(127 downto 0);
        ou32_joystick0 : out unsigned(31 downto 0);
        ou32_joystick1 : out unsigned(31 downto 0);
        ou11_key_event : out unsigned(10 downto 0);
        ou2_buttons : out unsigned(1 downto 0);
        o_forced_scandoubler : out std_logic;
        o_direct_video : out std_logic;
        ou16_sdram_configuration : out unsigned(15 downto 0);
        o_file_download : out std_logic;
        ou16_file_index : out unsigned(15 downto 0);
        o_file_write : out std_logic;
        ou27_file_byte_address : out unsigned(26 downto 0);
        ou8_file_data : out unsigned(7 downto 0);
        i_file_wait : in std_logic
    );
end entity;

architecture evaluation of host_check is
    signal su46_hps_bus : unsigned(45 downto 0);
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
    host : entity work.rabbitpunch_host
        port map (
            i_clk => i_clk,
            iou46_hps_bus => su46_hps_bus,
            iu16_menu_mask => iu16_menu_mask,
            ou128_status => ou128_status,
            ou32_joystick0 => ou32_joystick0,
            ou32_joystick1 => ou32_joystick1,
            ou11_key_event => ou11_key_event,
            ou2_buttons => ou2_buttons,
            o_forced_scandoubler => o_forced_scandoubler,
            o_direct_video => o_direct_video,
            ou16_sdram_configuration => ou16_sdram_configuration,
            o_file_download => o_file_download,
            ou16_file_index => ou16_file_index,
            o_file_write => o_file_write,
            ou27_file_byte_address => ou27_file_byte_address,
            ou8_file_data => ou8_file_data,
            i_file_wait => i_file_wait
        );
end architecture;
