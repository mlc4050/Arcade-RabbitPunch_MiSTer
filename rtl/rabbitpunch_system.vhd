library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- Logical board plus sequential image loading and the SDRAM ROM subsystem.
-- Physical raster/PLL and HPS/DDR streaming remain external interfaces.
entity rabbitpunch_system is
    generic (
        sint_IMAGE_BYTES : positive := ROM_IMAGE_SIZE;
        EXTERNAL_PHASE_ENABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_main_phase_enable : in std_logic := '0';
        i_initialize : in std_logic;
        i_game_reset : in std_logic;
        i_pause : in std_logic;
        o_paused : out std_logic;
        i_maintenance_initialize : in std_logic := '0';
        i_maintenance_access : in std_logic := '0';
        i_maintenance_valid : in std_logic := '0';
        i_maintenance_write : in std_logic := '0';
        iu14_maintenance_byte_address : in unsigned(13 downto 0) := (others => '0');
        iu8_maintenance_data : in unsigned(7 downto 0) := (others => '0');
        o_maintenance_ready : out std_logic;
        o_maintenance_response_valid : out std_logic;
        ou8_maintenance_response_data : out unsigned(7 downto 0);
        o_maintenance_pause : out std_logic;

        i_vblank_start : in std_logic;
        i_half_frame : in std_logic;
        i_line_valid : in std_logic;
        o_line_ready : out std_logic;
        i_render_bank : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        o_line_done : out std_logic;
        i_pixel_valid : in std_logic;
        o_pixel_ready : out std_logic;
        i_pixel_bank : in std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        o_pixel_valid : out std_logic;
        o_pixel_error : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        i_view_enable : in std_logic;
        iu5_view_target : in target_t;
        iu15_view_word_address : in unsigned(14 downto 0);
        o_view_valid : out std_logic;
        ou16_view_data : out unsigned(15 downto 0);
        iu8_player1 : in unsigned(7 downto 0);
        iu8_player2 : in unsigned(7 downto 0);
        iu8_service : in unsigned(7 downto 0);
        iu16_dips : in unsigned(15 downto 0);
        i_sound_cpu_enable : in std_logic := '0';
        i_ym_enable : in std_logic := '0';
        i_ym_half_enable : in std_logic := '0';
        i_adpcm_enable : in std_logic := '0';
        ou16_left_pcm : out unsigned(15 downto 0);
        ou16_right_pcm : out unsigned(15 downto 0);
        ou9_adpcm_pcm : out unsigned(8 downto 0);
        ou16_mono_pcm : out unsigned(15 downto 0);
        o_audio_sample_marker : out std_logic;
        o_adpcm_busy : out std_logic;
        i_audio_view_enable : in std_logic := '0';
        iu11_audio_view_address : in unsigned(10 downto 0) := (others => '0');
        ou8_audio_view_data : out unsigned(7 downto 0);
        o_audio_debug_request : out std_logic;
        o_audio_debug_write : out std_logic;
        ou16_audio_debug_address : out unsigned(15 downto 0);
        ou8_audio_debug_data : out unsigned(7 downto 0);
        i_sound_command_read : in std_logic;
        o_sound_command_write : out std_logic;
        ou8_sound_command : out unsigned(7 downto 0);
        o_sound_pending : out std_logic;
        ou16_video_flags : out unsigned(15 downto 0);
        ou9_scroll0_y : out unsigned(8 downto 0);
        ou9_scroll0_x : out unsigned(8 downto 0);
        ou9_scroll1_y : out unsigned(8 downto 0);
        ou9_scroll1_x : out unsigned(8 downto 0);
        ou6_sprite_count : out unsigned(5 downto 0);
        ou6_sprite_priority : out unsigned(5 downto 0);
        ou4_gga_selected : out unsigned(3 downto 0);
        iu4_gga_view_address : in unsigned(3 downto 0);
        ou8_gga_view_data : out unsigned(7 downto 0);
        o_gga_write : out std_logic;
        ou4_gga_write_address : out unsigned(3 downto 0);
        ou8_gga_write_data : out unsigned(7 downto 0);
        o_cpu_request : out std_logic;
        o_cpu_request_write : out std_logic;
        ou24_cpu_request_address : out unsigned(23 downto 0);
        ou16_cpu_request_data : out unsigned(15 downto 0);
        ou2_cpu_request_bytes : out unsigned(1 downto 0);
        i_download : in std_logic;
        i_word_valid : in std_logic;
        o_word_ready : out std_logic;
        iu27_word_byte_address : in unsigned(26 downto 0);
        iu16_word_data : in unsigned(15 downto 0);
        o_image_valid : out std_logic;
        o_error : out std_logic;
        o_done : out std_logic;
        ou27_bytes_loaded : out unsigned(26 downto 0);
        iou16_sdram_data : inout unsigned(15 downto 0);
        ou13_sdram_address : out unsigned(12 downto 0);
        ou2_sdram_bank : out unsigned(1 downto 0);
        ou2_sdram_byte_mask : out unsigned(1 downto 0);
        o_sdram_chip_select : out std_logic;
        o_sdram_write_n : out std_logic;
        o_sdram_row_n : out std_logic;
        o_sdram_column_n : out std_logic;
        o_sdram_clock_enable : out std_logic;
        o_ready : out std_logic;
        o_loading : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_system is
    signal s_board_reset, s_download_reset, s_loading, s_rom_ready, s_rom_idle : std_logic;
    signal s_loader_request, s_loader_ready, s_loader_valid : std_logic;
    signal su27_loader_address : unsigned(26 downto 0);
    signal su16_loader_data : unsigned(15 downto 0);
    signal su2_loader_bytes : unsigned(1 downto 0);
    signal s_sprite_request, s_sprite_valid, s_tile_request, s_tile_valid, s_tile_foreground : std_logic;
    signal su17_sprite_address, su17_tile_address : unsigned(16 downto 0);
    signal su32_sprite_data, su32_tile_data : unsigned(31 downto 0);
    signal s_cpu_rom_request, s_cpu_rom_valid : std_logic;
    signal su18_cpu_rom_address : unsigned(17 downto 0);
    signal su16_cpu_rom_data : unsigned(15 downto 0);
    signal s_main_paused, s_audio_paused, s_sound_pending, s_sound_command_read : std_logic;
    signal su8_sound_command : unsigned(7 downto 0);
    signal s_fm_sample_marker : std_logic;
    signal su16_fm_left, su16_fm_right : unsigned(15 downto 0);
    signal su9_sample_pcm : unsigned(8 downto 0);
    signal s_fm_primed, s_fm_valid : std_logic := '0';
    signal su16_left_mix, su16_right_mix : unsigned(15 downto 0);
    signal s_audio_request, s_audio_ready, s_audio_valid, s_sample_request, s_sample_valid : std_logic;
    signal su16_audio_address : unsigned(15 downto 0);
    signal su18_sample_address : unsigned(17 downto 0);
    signal su8_audio_data, su8_sample_data : unsigned(7 downto 0);
    signal s_board_idle, s_maintenance_pause : std_logic;
begin
    ou16_left_pcm <= su16_fm_left;
    ou16_right_pcm <= su16_fm_right;
    ou9_adpcm_pcm <= su9_sample_pcm;
    o_audio_sample_marker <= s_fm_sample_marker;
    o_paused <= s_main_paused and s_audio_paused;
    ou8_sound_command <= su8_sound_command;
    o_sound_pending <= s_sound_pending;
    o_maintenance_pause <= s_maintenance_pause;
    s_board_reset <= i_initialize or i_game_reset or s_download_reset or not s_rom_ready;
    o_ready <= not s_board_reset;
    o_loading <= s_loading;
    board : entity work.rabbitpunch_board
        generic map (
            EXTERNAL_PHASE_ENABLE => EXTERNAL_PHASE_ENABLE
        )
        port map (
            i_clk => i_clk,
            i_main_phase_enable => i_main_phase_enable,
            i_initialize => i_initialize or s_download_reset,
            i_reset => s_board_reset,
            i_pause => i_pause,
            o_paused => s_main_paused,
            i_maintenance_initialize => i_maintenance_initialize,
            i_maintenance_access => i_maintenance_access,
            i_maintenance_valid => i_maintenance_valid,
            i_maintenance_write => i_maintenance_write,
            iu14_maintenance_byte_address => iu14_maintenance_byte_address,
            iu8_maintenance_data => iu8_maintenance_data,
            o_maintenance_ready => o_maintenance_ready,
            o_maintenance_response_valid => o_maintenance_response_valid,
            ou8_maintenance_response_data => ou8_maintenance_response_data,
            o_maintenance_pause => s_maintenance_pause,
            i_maintenance_permitted => s_audio_paused,
            o_transport_idle => s_board_idle,
            i_vblank_start => i_vblank_start,
            i_half_frame => i_half_frame,
            i_line_valid => i_line_valid,
            o_line_ready => o_line_ready,
            i_render_bank => i_render_bank,
            iu9_line_y => iu9_line_y,
            o_line_done => o_line_done,
            o_sprite_rom_request => s_sprite_request,
            ou17_sprite_rom_word_address => su17_sprite_address,
            i_sprite_rom_response_valid => s_sprite_valid,
            iu32_sprite_rom_response_data => su32_sprite_data,
            o_tile_rom_request => s_tile_request,
            ou17_tile_rom_word_address => su17_tile_address,
            o_tile_rom_foreground => s_tile_foreground,
            i_tile_rom_response_valid => s_tile_valid,
            iu32_tile_rom_response_data => su32_tile_data,
            i_pixel_valid => i_pixel_valid,
            o_pixel_ready => o_pixel_ready,
            i_pixel_bank => i_pixel_bank,
            iu9_pixel_x => iu9_pixel_x,
            iu8_pixel_y => iu8_pixel_y,
            o_pixel_valid => o_pixel_valid,
            o_pixel_error => o_pixel_error,
            ou9_pixel_x => ou9_pixel_x,
            ou8_pixel_y => ou8_pixel_y,
            ou8_red => ou8_red,
            ou8_green => ou8_green,
            ou8_blue => ou8_blue,
            o_rom_request => s_cpu_rom_request,
            ou18_rom_byte_address => su18_cpu_rom_address,
            i_rom_response_valid => s_cpu_rom_valid,
            iu16_rom_response_data => su16_cpu_rom_data,
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data,
            iu8_player1 => iu8_player1,
            iu8_player2 => iu8_player2,
            iu8_service => iu8_service,
            iu16_dips => iu16_dips,
            i_sound_command_read => i_sound_command_read or s_sound_command_read,
            o_sound_command_write => o_sound_command_write,
            ou8_sound_command => su8_sound_command,
            o_sound_pending => s_sound_pending,
            ou16_video_flags => ou16_video_flags,
            ou9_scroll0_y => ou9_scroll0_y,
            ou9_scroll0_x => ou9_scroll0_x,
            ou9_scroll1_y => ou9_scroll1_y,
            ou9_scroll1_x => ou9_scroll1_x,
            ou6_sprite_count => ou6_sprite_count,
            ou6_sprite_priority => ou6_sprite_priority,
            ou4_gga_selected => ou4_gga_selected,
            iu4_gga_view_address => iu4_gga_view_address,
            ou8_gga_view_data => ou8_gga_view_data,
            o_gga_write => o_gga_write,
            ou4_gga_write_address => ou4_gga_write_address,
            ou8_gga_write_data => ou8_gga_write_data,
            o_cpu_request => o_cpu_request,
            o_cpu_request_write => o_cpu_request_write,
            ou24_cpu_request_address => ou24_cpu_request_address,
            ou16_cpu_request_data => ou16_cpu_request_data,
            ou2_cpu_request_bytes => ou2_cpu_request_bytes
        );
    -- JT51's rolling accumulator needs a complete sample period after reset.
    -- Keep FM silent through the first marker until the next period completes.
    su16_left_mix <= su16_fm_left when s_fm_valid = '1' else (others => '0');
    su16_right_mix <= su16_fm_right when s_fm_valid = '1' else (others => '0');
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (s_board_reset = '1') then
                s_fm_primed <= '0';
                s_fm_valid <= '0';
            elsif (s_fm_sample_marker = '1') then
                s_fm_primed <= '1';
                if (s_fm_primed = '1') then
                    s_fm_valid <= '1';
                end if;
            end if;
        end if;
    end process;
    mixer : entity work.rabbitpunch_audio_mixer
        port map (
            i_clk => i_clk,
            i_reset => s_board_reset,
            iu16_left_pcm => su16_left_mix,
            iu16_right_pcm => su16_right_mix,
            iu9_adpcm_pcm => su9_sample_pcm,
            ou16_mono_pcm => ou16_mono_pcm
        );
    audio : entity work.rabbitpunch_audio
        port map (
            i_clk => i_clk,
            i_reset => s_board_reset,
            i_cpu_enable => i_sound_cpu_enable,
            i_ym_enable => i_ym_enable,
            i_ym_half_enable => i_ym_half_enable,
            i_adpcm_enable => i_adpcm_enable,
            i_pause => i_pause or s_maintenance_pause,
            o_paused => s_audio_paused,
            iu8_command => su8_sound_command,
            i_command_pending => s_sound_pending,
            o_command_read => s_sound_command_read,
            o_rom_request => s_audio_request,
            ou16_rom_address => su16_audio_address,
            i_rom_ready => s_audio_ready,
            i_rom_response_valid => s_audio_valid,
            iu8_rom_response_data => su8_audio_data,
            o_adpcm_rom_request => s_sample_request,
            ou18_adpcm_rom_address => su18_sample_address,
            i_adpcm_rom_valid => s_sample_valid,
            iu8_adpcm_rom_data => su8_sample_data,
            ou9_adpcm_pcm => su9_sample_pcm,
            o_adpcm_busy => o_adpcm_busy,
            ou16_left_pcm => su16_fm_left,
            ou16_right_pcm => su16_fm_right,
            o_sample_marker => s_fm_sample_marker,
            i_view_enable => i_audio_view_enable,
            iu11_view_address => iu11_audio_view_address,
            ou8_view_data => ou8_audio_view_data,
            o_debug_request => o_audio_debug_request,
            o_debug_write => o_audio_debug_write,
            ou16_debug_address => ou16_audio_debug_address,
            ou8_debug_data => ou8_audio_debug_data
        );
    roms : entity work.rabbitpunch_roms
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            o_ready => s_rom_ready,
            o_idle => s_rom_idle,
            i_loading => s_loading,
            i_loader_request => s_loader_request,
            o_loader_ready => s_loader_ready,
            iu27_loader_byte_address => su27_loader_address,
            iu16_loader_data => su16_loader_data,
            iu2_loader_bytes => su2_loader_bytes,
            o_loader_response_valid => s_loader_valid,
            i_sprite_request => s_sprite_request,
            iu17_sprite_word_address => su17_sprite_address,
            o_sprite_response_valid => s_sprite_valid,
            ou32_sprite_response_data => su32_sprite_data,
            i_tile_request => s_tile_request,
            iu17_tile_word_address => su17_tile_address,
            i_tile_foreground => s_tile_foreground,
            o_tile_response_valid => s_tile_valid,
            ou32_tile_response_data => su32_tile_data,
            i_cpu_request => s_cpu_rom_request,
            iu18_cpu_byte_address => su18_cpu_rom_address,
            o_cpu_response_valid => s_cpu_rom_valid,
            ou16_cpu_response_data => su16_cpu_rom_data,
            i_audio_request => s_audio_request,
            o_audio_ready => s_audio_ready,
            iu16_audio_byte_address => su16_audio_address,
            o_audio_response_valid => s_audio_valid,
            ou8_audio_response_data => su8_audio_data,
            i_sample_request => s_sample_request,
            iu18_sample_byte_address => su18_sample_address,
            o_sample_valid => s_sample_valid,
            ou8_sample_data => su8_sample_data,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => ou13_sdram_address,
            ou2_sdram_bank => ou2_sdram_bank,
            ou2_sdram_byte_mask => ou2_sdram_byte_mask,
            o_sdram_chip_select => o_sdram_chip_select,
            o_sdram_write_n => o_sdram_write_n,
            o_sdram_row_n => o_sdram_row_n,
            o_sdram_column_n => o_sdram_column_n,
            o_sdram_clock_enable => o_sdram_clock_enable
        );
    download : entity work.rabbitpunch_download
        generic map (sint_IMAGE_BYTES => sint_IMAGE_BYTES)
        port map (
            i_clk => i_clk,
            i_download => i_download,
            i_word_valid => i_word_valid,
            o_word_ready => o_word_ready,
            iu27_word_byte_address => iu27_word_byte_address,
            iu16_word_data => iu16_word_data,
            i_transport_idle => s_rom_idle and s_board_idle,
            i_loader_ready => s_loader_ready,
            i_loader_response_valid => s_loader_valid,
            o_loading => s_loading,
            o_loader_request => s_loader_request,
            ou27_loader_byte_address => su27_loader_address,
            ou16_loader_data => su16_loader_data,
            ou2_loader_bytes => su2_loader_bytes,
            o_game_reset => s_download_reset,
            o_image_valid => o_image_valid,
            o_error => o_error,
            o_done => o_done,
            ou27_bytes_loaded => ou27_bytes_loaded
        );
end architecture;
