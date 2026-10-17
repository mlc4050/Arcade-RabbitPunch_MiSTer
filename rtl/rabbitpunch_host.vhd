-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Descriptive byte-wide boundary around the unchanged MiSTer host module.
-- HPS_BUS retains all 46 native bit positions. Unused native disk/analog ports
-- are omitted just as in the framework template; this boundary enables neither.
entity rabbitpunch_host is
    generic (
        CONFIG_STRING : string := "RabbitPunch;;R0,Reset;"
    );
    port (
        i_clk : in std_logic;
        iou46_hps_bus : inout unsigned(45 downto 0);
        iu16_menu_mask : in unsigned(15 downto 0) := (others => '0');
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

architecture boundary of rabbitpunch_host is
    function pack_config(v_text : string) return unsigned is
        variable vux_result : unsigned(v_text'length * 8 - 1 downto 0);
        variable vint_byte : natural;
    begin
        for vint_index in v_text'range loop
            vint_byte := v_text'length - 1 - (vint_index - v_text'low);
            vux_result(vint_byte * 8 + 7 downto vint_byte * 8) := to_unsigned(character'pos(v_text(vint_index)), 8);
        end loop;
        return vux_result;
    end function;
    component hps_io is
        generic (
            CONF_STR : unsigned(CONFIG_STRING'length * 8 - 1 downto 0);
            STRLEN : integer := CONFIG_STRING'length;
            WIDE : integer := 0;
            PS2DIV : integer := 0
        );
        port (
            clk_sys : in std_logic;
            HPS_BUS : inout unsigned(45 downto 0);
            EXT_BUS : inout unsigned(35 downto 0);
            joystick_0 : out unsigned(31 downto 0);
            joystick_1 : out unsigned(31 downto 0);
            ps2_key : out unsigned(10 downto 0);
            buttons : out unsigned(1 downto 0);
            forced_scandoubler : out std_logic;
            direct_video : out std_logic;
            video_rotated : in std_logic;
            new_vmode : in std_logic;
            status : out unsigned(127 downto 0);
            status_in : in unsigned(127 downto 0);
            status_set : in std_logic;
            status_menumask : in unsigned(15 downto 0);
            info_req : in std_logic;
            info : in unsigned(7 downto 0);
            ioctl_download : out std_logic;
            ioctl_index : out unsigned(15 downto 0);
            ioctl_wr : out std_logic;
            ioctl_addr : out unsigned(26 downto 0);
            ioctl_dout : out unsigned(7 downto 0);
            ioctl_upload_req : in std_logic;
            ioctl_upload_index : in unsigned(7 downto 0);
            ioctl_din : in unsigned(7 downto 0);
            ioctl_wait : in std_logic;
            sdram_sz : out unsigned(15 downto 0)
        );
    end component;
    signal su36_unused_extensions : unsigned(35 downto 0);
begin
    -- Disable extension overrides of the normal host response bus.
    su36_unused_extensions(32) <= '0';
    su36_unused_extensions(15 downto 0) <= (others => '0');
    host_interface : hps_io
        generic map (
            CONF_STR => pack_config(CONFIG_STRING),
            STRLEN => CONFIG_STRING'length,
            WIDE => 0,
            PS2DIV => 0
        )
        port map (
            clk_sys => i_clk,
            HPS_BUS => iou46_hps_bus,
            EXT_BUS => su36_unused_extensions,
            joystick_0 => ou32_joystick0,
            joystick_1 => ou32_joystick1,
            ps2_key => ou11_key_event,
            buttons => ou2_buttons,
            forced_scandoubler => o_forced_scandoubler,
            direct_video => o_direct_video,
            video_rotated => '0',
            new_vmode => '0',
            status => ou128_status,
            status_in => (others => '0'),
            status_set => '0',
            status_menumask => iu16_menu_mask,
            info_req => '0',
            info => (others => '0'),
            ioctl_download => o_file_download,
            ioctl_index => ou16_file_index,
            ioctl_wr => o_file_write,
            ioctl_addr => ou27_file_byte_address,
            ioctl_dout => ou8_file_data,
            ioctl_upload_req => '0',
            ioctl_upload_index => (others => '0'),
            ioctl_din => (others => '0'),
            ioctl_wait => i_file_wait,
            sdram_sz => ou16_sdram_configuration
        );
end architecture;

