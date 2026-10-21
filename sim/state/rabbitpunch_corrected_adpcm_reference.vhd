-- SPDX-License-Identifier: GPL-3.0-or-later
-- Independent native reference from ea4c83e production wrapper.
-- Rabbit Punch standalone player. The divider, FIFO and nibble decoder
-- are unchanged JT7759 imports; the controller uses MAME silence duration.
-- PCM is signed nine-bit two's-complement carried on an unsigned bus.
-- The board adapter owns bank selection and reset/start timing.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rabbitpunch_corrected_adpcm_reference is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_start : in std_logic;
        iu8_command : in unsigned(7 downto 0);
        o_busy : out std_logic;
        o_data_request_n : out std_logic;
        o_rom_request : out std_logic;
        ou17_rom_address : out unsigned(16 downto 0);
        i_rom_valid : in std_logic;
        iu8_rom_data : in unsigned(7 downto 0);
        ou9_pcm : out unsigned(8 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_corrected_adpcm_reference is
    component jt7759_div is
        port (
            clk : in std_logic;
            cen : in std_logic;
            divby : in unsigned(5 downto 0);
            cen_ctl : out std_logic;
            cen_dec : out std_logic
        );
    end component;
    component jt7759_data is
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen_ctl : in std_logic;
            cen_dec : in std_logic;
            mdn : in std_logic;
            ctrl_flush : in std_logic;
            ctrl_cs : in std_logic;
            ctrl_busyn : in std_logic;
            ctrl_addr : in unsigned(16 downto 0);
            ctrl_din : out unsigned(7 downto 0);
            ctrl_ok : out std_logic;
            rom_cs : out std_logic;
            rom_addr : out unsigned(16 downto 0);
            rom_data : in unsigned(7 downto 0);
            rom_ok : in std_logic;
            cs : in std_logic;
            wrn : in std_logic;
            din : in unsigned(7 downto 0);
            drqn : out std_logic
        );
    end component;
    component jt7759_adpcm is
        generic (
            SW : integer := 9
        );
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen_dec : in std_logic;
            encoded : in unsigned(3 downto 0);
            sound : out unsigned(8 downto 0)
        );
    end component;
    signal su6_divider : unsigned(5 downto 0);
    signal su4_encoded : unsigned(3 downto 0);
    signal su17_control_address : unsigned(16 downto 0);
    signal su8_control_data : unsigned(7 downto 0);
    signal s_control_enable, s_decode_enable, s_decoder_reset : std_logic;
    signal s_control_request, s_control_ready, s_fifo_flush : std_logic;
    signal s_busy_n, s_data_request_n : std_logic;
begin
    o_busy <= not s_busy_n;
    o_data_request_n <= s_data_request_n;
    divider : jt7759_div
        port map (
            clk => i_clk,
            cen => i_enable,
            divby => su6_divider,
            cen_ctl => s_control_enable,
            cen_dec => s_decode_enable
        );
    control : entity work.rabbitpunch_upd7759_control
        generic map (
            GBOOL_MAME_SILENCE => true
        )
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_control_enable => s_control_enable,
            i_decode_enable => s_decode_enable,
            i_start_n => not i_start,
            i_chip_select => '1',
            i_standalone_mode => '1',
            i_data_request_n => s_data_request_n,
            i_write_n => '1',
            iu8_command => iu8_command,
            ou6_divider => su6_divider,
            o_busy_n => s_busy_n,
            o_decoder_reset => s_decoder_reset,
            ou4_decoder_nibble => su4_encoded,
            o_rom_request => s_control_request,
            ou17_rom_address => su17_control_address,
            iu8_rom_data => su8_control_data,
            i_rom_valid => s_control_ready,
            o_fifo_flush => s_fifo_flush,
            ou17_debug_silence_remaining => open
        );
    rom_fifo : jt7759_data
        port map (
            rst => i_reset,
            clk => i_clk,
            cen_ctl => s_control_enable,
            cen_dec => s_decode_enable,
            mdn => '1',
            ctrl_flush => s_fifo_flush,
            ctrl_cs => s_control_request,
            ctrl_busyn => s_busy_n,
            ctrl_addr => su17_control_address,
            ctrl_din => su8_control_data,
            ctrl_ok => s_control_ready,
            rom_cs => o_rom_request,
            rom_addr => ou17_rom_address,
            rom_data => iu8_rom_data,
            rom_ok => i_rom_valid,
            cs => '1',
            wrn => '1',
            din => iu8_command,
            drqn => s_data_request_n
        );
    decoder : jt7759_adpcm
        generic map (
            SW => 9
        )
        port map (
            rst => s_decoder_reset,
            clk => i_clk,
            cen_dec => s_decode_enable,
            encoded => su4_encoded,
            sound => ou9_pcm
        );
end architecture;
