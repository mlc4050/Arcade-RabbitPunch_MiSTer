-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_config.all;

-- Evaluation launch/capture registers; external SDRAM pins stay direct.
entity clocked_machine_check is
    port (
        i_reference_clk : in std_logic;
        o_sdram_clk : out std_logic;
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

architecture rtl of clocked_machine_check is
    signal s_system_clk : std_logic;
    signal s_framework_reset_launch : std_logic;
    signal su128_status_launch : unsigned(127 downto 0);
    signal su2_host_buttons_launch : unsigned(1 downto 0);
    signal su32_joystick0_launch : unsigned(31 downto 0);
    signal su32_joystick1_launch : unsigned(31 downto 0);
    signal su11_key_event_launch : unsigned(10 downto 0);
    signal s_osd_open_launch : std_logic;
    signal s_debug_pause_launch : std_logic;
    signal s_state_pause_launch : std_logic;
    signal s_host_download_launch : std_logic;
    signal s_host_upload_launch : std_logic;
    signal s_host_upload_request_capture : std_logic;
    signal su8_host_upload_data_capture : unsigned(7 downto 0);
    signal su16_host_menu_mask_capture : unsigned(15 downto 0);
    signal s_hiscore_enabled_capture : std_logic;
    signal s_hiscore_config_error_capture : std_logic;
    signal s_hiscore_initialized_capture : std_logic;
    signal s_hiscore_saved_valid_capture : std_logic;
    signal s_hiscore_dirty_capture : std_logic;
    signal su16_host_index_launch : unsigned(15 downto 0);
    signal s_host_write_launch : std_logic;
    signal su27_host_byte_address_launch : unsigned(26 downto 0);
    signal su8_host_data_launch : unsigned(7 downto 0);
    signal s_host_wait_capture : std_logic;
    signal s_downloading_capture : std_logic;
    signal s_ddr_owner_capture : std_logic;
    signal s_pause_request_capture : std_logic;
    signal s_user_paused_capture : std_logic;
    signal s_maintenance_access_launch : std_logic;
    signal s_maintenance_valid_launch : std_logic;
    signal s_maintenance_write_launch : std_logic;
    signal su14_maintenance_byte_address_launch : unsigned(13 downto 0);
    signal su8_maintenance_data_launch : unsigned(7 downto 0);
    signal s_maintenance_ready_capture : std_logic;
    signal s_maintenance_response_valid_capture : std_logic;
    signal su8_maintenance_response_data_capture : unsigned(7 downto 0);
    signal s_maintenance_pause_capture : std_logic;
    signal su8_player1_capture : unsigned(7 downto 0);
    signal su8_player2_capture : unsigned(7 downto 0);
    signal su8_service_capture : unsigned(7 downto 0);
    signal su16_dips_capture : unsigned(15 downto 0);
    signal s_ddr_mode_capture : std_logic;
    signal s_ddr_busy_launch : std_logic;
    signal su8_ddr_burst_count_capture : unsigned(7 downto 0);
    signal su29_ddr_word_address_capture : unsigned(28 downto 0);
    signal su64_ddr_read_data_launch : unsigned(63 downto 0);
    signal s_ddr_read_valid_launch : std_logic;
    signal s_ddr_read_capture : std_logic;
    signal su64_ddr_write_data_capture : unsigned(63 downto 0);
    signal su8_ddr_byte_enables_capture : unsigned(7 downto 0);
    signal s_ddr_write_capture : std_logic;
    signal s_paused_capture : std_logic;
    signal s_view_enable_launch : std_logic;
    signal su5_view_target_launch : target_t;
    signal su15_view_word_address_launch : unsigned(14 downto 0);
    signal s_view_valid_capture : std_logic;
    signal su16_view_data_capture : unsigned(15 downto 0);
    signal su16_left_pcm_capture : unsigned(15 downto 0);
    signal su16_right_pcm_capture : unsigned(15 downto 0);
    signal su9_adpcm_pcm_capture : unsigned(8 downto 0);
    signal su16_mono_pcm_capture : unsigned(15 downto 0);
    signal s_audio_sample_marker_capture : std_logic;
    signal s_adpcm_busy_capture : std_logic;
    signal s_audio_view_enable_launch : std_logic;
    signal su11_audio_view_address_launch : unsigned(10 downto 0);
    signal su8_audio_view_data_capture : unsigned(7 downto 0);
    signal s_audio_debug_request_capture : std_logic;
    signal s_audio_debug_write_capture : std_logic;
    signal su16_audio_debug_address_capture : unsigned(15 downto 0);
    signal su8_audio_debug_data_capture : unsigned(7 downto 0);
    signal s_sound_command_write_capture : std_logic;
    signal su8_sound_command_capture : unsigned(7 downto 0);
    signal s_sound_pending_capture : std_logic;
    signal su16_video_flags_capture : unsigned(15 downto 0);
    signal su9_scroll0_y_capture : unsigned(8 downto 0);
    signal su9_scroll0_x_capture : unsigned(8 downto 0);
    signal su9_scroll1_y_capture : unsigned(8 downto 0);
    signal su9_scroll1_x_capture : unsigned(8 downto 0);
    signal su6_sprite_count_capture : unsigned(5 downto 0);
    signal su6_sprite_priority_capture : unsigned(5 downto 0);
    signal su4_gga_selected_capture : unsigned(3 downto 0);
    signal su4_gga_view_address_launch : unsigned(3 downto 0);
    signal su8_gga_view_data_capture : unsigned(7 downto 0);
    signal s_gga_write_capture : std_logic;
    signal su4_gga_write_address_capture : unsigned(3 downto 0);
    signal su8_gga_write_data_capture : unsigned(7 downto 0);
    signal s_cpu_request_capture : std_logic;
    signal s_cpu_request_write_capture : std_logic;
    signal su24_cpu_request_address_capture : unsigned(23 downto 0);
    signal su16_cpu_request_data_capture : unsigned(15 downto 0);
    signal su2_cpu_request_bytes_capture : unsigned(1 downto 0);
    signal s_image_valid_capture : std_logic;
    signal s_error_capture : std_logic;
    signal s_done_capture : std_logic;
    signal su27_bytes_loaded_capture : unsigned(26 downto 0);
    signal s_ready_capture : std_logic;
    signal s_loading_capture : std_logic;
    signal s_pixel_enable_capture : std_logic;
    signal s_active_capture : std_logic;
    signal s_hsync_capture : std_logic;
    signal s_vsync_capture : std_logic;
    signal s_hblank_capture : std_logic;
    signal s_vblank_capture : std_logic;
    signal su9_output_x_capture : unsigned(8 downto 0);
    signal su8_output_y_capture : unsigned(7 downto 0);
    signal su8_red_capture : unsigned(7 downto 0);
    signal su8_green_capture : unsigned(7 downto 0);
    signal su8_blue_capture : unsigned(7 downto 0);
    signal su9_horizontal_position_capture : unsigned(8 downto 0);
    signal su9_vertical_position_capture : unsigned(8 downto 0);
    signal s_scanout_armed_capture : std_logic;
    signal s_scanout_underflow_capture : std_logic;
begin
    machine : entity work.rabbitpunch_clocked_machine
        port map (
            i_reference_clk => i_reference_clk,
            o_system_clk => s_system_clk,
            o_sdram_clk => o_sdram_clk,
            o_pll_locked => open,
            i_cold_reset => '0',
            i_framework_reset => s_framework_reset_launch,
            iu128_status => su128_status_launch,
            iu2_host_buttons => su2_host_buttons_launch,
            iu32_joystick0 => su32_joystick0_launch,
            iu32_joystick1 => su32_joystick1_launch,
            iu11_key_event => su11_key_event_launch,
            i_osd_open => s_osd_open_launch,
            i_debug_pause => s_debug_pause_launch,
            i_state_pause => s_state_pause_launch,
            i_host_download => s_host_download_launch,
            i_host_upload => s_host_upload_launch,
            o_host_upload_request => s_host_upload_request_capture,
            ou8_host_upload_data => su8_host_upload_data_capture,
            ou16_host_menu_mask => su16_host_menu_mask_capture,
            o_hiscore_enabled => s_hiscore_enabled_capture,
            o_hiscore_config_error => s_hiscore_config_error_capture,
            o_hiscore_initialized => s_hiscore_initialized_capture,
            o_hiscore_saved_valid => s_hiscore_saved_valid_capture,
            o_hiscore_dirty => s_hiscore_dirty_capture,
            iu16_host_index => su16_host_index_launch,
            i_host_write => s_host_write_launch,
            iu27_host_byte_address => su27_host_byte_address_launch,
            iu8_host_data => su8_host_data_launch,
            o_host_wait => s_host_wait_capture,
            o_downloading => s_downloading_capture,
            o_ddr_owner => s_ddr_owner_capture,
            o_pause_request => s_pause_request_capture,
            o_user_paused => s_user_paused_capture,
            i_maintenance_access => s_maintenance_access_launch,
            i_maintenance_valid => s_maintenance_valid_launch,
            i_maintenance_write => s_maintenance_write_launch,
            iu14_maintenance_byte_address => su14_maintenance_byte_address_launch,
            iu8_maintenance_data => su8_maintenance_data_launch,
            o_maintenance_ready => s_maintenance_ready_capture,
            o_maintenance_response_valid => s_maintenance_response_valid_capture,
            ou8_maintenance_response_data => su8_maintenance_response_data_capture,
            o_maintenance_pause => s_maintenance_pause_capture,
            ou8_player1 => su8_player1_capture,
            ou8_player2 => su8_player2_capture,
            ou8_service => su8_service_capture,
            ou16_dips => su16_dips_capture,
            o_ddr_mode => s_ddr_mode_capture,
            i_ddr_busy => s_ddr_busy_launch,
            ou8_ddr_burst_count => su8_ddr_burst_count_capture,
            ou29_ddr_word_address => su29_ddr_word_address_capture,
            iu64_ddr_read_data => su64_ddr_read_data_launch,
            i_ddr_read_valid => s_ddr_read_valid_launch,
            o_ddr_read => s_ddr_read_capture,
            ou64_ddr_write_data => su64_ddr_write_data_capture,
            ou8_ddr_byte_enables => su8_ddr_byte_enables_capture,
            o_ddr_write => s_ddr_write_capture,
            o_paused => s_paused_capture,
            i_view_enable => s_view_enable_launch,
            iu5_view_target => su5_view_target_launch,
            iu15_view_word_address => su15_view_word_address_launch,
            o_view_valid => s_view_valid_capture,
            ou16_view_data => su16_view_data_capture,
            ou16_left_pcm => su16_left_pcm_capture,
            ou16_right_pcm => su16_right_pcm_capture,
            ou9_adpcm_pcm => su9_adpcm_pcm_capture,
            ou16_mono_pcm => su16_mono_pcm_capture,
            o_audio_sample_marker => s_audio_sample_marker_capture,
            o_adpcm_busy => s_adpcm_busy_capture,
            i_audio_view_enable => s_audio_view_enable_launch,
            iu11_audio_view_address => su11_audio_view_address_launch,
            ou8_audio_view_data => su8_audio_view_data_capture,
            o_audio_debug_request => s_audio_debug_request_capture,
            o_audio_debug_write => s_audio_debug_write_capture,
            ou16_audio_debug_address => su16_audio_debug_address_capture,
            ou8_audio_debug_data => su8_audio_debug_data_capture,
            o_sound_command_write => s_sound_command_write_capture,
            ou8_sound_command => su8_sound_command_capture,
            o_sound_pending => s_sound_pending_capture,
            ou16_video_flags => su16_video_flags_capture,
            ou9_scroll0_y => su9_scroll0_y_capture,
            ou9_scroll0_x => su9_scroll0_x_capture,
            ou9_scroll1_y => su9_scroll1_y_capture,
            ou9_scroll1_x => su9_scroll1_x_capture,
            ou6_sprite_count => su6_sprite_count_capture,
            ou6_sprite_priority => su6_sprite_priority_capture,
            ou4_gga_selected => su4_gga_selected_capture,
            iu4_gga_view_address => su4_gga_view_address_launch,
            ou8_gga_view_data => su8_gga_view_data_capture,
            o_gga_write => s_gga_write_capture,
            ou4_gga_write_address => su4_gga_write_address_capture,
            ou8_gga_write_data => su8_gga_write_data_capture,
            o_cpu_request => s_cpu_request_capture,
            o_cpu_request_write => s_cpu_request_write_capture,
            ou24_cpu_request_address => su24_cpu_request_address_capture,
            ou16_cpu_request_data => su16_cpu_request_data_capture,
            ou2_cpu_request_bytes => su2_cpu_request_bytes_capture,
            o_image_valid => s_image_valid_capture,
            o_error => s_error_capture,
            o_done => s_done_capture,
            ou27_bytes_loaded => su27_bytes_loaded_capture,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => ou13_sdram_address,
            ou2_sdram_bank => ou2_sdram_bank,
            ou2_sdram_byte_mask => ou2_sdram_byte_mask,
            o_sdram_chip_select => o_sdram_chip_select,
            o_sdram_write_n => o_sdram_write_n,
            o_sdram_row_n => o_sdram_row_n,
            o_sdram_column_n => o_sdram_column_n,
            o_sdram_clock_enable => o_sdram_clock_enable,
            o_ready => s_ready_capture,
            o_loading => s_loading_capture,
            o_pixel_enable => s_pixel_enable_capture,
            o_active => s_active_capture,
            o_hsync => s_hsync_capture,
            o_vsync => s_vsync_capture,
            o_hblank => s_hblank_capture,
            o_vblank => s_vblank_capture,
            ou9_output_x => su9_output_x_capture,
            ou8_output_y => su8_output_y_capture,
            ou8_red => su8_red_capture,
            ou8_green => su8_green_capture,
            ou8_blue => su8_blue_capture,
            ou9_horizontal_position => su9_horizontal_position_capture,
            ou9_vertical_position => su9_vertical_position_capture,
            o_scanout_armed => s_scanout_armed_capture,
            o_scanout_underflow => s_scanout_underflow_capture
        );
    registers : process(s_system_clk)
    begin
        if (rising_edge(s_system_clk)) then
            s_framework_reset_launch <= i_framework_reset;
            su128_status_launch <= iu128_status;
            su2_host_buttons_launch <= iu2_host_buttons;
            su32_joystick0_launch <= iu32_joystick0;
            su32_joystick1_launch <= iu32_joystick1;
            su11_key_event_launch <= iu11_key_event;
            s_osd_open_launch <= i_osd_open;
            s_debug_pause_launch <= i_debug_pause;
            s_state_pause_launch <= i_state_pause;
            s_host_download_launch <= i_host_download;
            s_host_upload_launch <= i_host_upload;
            o_host_upload_request <= s_host_upload_request_capture;
            ou8_host_upload_data <= su8_host_upload_data_capture;
            ou16_host_menu_mask <= su16_host_menu_mask_capture;
            o_hiscore_enabled <= s_hiscore_enabled_capture;
            o_hiscore_config_error <= s_hiscore_config_error_capture;
            o_hiscore_initialized <= s_hiscore_initialized_capture;
            o_hiscore_saved_valid <= s_hiscore_saved_valid_capture;
            o_hiscore_dirty <= s_hiscore_dirty_capture;
            su16_host_index_launch <= iu16_host_index;
            s_host_write_launch <= i_host_write;
            su27_host_byte_address_launch <= iu27_host_byte_address;
            su8_host_data_launch <= iu8_host_data;
            o_host_wait <= s_host_wait_capture;
            o_downloading <= s_downloading_capture;
            o_ddr_owner <= s_ddr_owner_capture;
            o_pause_request <= s_pause_request_capture;
            o_user_paused <= s_user_paused_capture;
            s_maintenance_access_launch <= i_maintenance_access;
            s_maintenance_valid_launch <= i_maintenance_valid;
            s_maintenance_write_launch <= i_maintenance_write;
            su14_maintenance_byte_address_launch <= iu14_maintenance_byte_address;
            su8_maintenance_data_launch <= iu8_maintenance_data;
            o_maintenance_ready <= s_maintenance_ready_capture;
            o_maintenance_response_valid <= s_maintenance_response_valid_capture;
            ou8_maintenance_response_data <= su8_maintenance_response_data_capture;
            o_maintenance_pause <= s_maintenance_pause_capture;
            ou8_player1 <= su8_player1_capture;
            ou8_player2 <= su8_player2_capture;
            ou8_service <= su8_service_capture;
            ou16_dips <= su16_dips_capture;
            o_ddr_mode <= s_ddr_mode_capture;
            s_ddr_busy_launch <= i_ddr_busy;
            ou8_ddr_burst_count <= su8_ddr_burst_count_capture;
            ou29_ddr_word_address <= su29_ddr_word_address_capture;
            su64_ddr_read_data_launch <= iu64_ddr_read_data;
            s_ddr_read_valid_launch <= i_ddr_read_valid;
            o_ddr_read <= s_ddr_read_capture;
            ou64_ddr_write_data <= su64_ddr_write_data_capture;
            ou8_ddr_byte_enables <= su8_ddr_byte_enables_capture;
            o_ddr_write <= s_ddr_write_capture;
            o_paused <= s_paused_capture;
            s_view_enable_launch <= i_view_enable;
            su5_view_target_launch <= iu5_view_target;
            su15_view_word_address_launch <= iu15_view_word_address;
            o_view_valid <= s_view_valid_capture;
            ou16_view_data <= su16_view_data_capture;
            ou16_left_pcm <= su16_left_pcm_capture;
            ou16_right_pcm <= su16_right_pcm_capture;
            ou9_adpcm_pcm <= su9_adpcm_pcm_capture;
            ou16_mono_pcm <= su16_mono_pcm_capture;
            o_audio_sample_marker <= s_audio_sample_marker_capture;
            o_adpcm_busy <= s_adpcm_busy_capture;
            s_audio_view_enable_launch <= i_audio_view_enable;
            su11_audio_view_address_launch <= iu11_audio_view_address;
            ou8_audio_view_data <= su8_audio_view_data_capture;
            o_audio_debug_request <= s_audio_debug_request_capture;
            o_audio_debug_write <= s_audio_debug_write_capture;
            ou16_audio_debug_address <= su16_audio_debug_address_capture;
            ou8_audio_debug_data <= su8_audio_debug_data_capture;
            o_sound_command_write <= s_sound_command_write_capture;
            ou8_sound_command <= su8_sound_command_capture;
            o_sound_pending <= s_sound_pending_capture;
            ou16_video_flags <= su16_video_flags_capture;
            ou9_scroll0_y <= su9_scroll0_y_capture;
            ou9_scroll0_x <= su9_scroll0_x_capture;
            ou9_scroll1_y <= su9_scroll1_y_capture;
            ou9_scroll1_x <= su9_scroll1_x_capture;
            ou6_sprite_count <= su6_sprite_count_capture;
            ou6_sprite_priority <= su6_sprite_priority_capture;
            ou4_gga_selected <= su4_gga_selected_capture;
            su4_gga_view_address_launch <= iu4_gga_view_address;
            ou8_gga_view_data <= su8_gga_view_data_capture;
            o_gga_write <= s_gga_write_capture;
            ou4_gga_write_address <= su4_gga_write_address_capture;
            ou8_gga_write_data <= su8_gga_write_data_capture;
            o_cpu_request <= s_cpu_request_capture;
            o_cpu_request_write <= s_cpu_request_write_capture;
            ou24_cpu_request_address <= su24_cpu_request_address_capture;
            ou16_cpu_request_data <= su16_cpu_request_data_capture;
            ou2_cpu_request_bytes <= su2_cpu_request_bytes_capture;
            o_image_valid <= s_image_valid_capture;
            o_error <= s_error_capture;
            o_done <= s_done_capture;
            ou27_bytes_loaded <= su27_bytes_loaded_capture;
            o_ready <= s_ready_capture;
            o_loading <= s_loading_capture;
            o_pixel_enable <= s_pixel_enable_capture;
            o_active <= s_active_capture;
            o_hsync <= s_hsync_capture;
            o_vsync <= s_vsync_capture;
            o_hblank <= s_hblank_capture;
            o_vblank <= s_vblank_capture;
            ou9_output_x <= su9_output_x_capture;
            ou8_output_y <= su8_output_y_capture;
            ou8_red <= su8_red_capture;
            ou8_green <= su8_green_capture;
            ou8_blue <= su8_blue_capture;
            ou9_horizontal_position <= su9_horizontal_position_capture;
            ou9_vertical_position <= su9_vertical_position_capture;
            o_scanout_armed <= s_scanout_armed_capture;
            o_scanout_underflow <= s_scanout_underflow_capture;
        end if;
    end process;
end architecture;
