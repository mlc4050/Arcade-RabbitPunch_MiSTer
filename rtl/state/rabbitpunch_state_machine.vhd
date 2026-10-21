-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_config.all;

-- State service and actual machine behind separate loader/state DDR clients.
-- The framework owns their shared DDR arbitration and continuous presentation.
-- Controls remain internal until full game continuation and FPGA qualification.
entity rabbitpunch_state_machine is
    generic (
        GINT_SDRAM_READ_CAPTURE_ADJUST : natural range 0 to 2 := 0;
        GINT_IMAGE_BYTES : positive := CINT_ROM_IMAGE_SIZE;
        GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000";
        GINT_STATE_TIMEOUT_CYCLES : positive := 48000000
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
        o_scanout_underflow : out std_logic;
        o_state_cpu_stopped : out std_logic;
        ou52_state_cpu_bus : out unsigned(51 downto 0);
        i_state_save : in std_logic;
        i_state_restore : in std_logic;
        i_state_cancel : in std_logic;
        iu2_state_slot : in unsigned(1 downto 0);
        iu32_state_abi_signature : in unsigned(31 downto 0);
        iu32_state_config_identity : in unsigned(31 downto 0);
        o_state_ready : out std_logic;
        o_state_busy : out std_logic;
        o_state_finished : out std_logic;
        o_state_success : out std_logic;
        o_state_restoring : out std_logic;
        o_state_incomplete : out std_logic;
        o_state_run_release : out std_logic := '0';
        o_state_presentation_flush : out std_logic := '0';
        ou8_state_error : out unsigned(7 downto 0);
        o_state_rom_identity_valid : out std_logic;
        o_state_rom_identity_error : out std_logic;
        ou32_state_rom_identity : out unsigned(31 downto 0);
        o_state_ddr_read : out std_logic;
        o_state_ddr_write : out std_logic;
        ou29_state_ddr_word_address : out unsigned(28 downto 0);
        ou64_state_ddr_write_data : out unsigned(63 downto 0);
        i_state_ddr_busy : in std_logic;
        i_state_ddr_read_valid : in std_logic;
        iu64_state_ddr_read_data : in unsigned(63 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_machine is
    signal s_ready, s_initialize, s_incomplete, s_reset_drained, s_rom_valid : std_logic;
    signal s_machine_ready, s_machine_busy, s_machine_held, s_machine_finished : std_logic;
    signal s_acquire, s_machine_cancel, s_release : std_logic;
    signal su4_machine_error : unsigned(3 downto 0);
    signal su32_rom_identity : unsigned(31 downto 0);
    signal s_body_begin, s_body_request, s_body_ready, s_body_write, s_body_response : std_logic;
    signal s_body_error, s_body_commit, s_body_committed, s_body_commit_error : std_logic;
    signal su18_body_address : unsigned(17 downto 0);
    signal su8_body_write_data, su8_body_read_data : unsigned(7 downto 0);
    signal s_previous_save, s_previous_restore : std_logic := '0';
    signal s_save_edge, s_restore_edge : std_logic;
begin
    o_ready <= s_ready;
    o_state_incomplete <= s_incomplete;
    o_state_rom_identity_valid <= s_rom_valid;
    ou32_state_rom_identity <= su32_rom_identity;
    s_initialize <= i_initialize or not s_ready;
    s_save_edge <= i_state_save and not s_previous_save;
    s_restore_edge <= i_state_restore and not s_previous_restore;
    command_edges : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (s_initialize = '1') then
                s_previous_save <= '0';
                s_previous_restore <= '0';
            else
                s_previous_save <= i_state_save;
                s_previous_restore <= i_state_restore;
            end if;
        end if;
    end process;
    machine : entity work.rabbitpunch_state_machine_backend
        generic map (
            GINT_SDRAM_READ_CAPTURE_ADJUST => GINT_SDRAM_READ_CAPTURE_ADJUST,
            GINT_IMAGE_BYTES => GINT_IMAGE_BYTES,
            GU16_DIP_DEFAULT => GU16_DIP_DEFAULT,
            GINT_STATE_TIMEOUT_CYCLES => GINT_STATE_TIMEOUT_CYCLES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_framework_reset => i_framework_reset,
            iu128_status => iu128_status,
            iu2_host_buttons => iu2_host_buttons,
            iu32_joystick0 => iu32_joystick0,
            iu32_joystick1 => iu32_joystick1,
            iu11_key_event => iu11_key_event,
            i_osd_open => i_osd_open,
            i_debug_pause => i_debug_pause,
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
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data,
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
            o_loading => o_loading,
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
            o_scanout_armed => o_scanout_armed,
            o_scanout_underflow => o_scanout_underflow,
            i_state_acquire => s_acquire,
            i_state_cancel => s_machine_cancel,
            i_state_release => s_release,
            i_state_incomplete => s_incomplete,
            o_state_ready => s_machine_ready,
            o_state_busy => s_machine_busy,
            o_state_held => s_machine_held,
            o_state_finished => s_machine_finished,
            o_state_canceled => open,
            ou4_state_error => su4_machine_error,
            o_state_reset_drained => s_reset_drained,
            o_state_run_release => o_state_run_release,
            o_state_presentation_flush => o_state_presentation_flush,
            o_state_rom_identity_valid => s_rom_valid,
            o_state_rom_identity_error => o_state_rom_identity_error,
            ou32_state_rom_identity => su32_rom_identity,
            i_state_apply_begin => s_body_begin,
            i_state_byte_request => s_body_request,
            o_state_byte_ready => s_body_ready,
            i_state_byte_write => s_body_write,
            iu18_state_byte_address => su18_body_address,
            iu8_state_byte_data => su8_body_write_data,
            o_state_byte_response => s_body_response,
            o_state_byte_error => s_body_error,
            ou8_state_byte_data => su8_body_read_data,
            i_state_commit => s_body_commit,
            o_state_committed => s_body_committed,
            o_state_commit_error => s_body_commit_error,
            o_state_banks_idle => open,
            o_state_cpu_stopped => o_state_cpu_stopped,
            ou52_state_cpu_bus => ou52_state_cpu_bus
        );
    image_service : entity work.rabbitpunch_state_service
        port map (
            i_clk => i_clk,
            i_initialize => s_initialize,
            i_game_reset_completed => s_reset_drained,
            i_save => s_save_edge,
            i_restore => s_restore_edge,
            i_cancel => i_state_cancel,
            iu2_slot => iu2_state_slot,
            i_rom_identity_valid => s_rom_valid,
            iu32_abi_signature => iu32_state_abi_signature,
            iu32_rom_identity => su32_rom_identity,
            iu32_config_identity => iu32_state_config_identity,
            o_ready => o_state_ready,
            o_busy => o_state_busy,
            o_finished => o_state_finished,
            o_success => o_state_success,
            o_restoring => o_state_restoring,
            o_incomplete => s_incomplete,
            ou8_error => ou8_state_error,
            i_machine_ready => s_machine_ready,
            i_machine_busy => s_machine_busy,
            i_machine_held => s_machine_held,
            i_machine_finished => s_machine_finished,
            iu4_machine_error => su4_machine_error,
            o_machine_acquire => s_acquire,
            o_machine_cancel => s_machine_cancel,
            o_machine_release => s_release,
            o_body_apply_begin => s_body_begin,
            o_body_request => s_body_request,
            i_body_ready => s_body_ready,
            o_body_write => s_body_write,
            ou18_body_address => su18_body_address,
            ou8_body_data => su8_body_write_data,
            i_body_response => s_body_response,
            i_body_error => s_body_error,
            iu8_body_data => su8_body_read_data,
            o_body_commit => s_body_commit,
            i_body_committed => s_body_committed,
            i_body_commit_error => s_body_commit_error,
            o_ddr_read => o_state_ddr_read,
            o_ddr_write => o_state_ddr_write,
            ou29_ddr_word_address => ou29_state_ddr_word_address,
            ou64_ddr_write_data => ou64_state_ddr_write_data,
            i_ddr_busy => i_state_ddr_busy,
            i_ddr_read_valid => i_state_ddr_read_valid,
            iu64_ddr_read_data => iu64_state_ddr_read_data
        );
end architecture;
