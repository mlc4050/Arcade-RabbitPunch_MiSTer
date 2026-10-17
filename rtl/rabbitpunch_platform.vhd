-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- Logical MiSTer-facing platform. Native hps_io is an external boundary;
-- physical PLL/raster/scanout and the shared DDR ownership mux remain external.
-- i_initialize is cold transport initialization, never the gameplay reset.
entity rabbitpunch_platform is
    generic (
        sint_IMAGE_BYTES : positive := ROM_IMAGE_SIZE;
        DIP_DEFAULT : unsigned(15 downto 0) := x"0000"
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_framework_reset : in std_logic;
        iu128_status : in unsigned(127 downto 0);
        iu2_host_buttons : in unsigned(1 downto 0);
        iu32_joystick0 : in unsigned(31 downto 0);
        iu32_joystick1 : in unsigned(31 downto 0);
        iu11_key_event : in unsigned(10 downto 0);
        i_osd_open : in std_logic;
        i_debug_pause : in std_logic := '0';
        i_state_pause : in std_logic := '0';
        i_host_download : in std_logic;
        iu16_host_index : in unsigned(15 downto 0);
        i_host_write : in std_logic;
        iu27_host_byte_address : in unsigned(26 downto 0);
        iu8_host_data : in unsigned(7 downto 0);
        o_host_wait : out std_logic;
        o_downloading : out std_logic;
        o_ddr_owner : out std_logic;
        o_pause_request : out std_logic;
        o_user_paused : out std_logic;
        ou8_player1 : out unsigned(7 downto 0);
        ou8_player2 : out unsigned(7 downto 0);
        ou8_service : out unsigned(7 downto 0);
        ou16_dips : out unsigned(15 downto 0);
        o_ddr_mode : out std_logic;
        i_ddr_busy : in std_logic;
        ou8_ddr_burst_count : out unsigned(7 downto 0);
        ou29_ddr_word_address : out unsigned(28 downto 0);
        iu64_ddr_read_data : in unsigned(63 downto 0);
        i_ddr_read_valid : in std_logic;
        o_ddr_read : out std_logic;
        ou64_ddr_write_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0);
        o_ddr_write : out std_logic;
        o_paused : out std_logic;
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

architecture rtl of rabbitpunch_platform is
    signal s_system_loading : std_logic;
    signal s_game_reset, s_controls_reset, s_downloading, s_ddr_mode : std_logic;
    signal s_frontend_error, s_system_error, s_word_valid, s_word_ready, s_pause_request : std_logic;
    signal su27_word_address : unsigned(26 downto 0);
    signal su16_word_data, su16_dips : unsigned(15 downto 0);
    signal su8_player1, su8_player2, su8_service : unsigned(7 downto 0);
