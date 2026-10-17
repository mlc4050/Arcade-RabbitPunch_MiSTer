-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity platform_check is
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

-- Registered logical evaluation boundaries; SDRAM pins are direct wires.
architecture evaluation of platform_check is
    signal s_boundary_i_initialize : std_logic := '0';
    signal s_boundary_i_framework_reset : std_logic := '0';
    signal su128_boundary_iu128_status : unsigned(127 downto 0) := (others => '0');
    signal su2_boundary_iu2_host_buttons : unsigned(1 downto 0) := (others => '0');
    signal su32_boundary_iu32_joystick0 : unsigned(31 downto 0) := (others => '0');
    signal su32_boundary_iu32_joystick1 : unsigned(31 downto 0) := (others => '0');
    signal su11_boundary_iu11_key_event : unsigned(10 downto 0) := (others => '0');
    signal s_boundary_i_osd_open : std_logic := '0';
    signal s_boundary_i_debug_pause : std_logic := '0';
    signal s_boundary_i_state_pause : std_logic := '0';
    signal s_boundary_i_host_download : std_logic := '0';
    signal su16_boundary_iu16_host_index : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_host_write : std_logic := '0';
    signal su27_boundary_iu27_host_byte_address : unsigned(26 downto 0) := (others => '0');
    signal su8_boundary_iu8_host_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_host_wait : std_logic := '0';
    signal s_boundary_o_downloading : std_logic := '0';
    signal s_boundary_o_ddr_owner : std_logic := '0';
    signal s_boundary_o_pause_request : std_logic := '0';
    signal s_boundary_o_user_paused : std_logic := '0';
    signal su8_boundary_ou8_player1 : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_player2 : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_service : unsigned(7 downto 0) := (others => '0');
    signal su16_boundary_ou16_dips : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_o_ddr_mode : std_logic := '0';
    signal s_boundary_i_ddr_busy : std_logic := '0';
    signal su8_boundary_ou8_ddr_burst_count : unsigned(7 downto 0) := (others => '0');
    signal su29_boundary_ou29_ddr_word_address : unsigned(28 downto 0) := (others => '0');
    signal su64_boundary_iu64_ddr_read_data : unsigned(63 downto 0) := (others => '0');
    signal s_boundary_i_ddr_read_valid : std_logic := '0';
    signal s_boundary_o_ddr_read : std_logic := '0';
    signal su64_boundary_ou64_ddr_write_data : unsigned(63 downto 0) := (others => '0');
    signal su8_boundary_ou8_ddr_byte_enables : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_ddr_write : std_logic := '0';
    signal s_boundary_o_paused : std_logic := '0';
    signal s_boundary_i_vblank_start : std_logic := '0';
    signal s_boundary_i_half_frame : std_logic := '0';
    signal s_boundary_i_line_valid : std_logic := '0';
    signal s_boundary_o_line_ready : std_logic := '0';
    signal s_boundary_i_render_bank : std_logic := '0';
    signal su9_boundary_iu9_line_y : unsigned(8 downto 0) := (others => '0');
    signal s_boundary_o_line_done : std_logic := '0';
    signal s_boundary_i_pixel_valid : std_logic := '0';
    signal s_boundary_o_pixel_ready : std_logic := '0';
    signal s_boundary_i_pixel_bank : std_logic := '0';
    signal su9_boundary_iu9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su8_boundary_iu8_pixel_y : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_pixel_valid : std_logic := '0';
    signal s_boundary_o_pixel_error : std_logic := '0';
    signal su9_boundary_ou9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su8_boundary_ou8_pixel_y : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_red : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_green : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_blue : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_i_view_enable : std_logic := '0';
    signal su5_boundary_iu5_view_target : target_t := (others => '0');
    signal su15_boundary_iu15_view_word_address : unsigned(14 downto 0) := (others => '0');
    signal s_boundary_o_view_valid : std_logic := '0';
    signal su16_boundary_ou16_view_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_sound_cpu_enable : std_logic := '0';
    signal s_boundary_i_ym_enable : std_logic := '0';
    signal s_boundary_i_ym_half_enable : std_logic := '0';
    signal s_boundary_i_adpcm_enable : std_logic := '0';
    signal su16_boundary_ou16_left_pcm : unsigned(15 downto 0) := (others => '0');
    signal su16_boundary_ou16_right_pcm : unsigned(15 downto 0) := (others => '0');
    signal su9_boundary_ou9_adpcm_pcm : unsigned(8 downto 0) := (others => '0');
    signal su16_boundary_ou16_mono_pcm : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_o_audio_sample_marker : std_logic := '0';
    signal s_boundary_o_adpcm_busy : std_logic := '0';
    signal s_boundary_i_audio_view_enable : std_logic := '0';
    signal su11_boundary_iu11_audio_view_address : unsigned(10 downto 0) := (others => '0');
    signal su8_boundary_ou8_audio_view_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_audio_debug_request : std_logic := '0';
    signal s_boundary_o_audio_debug_write : std_logic := '0';
    signal su16_boundary_ou16_audio_debug_address : unsigned(15 downto 0) := (others => '0');
    signal su8_boundary_ou8_audio_debug_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_sound_command_write : std_logic := '0';
    signal su8_boundary_ou8_sound_command : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_sound_pending : std_logic := '0';
    signal su16_boundary_ou16_video_flags : unsigned(15 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll0_y : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll0_x : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll1_y : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll1_x : unsigned(8 downto 0) := (others => '0');
    signal su6_boundary_ou6_sprite_count : unsigned(5 downto 0) := (others => '0');
    signal su6_boundary_ou6_sprite_priority : unsigned(5 downto 0) := (others => '0');
    signal su4_boundary_ou4_gga_selected : unsigned(3 downto 0) := (others => '0');
    signal su4_boundary_iu4_gga_view_address : unsigned(3 downto 0) := (others => '0');
    signal su8_boundary_ou8_gga_view_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_gga_write : std_logic := '0';
    signal su4_boundary_ou4_gga_write_address : unsigned(3 downto 0) := (others => '0');
    signal su8_boundary_ou8_gga_write_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_cpu_request : std_logic := '0';
    signal s_boundary_o_cpu_request_write : std_logic := '0';
    signal su24_boundary_ou24_cpu_request_address : unsigned(23 downto 0) := (others => '0');
    signal su16_boundary_ou16_cpu_request_data : unsigned(15 downto 0) := (others => '0');
    signal su2_boundary_ou2_cpu_request_bytes : unsigned(1 downto 0) := (others => '0');
    signal s_boundary_o_image_valid : std_logic := '0';
    signal s_boundary_o_error : std_logic := '0';
    signal s_boundary_o_done : std_logic := '0';
    signal su27_boundary_ou27_bytes_loaded : unsigned(26 downto 0) := (others => '0');
    signal s_boundary_o_ready : std_logic := '0';
    signal s_boundary_o_loading : std_logic := '0';
    signal s_boundary_i_maintenance_access : std_logic := '0';
    signal s_boundary_i_maintenance_valid : std_logic := '0';
    signal s_boundary_i_maintenance_write : std_logic := '0';
    signal su14_boundary_iu14_maintenance_byte_address : unsigned(13 downto 0) := (others => '0');
    signal su8_boundary_iu8_maintenance_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_maintenance_ready : std_logic := '0';
    signal s_boundary_o_maintenance_response_valid : std_logic := '0';
    signal su8_boundary_ou8_maintenance_response_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_maintenance_pause : std_logic := '0';
    signal su16_boundary_ou16_host_menu_mask : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_host_upload : std_logic := '0';
    signal s_boundary_o_host_upload_request : std_logic := '0';
    signal su8_boundary_ou8_host_upload_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_hiscore_enabled : std_logic := '0';
    signal s_boundary_o_hiscore_config_error : std_logic := '0';
    signal s_boundary_o_hiscore_initialized : std_logic := '0';
    signal s_boundary_o_hiscore_saved_valid : std_logic := '0';
    signal s_boundary_o_hiscore_dirty : std_logic := '0';
begin
    boundary : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            ou16_host_menu_mask <= su16_boundary_ou16_host_menu_mask;
            s_boundary_i_host_upload <= i_host_upload;
            o_host_upload_request <= s_boundary_o_host_upload_request;
            ou8_host_upload_data <= su8_boundary_ou8_host_upload_data;
            o_hiscore_enabled <= s_boundary_o_hiscore_enabled;
            o_hiscore_config_error <= s_boundary_o_hiscore_config_error;
            o_hiscore_initialized <= s_boundary_o_hiscore_initialized;
            o_hiscore_saved_valid <= s_boundary_o_hiscore_saved_valid;
            o_hiscore_dirty <= s_boundary_o_hiscore_dirty;
            s_boundary_i_maintenance_access <= i_maintenance_access;
            s_boundary_i_maintenance_valid <= i_maintenance_valid;
            s_boundary_i_maintenance_write <= i_maintenance_write;
            su14_boundary_iu14_maintenance_byte_address <= iu14_maintenance_byte_address;
            su8_boundary_iu8_maintenance_data <= iu8_maintenance_data;
            o_maintenance_ready <= s_boundary_o_maintenance_ready;
            o_maintenance_response_valid <= s_boundary_o_maintenance_response_valid;
            ou8_maintenance_response_data <= su8_boundary_ou8_maintenance_response_data;
            o_maintenance_pause <= s_boundary_o_maintenance_pause;
            s_boundary_i_initialize <= i_initialize;
            s_boundary_i_framework_reset <= i_framework_reset;
            su128_boundary_iu128_status <= iu128_status;
            su2_boundary_iu2_host_buttons <= iu2_host_buttons;
            su32_boundary_iu32_joystick0 <= iu32_joystick0;
            su32_boundary_iu32_joystick1 <= iu32_joystick1;
            su11_boundary_iu11_key_event <= iu11_key_event;
            s_boundary_i_osd_open <= i_osd_open;
            s_boundary_i_debug_pause <= i_debug_pause;
            s_boundary_i_state_pause <= i_state_pause;
            s_boundary_i_host_download <= i_host_download;
            su16_boundary_iu16_host_index <= iu16_host_index;
            s_boundary_i_host_write <= i_host_write;
            su27_boundary_iu27_host_byte_address <= iu27_host_byte_address;
            su8_boundary_iu8_host_data <= iu8_host_data;
            o_host_wait <= s_boundary_o_host_wait;
            o_downloading <= s_boundary_o_downloading;
            o_ddr_owner <= s_boundary_o_ddr_owner;
            o_pause_request <= s_boundary_o_pause_request;
            o_user_paused <= s_boundary_o_user_paused;
            ou8_player1 <= su8_boundary_ou8_player1;
            ou8_player2 <= su8_boundary_ou8_player2;
            ou8_service <= su8_boundary_ou8_service;
            ou16_dips <= su16_boundary_ou16_dips;
            o_ddr_mode <= s_boundary_o_ddr_mode;
            s_boundary_i_ddr_busy <= i_ddr_busy;
            ou8_ddr_burst_count <= su8_boundary_ou8_ddr_burst_count;
            ou29_ddr_word_address <= su29_boundary_ou29_ddr_word_address;
            su64_boundary_iu64_ddr_read_data <= iu64_ddr_read_data;
            s_boundary_i_ddr_read_valid <= i_ddr_read_valid;
            o_ddr_read <= s_boundary_o_ddr_read;
            ou64_ddr_write_data <= su64_boundary_ou64_ddr_write_data;
            ou8_ddr_byte_enables <= su8_boundary_ou8_ddr_byte_enables;
            o_ddr_write <= s_boundary_o_ddr_write;
            o_paused <= s_boundary_o_paused;
            s_boundary_i_vblank_start <= i_vblank_start;
            s_boundary_i_half_frame <= i_half_frame;
            s_boundary_i_line_valid <= i_line_valid;
            o_line_ready <= s_boundary_o_line_ready;
            s_boundary_i_render_bank <= i_render_bank;
            su9_boundary_iu9_line_y <= iu9_line_y;
            o_line_done <= s_boundary_o_line_done;
            s_boundary_i_pixel_valid <= i_pixel_valid;
            o_pixel_ready <= s_boundary_o_pixel_ready;
            s_boundary_i_pixel_bank <= i_pixel_bank;
            su9_boundary_iu9_pixel_x <= iu9_pixel_x;
            su8_boundary_iu8_pixel_y <= iu8_pixel_y;
            o_pixel_valid <= s_boundary_o_pixel_valid;
            o_pixel_error <= s_boundary_o_pixel_error;
            ou9_pixel_x <= su9_boundary_ou9_pixel_x;
            ou8_pixel_y <= su8_boundary_ou8_pixel_y;
            ou8_red <= su8_boundary_ou8_red;
            ou8_green <= su8_boundary_ou8_green;
            ou8_blue <= su8_boundary_ou8_blue;
            s_boundary_i_view_enable <= i_view_enable;
            su5_boundary_iu5_view_target <= iu5_view_target;
            su15_boundary_iu15_view_word_address <= iu15_view_word_address;
            o_view_valid <= s_boundary_o_view_valid;
            ou16_view_data <= su16_boundary_ou16_view_data;
            s_boundary_i_sound_cpu_enable <= i_sound_cpu_enable;
            s_boundary_i_ym_enable <= i_ym_enable;
            s_boundary_i_ym_half_enable <= i_ym_half_enable;
            s_boundary_i_adpcm_enable <= i_adpcm_enable;
            ou16_left_pcm <= su16_boundary_ou16_left_pcm;
            ou16_right_pcm <= su16_boundary_ou16_right_pcm;
            ou9_adpcm_pcm <= su9_boundary_ou9_adpcm_pcm;
            ou16_mono_pcm <= su16_boundary_ou16_mono_pcm;
            o_audio_sample_marker <= s_boundary_o_audio_sample_marker;
            o_adpcm_busy <= s_boundary_o_adpcm_busy;
            s_boundary_i_audio_view_enable <= i_audio_view_enable;
            su11_boundary_iu11_audio_view_address <= iu11_audio_view_address;
            ou8_audio_view_data <= su8_boundary_ou8_audio_view_data;
            o_audio_debug_request <= s_boundary_o_audio_debug_request;
            o_audio_debug_write <= s_boundary_o_audio_debug_write;
            ou16_audio_debug_address <= su16_boundary_ou16_audio_debug_address;
            ou8_audio_debug_data <= su8_boundary_ou8_audio_debug_data;
            o_sound_command_write <= s_boundary_o_sound_command_write;
            ou8_sound_command <= su8_boundary_ou8_sound_command;
            o_sound_pending <= s_boundary_o_sound_pending;
            ou16_video_flags <= su16_boundary_ou16_video_flags;
            ou9_scroll0_y <= su9_boundary_ou9_scroll0_y;
            ou9_scroll0_x <= su9_boundary_ou9_scroll0_x;
            ou9_scroll1_y <= su9_boundary_ou9_scroll1_y;
            ou9_scroll1_x <= su9_boundary_ou9_scroll1_x;
            ou6_sprite_count <= su6_boundary_ou6_sprite_count;
            ou6_sprite_priority <= su6_boundary_ou6_sprite_priority;
            ou4_gga_selected <= su4_boundary_ou4_gga_selected;
            su4_boundary_iu4_gga_view_address <= iu4_gga_view_address;
            ou8_gga_view_data <= su8_boundary_ou8_gga_view_data;
            o_gga_write <= s_boundary_o_gga_write;
            ou4_gga_write_address <= su4_boundary_ou4_gga_write_address;
            ou8_gga_write_data <= su8_boundary_ou8_gga_write_data;
            o_cpu_request <= s_boundary_o_cpu_request;
            o_cpu_request_write <= s_boundary_o_cpu_request_write;
            ou24_cpu_request_address <= su24_boundary_ou24_cpu_request_address;
            ou16_cpu_request_data <= su16_boundary_ou16_cpu_request_data;
            ou2_cpu_request_bytes <= su2_boundary_ou2_cpu_request_bytes;
            o_image_valid <= s_boundary_o_image_valid;
            o_error <= s_boundary_o_error;
            o_done <= s_boundary_o_done;
            ou27_bytes_loaded <= su27_boundary_ou27_bytes_loaded;
            o_ready <= s_boundary_o_ready;
            o_loading <= s_boundary_o_loading;
        end if;
    end process;
    platform : entity work.rabbitpunch_platform
        port map (
            i_clk => i_clk,
            i_initialize => s_boundary_i_initialize,
            i_framework_reset => s_boundary_i_framework_reset,
            iu128_status => su128_boundary_iu128_status,
            iu2_host_buttons => su2_boundary_iu2_host_buttons,
            iu32_joystick0 => su32_boundary_iu32_joystick0,
            iu32_joystick1 => su32_boundary_iu32_joystick1,
            iu11_key_event => su11_boundary_iu11_key_event,
            i_osd_open => s_boundary_i_osd_open,
            i_debug_pause => s_boundary_i_debug_pause,
            i_state_pause => s_boundary_i_state_pause,
            i_host_download => s_boundary_i_host_download,
            i_host_upload => s_boundary_i_host_upload,
            ou16_host_menu_mask => su16_boundary_ou16_host_menu_mask,
            o_host_upload_request => s_boundary_o_host_upload_request,
            ou8_host_upload_data => su8_boundary_ou8_host_upload_data,
            o_hiscore_enabled => s_boundary_o_hiscore_enabled,
            o_hiscore_config_error => s_boundary_o_hiscore_config_error,
            o_hiscore_initialized => s_boundary_o_hiscore_initialized,
            o_hiscore_saved_valid => s_boundary_o_hiscore_saved_valid,
            o_hiscore_dirty => s_boundary_o_hiscore_dirty,
            iu16_host_index => su16_boundary_iu16_host_index,
            i_host_write => s_boundary_i_host_write,
            iu27_host_byte_address => su27_boundary_iu27_host_byte_address,
            iu8_host_data => su8_boundary_iu8_host_data,
            o_host_wait => s_boundary_o_host_wait,
            o_downloading => s_boundary_o_downloading,
            o_ddr_owner => s_boundary_o_ddr_owner,
            o_pause_request => s_boundary_o_pause_request,
            o_user_paused => s_boundary_o_user_paused,
            ou8_player1 => su8_boundary_ou8_player1,
            ou8_player2 => su8_boundary_ou8_player2,
            ou8_service => su8_boundary_ou8_service,
            ou16_dips => su16_boundary_ou16_dips,
            o_ddr_mode => s_boundary_o_ddr_mode,
            i_ddr_busy => s_boundary_i_ddr_busy,
            ou8_ddr_burst_count => su8_boundary_ou8_ddr_burst_count,
            ou29_ddr_word_address => su29_boundary_ou29_ddr_word_address,
            iu64_ddr_read_data => su64_boundary_iu64_ddr_read_data,
            i_ddr_read_valid => s_boundary_i_ddr_read_valid,
            o_ddr_read => s_boundary_o_ddr_read,
            ou64_ddr_write_data => su64_boundary_ou64_ddr_write_data,
            ou8_ddr_byte_enables => su8_boundary_ou8_ddr_byte_enables,
            o_ddr_write => s_boundary_o_ddr_write,
            o_paused => s_boundary_o_paused,
            i_maintenance_access => s_boundary_i_maintenance_access,
            i_maintenance_valid => s_boundary_i_maintenance_valid,
            i_maintenance_write => s_boundary_i_maintenance_write,
            iu14_maintenance_byte_address => su14_boundary_iu14_maintenance_byte_address,
            iu8_maintenance_data => su8_boundary_iu8_maintenance_data,
            o_maintenance_ready => s_boundary_o_maintenance_ready,
            o_maintenance_response_valid => s_boundary_o_maintenance_response_valid,
            ou8_maintenance_response_data => su8_boundary_ou8_maintenance_response_data,
            o_maintenance_pause => s_boundary_o_maintenance_pause,
            i_vblank_start => s_boundary_i_vblank_start,
            i_half_frame => s_boundary_i_half_frame,
            i_line_valid => s_boundary_i_line_valid,
            o_line_ready => s_boundary_o_line_ready,
            i_render_bank => s_boundary_i_render_bank,
            iu9_line_y => su9_boundary_iu9_line_y,
            o_line_done => s_boundary_o_line_done,
            i_pixel_valid => s_boundary_i_pixel_valid,
            o_pixel_ready => s_boundary_o_pixel_ready,
            i_pixel_bank => s_boundary_i_pixel_bank,
            iu9_pixel_x => su9_boundary_iu9_pixel_x,
            iu8_pixel_y => su8_boundary_iu8_pixel_y,
            o_pixel_valid => s_boundary_o_pixel_valid,
            o_pixel_error => s_boundary_o_pixel_error,
            ou9_pixel_x => su9_boundary_ou9_pixel_x,
            ou8_pixel_y => su8_boundary_ou8_pixel_y,
            ou8_red => su8_boundary_ou8_red,
            ou8_green => su8_boundary_ou8_green,
            ou8_blue => su8_boundary_ou8_blue,
            i_view_enable => s_boundary_i_view_enable,
            iu5_view_target => su5_boundary_iu5_view_target,
            iu15_view_word_address => su15_boundary_iu15_view_word_address,
            o_view_valid => s_boundary_o_view_valid,
            ou16_view_data => su16_boundary_ou16_view_data,
            i_sound_cpu_enable => s_boundary_i_sound_cpu_enable,
            i_ym_enable => s_boundary_i_ym_enable,
            i_ym_half_enable => s_boundary_i_ym_half_enable,
            i_adpcm_enable => s_boundary_i_adpcm_enable,
            ou16_left_pcm => su16_boundary_ou16_left_pcm,
            ou16_right_pcm => su16_boundary_ou16_right_pcm,
            ou9_adpcm_pcm => su9_boundary_ou9_adpcm_pcm,
            ou16_mono_pcm => su16_boundary_ou16_mono_pcm,
            o_audio_sample_marker => s_boundary_o_audio_sample_marker,
            o_adpcm_busy => s_boundary_o_adpcm_busy,
            i_audio_view_enable => s_boundary_i_audio_view_enable,
            iu11_audio_view_address => su11_boundary_iu11_audio_view_address,
            ou8_audio_view_data => su8_boundary_ou8_audio_view_data,
            o_audio_debug_request => s_boundary_o_audio_debug_request,
            o_audio_debug_write => s_boundary_o_audio_debug_write,
            ou16_audio_debug_address => su16_boundary_ou16_audio_debug_address,
            ou8_audio_debug_data => su8_boundary_ou8_audio_debug_data,
            o_sound_command_write => s_boundary_o_sound_command_write,
            ou8_sound_command => su8_boundary_ou8_sound_command,
            o_sound_pending => s_boundary_o_sound_pending,
            ou16_video_flags => su16_boundary_ou16_video_flags,
            ou9_scroll0_y => su9_boundary_ou9_scroll0_y,
            ou9_scroll0_x => su9_boundary_ou9_scroll0_x,
            ou9_scroll1_y => su9_boundary_ou9_scroll1_y,
            ou9_scroll1_x => su9_boundary_ou9_scroll1_x,
            ou6_sprite_count => su6_boundary_ou6_sprite_count,
            ou6_sprite_priority => su6_boundary_ou6_sprite_priority,
            ou4_gga_selected => su4_boundary_ou4_gga_selected,
            iu4_gga_view_address => su4_boundary_iu4_gga_view_address,
            ou8_gga_view_data => su8_boundary_ou8_gga_view_data,
            o_gga_write => s_boundary_o_gga_write,
            ou4_gga_write_address => su4_boundary_ou4_gga_write_address,
            ou8_gga_write_data => su8_boundary_ou8_gga_write_data,
            o_cpu_request => s_boundary_o_cpu_request,
            o_cpu_request_write => s_boundary_o_cpu_request_write,
            ou24_cpu_request_address => su24_boundary_ou24_cpu_request_address,
            ou16_cpu_request_data => su16_boundary_ou16_cpu_request_data,
            ou2_cpu_request_bytes => su2_boundary_ou2_cpu_request_bytes,
            o_image_valid => s_boundary_o_image_valid,
            o_error => s_boundary_o_error,
            o_done => s_boundary_o_done,
            ou27_bytes_loaded => su27_boundary_ou27_bytes_loaded,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => ou13_sdram_address,
            ou2_sdram_bank => ou2_sdram_bank,
            ou2_sdram_byte_mask => ou2_sdram_byte_mask,
            o_sdram_chip_select => o_sdram_chip_select,
            o_sdram_write_n => o_sdram_write_n,
            o_sdram_row_n => o_sdram_row_n,
            o_sdram_column_n => o_sdram_column_n,
            o_sdram_clock_enable => o_sdram_clock_enable,
            o_ready => s_boundary_o_ready,
            o_loading => s_boundary_o_loading
        );
end architecture;
