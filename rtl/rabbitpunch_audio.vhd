library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical audio subsystem. Both ROM transports are external. PCM outputs
-- remain separate raw two's-complement buses; no mixer or new clock is added.
entity rabbitpunch_audio is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_cpu_enable : in std_logic;
        i_ym_enable : in std_logic;
        i_ym_half_enable : in std_logic;
        i_adpcm_enable : in std_logic;
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
        o_adpcm_rom_request : out std_logic;
        ou18_adpcm_rom_address : out unsigned(17 downto 0);
        i_adpcm_rom_valid : in std_logic;
        iu8_adpcm_rom_data : in unsigned(7 downto 0);
        ou9_adpcm_pcm : out unsigned(8 downto 0);
        o_adpcm_busy : out std_logic;
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


architecture rtl of rabbitpunch_audio is
    signal s_adpcm_control_write, s_adpcm_command_write : std_logic;
    signal su8_adpcm_data : unsigned(7 downto 0);
begin
    sound_board : entity work.rabbitpunch_sound_board
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_cpu_enable => i_cpu_enable,
            i_ym_enable => i_ym_enable,
            i_ym_half_enable => i_ym_half_enable,
            i_pause => i_pause,
            o_paused => o_paused,
            iu8_command => iu8_command,
            i_command_pending => i_command_pending,
            o_command_read => o_command_read,
            o_rom_request => o_rom_request,
            ou16_rom_address => ou16_rom_address,
            i_rom_ready => i_rom_ready,
            i_rom_response_valid => i_rom_response_valid,
            iu8_rom_response_data => iu8_rom_response_data,
            o_adpcm_control_write => s_adpcm_control_write,
            o_adpcm_command_write => s_adpcm_command_write,
            ou8_adpcm_data => su8_adpcm_data,
            ou16_left_pcm => ou16_left_pcm,
            ou16_right_pcm => ou16_right_pcm,
            o_sample_marker => o_sample_marker,
            i_view_enable => i_view_enable,
            iu11_view_address => iu11_view_address,
            ou8_view_data => ou8_view_data,
            o_debug_request => o_debug_request,
            o_debug_write => o_debug_write,
            ou16_debug_address => ou16_debug_address,
            ou8_debug_data => ou8_debug_data
        );
    adpcm : entity work.rabbitpunch_adpcm
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_enable => i_adpcm_enable,
            i_control_write => s_adpcm_control_write,
            i_command_write => s_adpcm_command_write,
            iu8_write_data => su8_adpcm_data,
            o_busy => o_adpcm_busy,
            o_rom_request => o_adpcm_rom_request,
            ou18_rom_address => ou18_adpcm_rom_address,
            i_rom_valid => i_adpcm_rom_valid,
            iu8_rom_data => iu8_adpcm_rom_data,
            ou9_pcm => ou9_adpcm_pcm,
            o_bank => open,
            o_reset_asserted => open
        );
end architecture;