begin
    s_game_reset <= i_framework_reset or iu128_status(0) or iu2_host_buttons(1) or s_frontend_error or s_system_error;
    s_controls_reset <= s_game_reset or s_downloading;
    o_downloading <= s_downloading;
    o_ddr_mode <= s_ddr_mode;
    o_ddr_owner <= s_downloading and s_ddr_mode;
    o_loading <= s_system_loading;
    o_error <= s_frontend_error or s_system_error;
    o_pause_request <= s_pause_request;
    ou8_player1 <= su8_player1;
    ou8_player2 <= su8_player2;
    ou8_service <= su8_service;
    ou16_dips <= su16_dips;
    controls : entity work.rabbitpunch_controls
        generic map (DIP_DEFAULT => DIP_DEFAULT)
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_game_reset => s_controls_reset,
            i_osd_open => i_osd_open,
            i_pause_on_osd => iu128_status(2),
            i_debug_pause => i_debug_pause or iu128_status(1),
            i_state_pause => i_state_pause,
            iu32_joystick0 => iu32_joystick0,
            iu32_joystick1 => iu32_joystick1,
            iu11_key_event => iu11_key_event,
            i_file_write => i_host_write,
            iu16_file_index => iu16_host_index,
            iu27_file_byte_address => iu27_host_byte_address,
            iu8_file_data => iu8_host_data,
            ou8_player1 => su8_player1,
            ou8_player2 => su8_player2,
            ou8_service => su8_service,
            ou16_dips => su16_dips,
            o_pause_request => s_pause_request,
            o_user_paused => o_user_paused
        );
    load_frontend : entity work.rabbitpunch_load_frontend
        generic map (sint_IMAGE_BYTES => sint_IMAGE_BYTES)
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_framework_reset => i_framework_reset,
            i_start_ready => not s_system_loading,
            i_host_download => i_host_download,
            iu16_host_index => iu16_host_index,
            i_host_write => i_host_write,
            iu27_host_byte_address => iu27_host_byte_address,
            iu8_host_data => iu8_host_data,
            o_host_wait => o_host_wait,
            o_download_active => s_downloading,
            o_done => open,
            o_error => s_frontend_error,
            o_ddr_mode => s_ddr_mode,
            o_word_valid => s_word_valid,
            i_word_ready => s_word_ready,
            ou27_word_byte_address => su27_word_address,
            ou16_word_data => su16_word_data,
            i_ddr_busy => i_ddr_busy,
            ou8_ddr_burst_count => ou8_ddr_burst_count,
            ou29_ddr_word_address => ou29_ddr_word_address,
            iu64_ddr_read_data => iu64_ddr_read_data,
            i_ddr_read_valid => i_ddr_read_valid,
            o_ddr_read => o_ddr_read,
            ou64_ddr_write_data => ou64_ddr_write_data,
            ou8_ddr_byte_enables => ou8_ddr_byte_enables,
            o_ddr_write => o_ddr_write
        );
    system : entity work.rabbitpunch_system
        generic map (sint_IMAGE_BYTES => sint_IMAGE_BYTES)
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_game_reset => s_game_reset,
            i_pause => s_pause_request,
            o_paused => o_paused,
            i_vblank_start => i_vblank_start,
            i_half_frame => i_half_frame,
            i_line_valid => i_line_valid,
            o_line_ready => o_line_ready,
            i_render_bank => i_render_bank,
            iu9_line_y => iu9_line_y,
            o_line_done => o_line_done,
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
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data,
            iu8_player1 => su8_player1,
            iu8_player2 => su8_player2,
            iu8_service => su8_service,
            iu16_dips => su16_dips,
            i_sound_cpu_enable => i_sound_cpu_enable,
            i_ym_enable => i_ym_enable,
            i_ym_half_enable => i_ym_half_enable,
            i_adpcm_enable => i_adpcm_enable,
            ou16_left_pcm => ou16_left_pcm,
            ou16_right_pcm => ou16_right_pcm,
            ou9_adpcm_pcm => ou9_adpcm_pcm,
            ou16_mono_pcm => ou16_mono_pcm,
            o_audio_sample_marker => o_audio_sample_marker,
            o_adpcm_busy => o_adpcm_busy,
            i_audio_view_enable => i_audio_view_enable,
            iu11_audio_view_address => iu11_audio_view_address,
            ou8_audio_view_data => ou8_audio_view_data,
            o_audio_debug_request => o_audio_debug_request,
            o_audio_debug_write => o_audio_debug_write,
            ou16_audio_debug_address => ou16_audio_debug_address,
            ou8_audio_debug_data => ou8_audio_debug_data,
            i_sound_command_read => '0',
            o_sound_command_write => o_sound_command_write,
            ou8_sound_command => ou8_sound_command,
            o_sound_pending => o_sound_pending,
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
            ou2_cpu_request_bytes => ou2_cpu_request_bytes,
            i_download => s_downloading,
            i_word_valid => s_word_valid,
            o_word_ready => s_word_ready,
            iu27_word_byte_address => su27_word_address,
            iu16_word_data => su16_word_data,
            o_image_valid => o_image_valid,
            o_error => s_system_error,
            o_done => o_done,
            ou27_bytes_loaded => ou27_bytes_loaded,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => ou13_sdram_address,
            ou2_sdram_bank => ou2_sdram_bank,
            ou2_sdram_byte_mask => ou2_sdram_byte_mask,
            o_sdram_chip_select => o_sdram_chip_select,
            o_sdram_write_n => o_sdram_write_n,
            o_sdram_row_n => o_sdram_row_n,
            o_sdram_column_n => o_sdram_column_n,
            o_sdram_clock_enable => o_sdram_clock_enable,
            o_ready => o_ready,
            o_loading => s_system_loading
        );
end architecture;
