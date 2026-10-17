library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical sound board. The caller supplies synchronous 4 MHz/2 MHz enables,
-- an audio-ROM byte transport, and the main board's existing command latch.
entity rabbitpunch_sound_board is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_cpu_enable : in std_logic;
        i_ym_enable : in std_logic;
        i_ym_half_enable : in std_logic;
        i_pause : in std_logic;
        o_paused : out std_logic;
        iu8_command : in unsigned(7 downto 0);
        i_command_pending : in std_logic;
        o_command_read : out std_logic;
        o_rom_request : out std_logic;
        ou16_rom_address : out unsigned(15 downto 0);
        i_rom_ready : in std_logic;
        i_rom_response_valid : in std_logic;
        iu8_rom_response_data : in unsigned(7 downto 0);
        o_adpcm_control_write : out std_logic;
        o_adpcm_command_write : out std_logic;
        ou8_adpcm_data : out unsigned(7 downto 0);
        ou16_left_pcm : out unsigned(15 downto 0);
        ou16_right_pcm : out unsigned(15 downto 0);
        o_sample_marker : out std_logic;
        i_view_enable : in std_logic;
        iu11_view_address : in unsigned(10 downto 0);
        ou8_view_data : out unsigned(7 downto 0);
        o_debug_request : out std_logic;
        o_debug_write : out std_logic;
        ou16_debug_address : out unsigned(15 downto 0);
        ou8_debug_data : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_sound_board is
    signal s_request, s_write, s_response, s_ym_write, s_ym_data, s_ym_interrupt, s_paused : std_logic;
    signal su16_address : unsigned(15 downto 0);
    signal su8_data, su8_reply, su8_ym_status, su8_ym_data : unsigned(7 downto 0);
begin
    o_paused <= s_paused;
    o_debug_request <= s_request;
    o_debug_write <= s_write;
    ou16_debug_address <= su16_address;
    ou8_debug_data <= su8_data;
    assert (i_view_enable /= '1' or s_paused = '1')
        report "Sound RAM inspection requires drained CPU pause" severity failure;
    sound_cpu : entity work.rabbitpunch_soundcpu
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_enable => i_cpu_enable,
            i_pause => i_pause,
            i_interrupt => s_ym_interrupt or i_command_pending,
            o_request => s_request,
            o_request_write => s_write,
            ou16_request_address => su16_address,
            ou8_request_data => su8_data,
            i_response_valid => s_response,
            iu8_response_data => su8_reply,
            o_paused => s_paused,
            o_halted => open
        );
    sound_bus : entity work.rabbitpunch_sound_bus
        port map (
            i_clk => i_clk,
            i_request => s_request,
            i_request_write => s_write,
            iu16_request_address => su16_address,
            iu8_request_data => su8_data,
            o_response_valid => s_response,
            ou8_response_data => su8_reply,
            o_rom_request => o_rom_request,
            ou16_rom_address => ou16_rom_address,
            i_rom_ready => i_rom_ready,
            i_rom_response_valid => i_rom_response_valid,
            iu8_rom_response_data => iu8_rom_response_data,
            i_ym_write_enable => i_ym_half_enable,
            iu8_ym_status => su8_ym_status,
            o_ym_write => s_ym_write,
            o_ym_data_register => s_ym_data,
            ou8_ym_write_data => su8_ym_data,
            iu8_command => iu8_command,
            o_command_read => o_command_read,
            o_adpcm_control_write => o_adpcm_control_write,
            o_adpcm_command_write => o_adpcm_command_write,
            ou8_adpcm_data => ou8_adpcm_data,
            i_view_enable => i_view_enable,
            iu11_view_address => iu11_view_address,
            ou8_view_data => ou8_view_data
        );
    ym2151 : entity work.rabbitpunch_ym2151
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_chip_enable => i_ym_enable,
            i_half_chip_enable => i_ym_half_enable,
            i_chip_select => s_ym_write,
            i_write => s_ym_write,
            i_data_register => s_ym_data,
            iu8_write_data => su8_ym_data,
            ou8_status => su8_ym_status,
            o_interrupt => s_ym_interrupt,
            o_sample_marker => o_sample_marker,
            ou16_left_pcm => ou16_left_pcm,
            ou16_right_pcm => ou16_right_pcm,
            ou16_full_left_pcm => open,
            ou16_full_right_pcm => open
        );
end architecture;
