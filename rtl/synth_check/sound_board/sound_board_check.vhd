library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical sound board. The caller supplies synchronous 4 MHz/2 MHz enables,
-- an audio-ROM byte transport, and the main board's existing command latch.
entity sound_board_check is
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


architecture evaluation of sound_board_check is
    signal s_boundary_i_reset : std_logic;
    signal s_boundary_i_cpu_enable : std_logic;
    signal s_boundary_i_ym_enable : std_logic;
    signal s_boundary_i_ym_half_enable : std_logic;
    signal s_boundary_i_pause : std_logic;
    signal s_boundary_o_paused : std_logic;
    signal su8_boundary_iu8_command : unsigned(7 downto 0);
    signal s_boundary_i_command_pending : std_logic;
    signal s_boundary_o_command_read : std_logic;
    signal s_boundary_o_rom_request : std_logic;
    signal su16_boundary_ou16_rom_address : unsigned(15 downto 0);
    signal s_boundary_i_rom_ready : std_logic;
    signal s_boundary_i_rom_response_valid : std_logic;
    signal su8_boundary_iu8_rom_response_data : unsigned(7 downto 0);
    signal s_boundary_o_adpcm_control_write : std_logic;
    signal s_boundary_o_adpcm_command_write : std_logic;
    signal su8_boundary_ou8_adpcm_data : unsigned(7 downto 0);
    signal su16_boundary_ou16_left_pcm : unsigned(15 downto 0);
    signal su16_boundary_ou16_right_pcm : unsigned(15 downto 0);
    signal s_boundary_o_sample_marker : std_logic;
    signal s_boundary_i_view_enable : std_logic;
    signal su11_boundary_iu11_view_address : unsigned(10 downto 0);
    signal su8_boundary_ou8_view_data : unsigned(7 downto 0);
    signal s_boundary_o_debug_request : std_logic;
    signal s_boundary_o_debug_write : std_logic;
    signal su16_boundary_ou16_debug_address : unsigned(15 downto 0);
    signal su8_boundary_ou8_debug_data : unsigned(7 downto 0);
begin
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_reset <= i_reset;
            s_boundary_i_cpu_enable <= i_cpu_enable;
            s_boundary_i_ym_enable <= i_ym_enable;
            s_boundary_i_ym_half_enable <= i_ym_half_enable;
            s_boundary_i_pause <= i_pause;
            o_paused <= s_boundary_o_paused;
            su8_boundary_iu8_command <= iu8_command;
            s_boundary_i_command_pending <= i_command_pending;
            o_command_read <= s_boundary_o_command_read;
            o_rom_request <= s_boundary_o_rom_request;
            ou16_rom_address <= su16_boundary_ou16_rom_address;
            s_boundary_i_rom_ready <= i_rom_ready;
            s_boundary_i_rom_response_valid <= i_rom_response_valid;
            su8_boundary_iu8_rom_response_data <= iu8_rom_response_data;
            o_adpcm_control_write <= s_boundary_o_adpcm_control_write;
            o_adpcm_command_write <= s_boundary_o_adpcm_command_write;
            ou8_adpcm_data <= su8_boundary_ou8_adpcm_data;
            ou16_left_pcm <= su16_boundary_ou16_left_pcm;
            ou16_right_pcm <= su16_boundary_ou16_right_pcm;
            o_sample_marker <= s_boundary_o_sample_marker;
            s_boundary_i_view_enable <= i_view_enable;
            su11_boundary_iu11_view_address <= iu11_view_address;
            ou8_view_data <= su8_boundary_ou8_view_data;
            o_debug_request <= s_boundary_o_debug_request;
            o_debug_write <= s_boundary_o_debug_write;
            ou16_debug_address <= su16_boundary_ou16_debug_address;
            ou8_debug_data <= su8_boundary_ou8_debug_data;
        end if;
    end process;
    sound_board : entity work.rabbitpunch_sound_board
        port map (
            i_clk => i_clk,
            i_reset => s_boundary_i_reset,
            i_cpu_enable => s_boundary_i_cpu_enable,
            i_ym_enable => s_boundary_i_ym_enable,
            i_ym_half_enable => s_boundary_i_ym_half_enable,
            i_pause => s_boundary_i_pause,
            o_paused => s_boundary_o_paused,
            iu8_command => su8_boundary_iu8_command,
            i_command_pending => s_boundary_i_command_pending,
            o_command_read => s_boundary_o_command_read,
            o_rom_request => s_boundary_o_rom_request,
            ou16_rom_address => su16_boundary_ou16_rom_address,
            i_rom_ready => s_boundary_i_rom_ready,
            i_rom_response_valid => s_boundary_i_rom_response_valid,
            iu8_rom_response_data => su8_boundary_iu8_rom_response_data,
            o_adpcm_control_write => s_boundary_o_adpcm_control_write,
            o_adpcm_command_write => s_boundary_o_adpcm_command_write,
            ou8_adpcm_data => su8_boundary_ou8_adpcm_data,
            ou16_left_pcm => su16_boundary_ou16_left_pcm,
            ou16_right_pcm => su16_boundary_ou16_right_pcm,
            o_sample_marker => s_boundary_o_sample_marker,
            i_view_enable => s_boundary_i_view_enable,
            iu11_view_address => su11_boundary_iu11_view_address,
            ou8_view_data => su8_boundary_ou8_view_data,
            o_debug_request => s_boundary_o_debug_request,
            o_debug_write => s_boundary_o_debug_write,
            ou16_debug_address => su16_boundary_ou16_debug_address,
            ou8_debug_data => su8_boundary_ou8_debug_data
        );
end architecture;
