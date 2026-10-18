-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_config.all;

-- Continuous single-clock machine. PLL and physical HPS/DDR ownership remain
-- at the framework boundary; gameplay reset never resets raster or enables.
entity rabbitpunch_machine is
    generic (
        GINT_SDRAM_READ_CAPTURE_ADJUST : natural range 0 to 2 := 0;
        GINT_IMAGE_BYTES : positive := CINT_ROM_IMAGE_SIZE;
        GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000"
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
        i_host_upload : in std_logic := '0';
        o_host_upload_request : out std_logic;
        ou8_host_upload_data : out unsigned(7 downto 0);
        ou16_host_menu_mask : out unsigned(15 downto 0);
        o_hiscore_enabled : out std_logic;
        o_hiscore_config_error : out std_logic;
        o_hiscore_initialized : out std_logic;
        o_hiscore_saved_valid : out std_logic;
        o_hiscore_dirty : out std_logic;
        iu16_host_index : in unsigned(15 downto 0);
        i_host_write : in std_logic;
        iu27_host_byte_address : in unsigned(26 downto 0);
        iu8_host_data : in unsigned(7 downto 0);
        o_host_wait : out std_logic;
        o_downloading : out std_logic;
        o_ddr_owner : out std_logic;
        o_pause_request : out std_logic;
        o_user_paused : out std_logic;
        i_maintenance_access : in std_logic := '0';
        i_maintenance_valid : in std_logic := '0';
        i_maintenance_write : in std_logic := '0';
        iu14_maintenance_byte_address : in unsigned(13 downto 0) := (others => '0');
        iu8_maintenance_data : in unsigned(7 downto 0) := (others => '0');
        o_maintenance_ready : out std_logic;
        o_maintenance_response_valid : out std_logic;
        ou8_maintenance_response_data : out unsigned(7 downto 0);
        o_maintenance_pause : out std_logic;
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
        i_view_enable : in std_logic;
        iu5_view_target : in target_t;
        iu15_view_word_address : in unsigned(14 downto 0);
        o_view_valid : out std_logic;
        ou16_view_data : out unsigned(15 downto 0);
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
        o_loading : out std_logic;
        o_pixel_enable : out std_logic;
        o_active : out std_logic;
        o_hsync : out std_logic;
        o_vsync : out std_logic;
        o_hblank : out std_logic;
        o_vblank : out std_logic;
        ou9_output_x : out unsigned(8 downto 0);
        ou8_output_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        ou9_horizontal_position : out unsigned(8 downto 0);
        ou9_vertical_position : out unsigned(8 downto 0);
        o_scanout_armed : out std_logic;
        o_scanout_underflow : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_machine is
    signal s_main_phase_enable, s_sound_enable, s_ym_enable, s_ym_half_enable, s_adpcm_enable : std_logic;
    signal s_vblank_start, s_half_frame, s_line_valid, s_line_ready, s_render_bank, s_line_done : std_logic;
    signal s_pixel_request, s_pixel_ready, s_pixel_bank, s_rgb_valid, s_rgb_error, s_ready : std_logic;
    signal su9_line_y, su9_pixel_x, su9_rgb_x : unsigned(8 downto 0);
    signal su8_pixel_y, su8_rgb_y, su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal su9_source_line_y, su9_source_pixel_x, su9_source_rgb_x : unsigned(8 downto 0);
    signal su8_source_pixel_y, su8_source_rgb_y : unsigned(7 downto 0);
    signal su16_video_flags : unsigned(15 downto 0);
    signal s_request_flip : std_logic;
begin
    o_ready <= s_ready;
    ou16_video_flags <= su16_video_flags;
    s_request_flip <= su16_video_flags(12) xor iu128_status(65);
    view_flip : entity work.rabbitpunch_view_flip
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_game_ready => s_ready,
            i_request_flip => s_request_flip,
            i_frame_prepare => s_vblank_start,
            i_line_valid => s_line_valid,
            i_line_ready => s_line_ready,
            i_line_done => s_line_done,
            i_pixel_valid => s_pixel_request,
            i_pixel_ready => s_pixel_ready,
            i_rgb_valid => s_rgb_valid,
            iu9_line_y => su9_line_y,
            ou9_source_line_y => su9_source_line_y,
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            ou9_source_pixel_x => su9_source_pixel_x,
            ou8_source_pixel_y => su8_source_pixel_y,
            iu9_source_rgb_x => su9_source_rgb_x,
            iu8_source_rgb_y => su8_source_rgb_y,
            ou9_rgb_x => su9_rgb_x,
            ou8_rgb_y => su8_rgb_y,
            o_applied_flip => open
        );
    platform : entity work.rabbitpunch_platform
        generic map (
            GINT_SDRAM_READ_CAPTURE_ADJUST => GINT_SDRAM_READ_CAPTURE_ADJUST,
            GINT_IMAGE_BYTES => GINT_IMAGE_BYTES,
            GU16_DIP_DEFAULT => GU16_DIP_DEFAULT,
            GBOOL_EXTERNAL_PHASE_ENABLE => true
        )
        port map (
            i_clk => i_clk,
            i_main_phase_enable => s_main_phase_enable,
            i_initialize => i_initialize,
            i_framework_reset => i_framework_reset,
            iu128_status => iu128_status,
            iu2_host_buttons => iu2_host_buttons,
            iu32_joystick0 => iu32_joystick0,
            iu32_joystick1 => iu32_joystick1,
            iu11_key_event => iu11_key_event,
            i_osd_open => i_osd_open,
            i_debug_pause => i_debug_pause,
            i_state_pause => i_state_pause,
            i_host_download => i_host_download,
            i_host_upload => i_host_upload,
            o_host_upload_request => o_host_upload_request,
            ou8_host_upload_data => ou8_host_upload_data,
            ou16_host_menu_mask => ou16_host_menu_mask,
            o_hiscore_enabled => o_hiscore_enabled,
            o_hiscore_config_error => o_hiscore_config_error,
            o_hiscore_initialized => o_hiscore_initialized,
            o_hiscore_saved_valid => o_hiscore_saved_valid,
            o_hiscore_dirty => o_hiscore_dirty,
            iu16_host_index => iu16_host_index,
            i_host_write => i_host_write,
            iu27_host_byte_address => iu27_host_byte_address,
            iu8_host_data => iu8_host_data,
            o_host_wait => o_host_wait,
            o_downloading => o_downloading,
            o_ddr_owner => o_ddr_owner,
            o_pause_request => o_pause_request,
            o_user_paused => o_user_paused,
            i_maintenance_access => i_maintenance_access,
            i_maintenance_valid => i_maintenance_valid,
            i_maintenance_write => i_maintenance_write,
            iu14_maintenance_byte_address => iu14_maintenance_byte_address,
            iu8_maintenance_data => iu8_maintenance_data,
            o_maintenance_ready => o_maintenance_ready,
            o_maintenance_response_valid => o_maintenance_response_valid,
            ou8_maintenance_response_data => ou8_maintenance_response_data,
            o_maintenance_pause => o_maintenance_pause,
            ou8_player1 => ou8_player1,
            ou8_player2 => ou8_player2,
            ou8_service => ou8_service,
            ou16_dips => ou16_dips,
            o_ddr_mode => o_ddr_mode,
            i_ddr_busy => i_ddr_busy,
            ou8_ddr_burst_count => ou8_ddr_burst_count,
            ou29_ddr_word_address => ou29_ddr_word_address,
            iu64_ddr_read_data => iu64_ddr_read_data,
            i_ddr_read_valid => i_ddr_read_valid,
            o_ddr_read => o_ddr_read,
            ou64_ddr_write_data => ou64_ddr_write_data,
            ou8_ddr_byte_enables => ou8_ddr_byte_enables,
            o_ddr_write => o_ddr_write,
            o_paused => o_paused,
            i_vblank_start => s_vblank_start,
            i_half_frame => s_half_frame,
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            i_render_bank => s_render_bank,
            iu9_line_y => su9_source_line_y,
            o_line_done => s_line_done,
            i_pixel_valid => s_pixel_request,
            o_pixel_ready => s_pixel_ready,
            i_pixel_bank => s_pixel_bank,
            iu9_pixel_x => su9_source_pixel_x,
            iu8_pixel_y => su8_source_pixel_y,
            o_pixel_valid => s_rgb_valid,
            o_pixel_error => s_rgb_error,
            ou9_pixel_x => su9_source_rgb_x,
            ou8_pixel_y => su8_source_rgb_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue,
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data,
            i_sound_cpu_enable => s_sound_enable,
            i_ym_enable => s_ym_enable,
            i_ym_half_enable => s_ym_half_enable,
            i_adpcm_enable => s_adpcm_enable,
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
            o_sound_command_write => o_sound_command_write,
            ou8_sound_command => ou8_sound_command,
            o_sound_pending => o_sound_pending,
            ou16_video_flags => su16_video_flags,
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
            o_image_valid => o_image_valid,
            o_error => o_error,
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
            o_ready => s_ready,
            o_loading => o_loading
        );
    scanout : entity work.rabbitpunch_scanout
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_game_ready => s_ready,
            o_main_phase_enable => s_main_phase_enable,
            o_sound_cpu_enable => s_sound_enable,
            o_ym_enable => s_ym_enable,
            o_ym_half_enable => s_ym_half_enable,
            o_adpcm_enable => s_adpcm_enable,
            o_vblank_start => s_vblank_start,
            o_half_frame => s_half_frame,
            o_line_valid => s_line_valid,
            i_line_ready => s_line_ready,
            o_render_bank => s_render_bank,
            ou9_line_y => su9_line_y,
            i_line_done => s_line_done,
            o_pixel_valid => s_pixel_request,
            i_pixel_ready => s_pixel_ready,
            o_pixel_bank => s_pixel_bank,
            ou9_pixel_x => su9_pixel_x,
            ou8_pixel_y => su8_pixel_y,
            i_rgb_valid => s_rgb_valid,
            i_rgb_error => s_rgb_error,
            iu9_rgb_x => su9_rgb_x,
            iu8_rgb_y => su8_rgb_y,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            o_pixel_enable => o_pixel_enable,
            o_active => o_active,
            o_hsync => o_hsync,
            o_vsync => o_vsync,
            o_hblank => o_hblank,
            o_vblank => o_vblank,
            ou9_output_x => ou9_output_x,
            ou8_output_y => ou8_output_y,
            ou8_red => ou8_red,
            ou8_green => ou8_green,
            ou8_blue => ou8_blue,
            ou9_horizontal_position => ou9_horizontal_position,
            ou9_vertical_position => ou9_vertical_position,
            o_armed => o_scanout_armed,
            o_underflow => o_scanout_underflow
        );
end architecture;
