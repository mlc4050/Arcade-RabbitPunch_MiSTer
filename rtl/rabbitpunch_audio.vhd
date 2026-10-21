library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical audio subsystem. Both ROM transports are external. PCM outputs
-- remain separate raw two's-complement buses; no mixer or new clock is added.
entity rabbitpunch_audio is
    generic (
        GBOOL_STATE_CAPABLE : boolean := false
    );
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
        ou8_debug_data : out unsigned(7 downto 0);
        i_capture_request : in std_logic := '0';
        i_capture_cancel : in std_logic := '0';
        o_capture_pending : out std_logic := '0';
        o_state_held : out std_logic := '0';
        o_state_cpu_drained : out std_logic := '0';
        i_state_resume : in std_logic := '0';
        i_cpu_state_write : in std_logic := '0';
        iu256_cpu_state : in unsigned(255 downto 0) := (others => '0');
        ou256_cpu_state : out unsigned(255 downto 0) := (others => '0');
        i_state_hold : in std_logic := '0';
        i_fm_state_write : in std_logic := '0';
        iu16_chip_state_word_address : in unsigned(15 downto 0) := (others => '0');
        iu32_chip_state_write_data : in unsigned(31 downto 0) := (others => '0');
        ou32_fm_state_read_data : out unsigned(31 downto 0) := (others => '0');
        i_state_memory_access : in std_logic := '0';
        i_state_memory_request : in std_logic := '0';
        i_state_memory_write : in std_logic := '0';
        iu16_state_memory_address : in unsigned(15 downto 0) := (others => '0');
        iu8_state_memory_data : in unsigned(7 downto 0) := (others => '0');
        o_state_memory_response : out std_logic := '0';
        ou8_state_memory_data : out unsigned(7 downto 0) := (others => '0');
        i_adpcm_state_load : in std_logic := '0';
        iu16_adpcm_state : in unsigned(15 downto 0) := (others => '0');
        ou16_adpcm_state : out unsigned(15 downto 0) := (others => '0');
        i_adpcm_chip_state_write : in std_logic := '0';
        ou32_adpcm_chip_state_read_data : out unsigned(31 downto 0) := (others => '0');
        o_state_bus_idle : out std_logic := '0'
    );
end entity;


architecture rtl of rabbitpunch_audio is
    signal s_adpcm_control_write, s_adpcm_command_write : std_logic;
    signal su8_adpcm_data : unsigned(7 downto 0);
begin
    sound_board : entity work.rabbitpunch_sound_board
        generic map (
            GBOOL_STATE_CAPABLE => GBOOL_STATE_CAPABLE
        )
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
            ou8_debug_data => ou8_debug_data,
            i_capture_request => i_capture_request,
            i_capture_cancel => i_capture_cancel,
            o_capture_pending => o_capture_pending,
            o_state_held => o_state_held,
            o_state_cpu_drained => o_state_cpu_drained,
            o_state_bus_idle => o_state_bus_idle,
            i_state_resume => i_state_resume,
            i_cpu_state_write => i_cpu_state_write,
            iu256_cpu_state => iu256_cpu_state,
            ou256_cpu_state => ou256_cpu_state,
            i_state_hold => i_state_hold,
            i_fm_state_write => i_fm_state_write,
            iu16_chip_state_word_address => iu16_chip_state_word_address,
            iu32_chip_state_write_data => iu32_chip_state_write_data,
            ou32_fm_state_read_data => ou32_fm_state_read_data,
            i_state_memory_access => i_state_memory_access,
            i_state_memory_request => i_state_memory_request,
            i_state_memory_write => i_state_memory_write,
            iu16_state_memory_address => iu16_state_memory_address,
            iu8_state_memory_data => iu8_state_memory_data,
            o_state_memory_response => o_state_memory_response,
            ou8_state_memory_data => ou8_state_memory_data
        );
    adpcm : entity work.rabbitpunch_adpcm
        generic map (
            GBOOL_STATE_CAPABLE => GBOOL_STATE_CAPABLE
        )
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
            o_reset_asserted => open,
            i_state_hold => i_state_hold,
            i_state_load => i_adpcm_state_load,
            iu16_state => iu16_adpcm_state,
            ou16_state => ou16_adpcm_state,
            i_chip_state_write => i_adpcm_chip_state_write,
            iu16_chip_state_word_address => iu16_chip_state_word_address,
            iu32_chip_state_write_data => iu32_chip_state_write_data,
            ou32_chip_state_read_data => ou32_adpcm_chip_state_read_data
        );
end architecture;
