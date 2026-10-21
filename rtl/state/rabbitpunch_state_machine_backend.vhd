-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_config.all;

-- Actual machine, coherent acquisition barrier and complete body byte backend.
-- The image service supplies incomplete-apply permission; no OSD or DDR slot
-- operation is exposed here. Physical raster and SDRAM remain continuously clocked.
entity rabbitpunch_state_machine_backend is
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
        i_state_acquire : in std_logic;
        i_state_cancel : in std_logic;
        i_state_release : in std_logic;
        i_state_incomplete : in std_logic;
        o_state_ready : out std_logic;
        o_state_busy : out std_logic;
        o_state_held : out std_logic;
        o_state_finished : out std_logic;
        o_state_canceled : out std_logic;
        ou4_state_error : out unsigned(3 downto 0);
        o_state_reset_drained : out std_logic;
        o_state_run_release : out std_logic := '0';
        o_state_presentation_flush : out std_logic := '0';
        o_state_rom_identity_valid : out std_logic;
        o_state_rom_identity_error : out std_logic;
        ou32_state_rom_identity : out unsigned(31 downto 0);
        i_state_apply_begin : in std_logic;
        i_state_byte_request : in std_logic;
        o_state_byte_ready : out std_logic;
        i_state_byte_write : in std_logic;
        iu18_state_byte_address : in unsigned(17 downto 0);
        iu8_state_byte_data : in unsigned(7 downto 0);
        o_state_byte_response : out std_logic;
        o_state_byte_error : out std_logic;
        ou8_state_byte_data : out unsigned(7 downto 0);
        i_state_commit : in std_logic;
        o_state_committed : out std_logic;
        o_state_commit_error : out std_logic;
        o_state_banks_idle : out std_logic;
        o_state_cpu_stopped : out std_logic;
        ou52_state_cpu_bus : out unsigned(51 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_machine_backend is
    signal s_machine_ready, s_scores_initialized, s_reset, s_access_ready, s_rom_identity_valid : std_logic;
    signal s_pause, s_main_capture, s_sound_capture, s_capture_cancel : std_logic;
    signal s_main_held, s_main_error, s_main_return_held, s_main_resumed, s_main_canceled : std_logic;
    signal s_sound_held, s_sound_drained, s_sound_bus_idle, s_main_bus_idle : std_logic;
    signal s_main_resume, s_main_release, s_sound_resume, s_private_return : std_logic;
    signal s_sdram_prepare, s_sdram_aligned, s_release_aligned : std_logic;
    signal s_game_hold, s_video_flush, s_rom_flush, s_transport_idle, s_aligned : std_logic;
    signal s_bank_session, s_banks_idle, s_held, s_board_load, s_t80_load : std_logic;
    signal s_nvram_quiesce, s_legacy_quiesce, s_nvram_quiesced, s_nvram_reconcile : std_logic;
    signal s_scores_ready, s_legacy_idle, s_cpu_write, s_fm_write, s_adpcm_write : std_logic;
    signal s_main_request, s_main_write, s_main_response : std_logic;
    signal s_sound_request, s_sound_write, s_sound_response : std_logic;
    signal su224_io : unsigned(223 downto 0);
    signal su4_irq : unsigned(3 downto 0);
    signal su32_cadence, su32_cpu_read_data, su32_cpu_write_data : unsigned(31 downto 0);
    signal su32_fm_data, su32_adpcm_data, su32_chip_data : unsigned(31 downto 0);
    signal su18_beam : unsigned(17 downto 0);
    signal su16_adpcm, su16_mixer, su16_chip_address, su16_sound_address : unsigned(15 downto 0);
    signal su16_main_write_data, su16_main_read_data : unsigned(15 downto 0);
    signal su8_sound_write_data, su8_sound_read_data : unsigned(7 downto 0);
    signal su2_fm_startup, su2_main_bytes : unsigned(1 downto 0);
    signal su5_cpu_address : unsigned(4 downto 0);
    signal su24_main_address : unsigned(23 downto 0);
    signal su256_t80, su256_t80_load : unsigned(255 downto 0);
    signal su512_board, su512_board_load : unsigned(511 downto 0);
begin
    o_ready <= s_machine_ready;
    o_hiscore_initialized <= s_scores_initialized;
    o_state_held <= s_held;
    o_state_banks_idle <= s_banks_idle;
    o_state_run_release <= s_main_release;
    s_release_aligned <= s_aligned and s_sdram_aligned;
    o_state_presentation_flush <= s_video_flush;
    o_state_ready <= s_access_ready and s_rom_identity_valid;
    o_state_rom_identity_valid <= s_rom_identity_valid;
    -- The machine's ready falls for every real board reset, including loading,
    -- status/button reset and ROM failure. Accepted bank credits still drain.
    s_reset <= i_initialize or not s_machine_ready;
    su512_board <= (511 downto 355 => '0') & s_scores_ready & su2_fm_startup &
        su16_mixer & su16_adpcm & (13 downto 0 => '0') & su18_beam &
        su32_cadence & (27 downto 0 => '0') & su4_irq & su224_io;
    machine : entity work.rabbitpunch_machine
        generic map (
            GINT_SDRAM_READ_CAPTURE_ADJUST => GINT_SDRAM_READ_CAPTURE_ADJUST,
            GINT_IMAGE_BYTES => GINT_IMAGE_BYTES,
            GU16_DIP_DEFAULT => GU16_DIP_DEFAULT,
            GBOOL_STATE_CAPABLE => true
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
            i_state_pause => s_pause,
            i_host_download => i_host_download,
            i_host_upload => i_host_upload,
            o_host_upload_request => o_host_upload_request,
            ou8_host_upload_data => ou8_host_upload_data,
            ou16_host_menu_mask => ou16_host_menu_mask,
            o_hiscore_enabled => o_hiscore_enabled,
            o_hiscore_config_error => o_hiscore_config_error,
            o_hiscore_initialized => s_scores_initialized,
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
            o_ready => s_machine_ready,
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
            i_state_capture => s_main_capture,
            i_state_cancel => s_capture_cancel,
            o_state_pending => open,
            o_state_held => s_main_held,
            o_state_error => s_main_error,
            i_state_resume => s_main_resume,
            o_state_return_held => s_main_return_held,
            i_state_release => s_main_release,
            o_state_resumed => s_main_resumed,
            o_state_canceled => s_main_canceled,
            iu5_state_cpu_address => su5_cpu_address,
            i_state_cpu_write => s_cpu_write,
            iu32_state_cpu_data => su32_cpu_write_data,
            ou32_state_cpu_data => su32_cpu_read_data,
            o_state_cpu_stopped => o_state_cpu_stopped,
            ou52_state_cpu_bus => ou52_state_cpu_bus,
            i_state_hold => s_game_hold,
            i_state_load => s_board_load,
            iu224_state_io => su512_board_load(223 downto 0),
            ou224_state_io => su224_io,
            iu4_state_irq => su512_board_load(227 downto 224),
            ou4_state_irq => su4_irq,
            i_state_memory_access => s_bank_session,
            i_state_memory_request => s_main_request,
            i_state_memory_write => s_main_write,
            iu24_state_memory_address => su24_main_address,
            iu16_state_memory_data => su16_main_write_data,
            iu2_state_memory_bytes => su2_main_bytes,
            o_state_memory_response => s_main_response,
            ou16_state_memory_data => su16_main_read_data,
            o_state_memory_busy => open,
            o_maintenance_idle => s_legacy_idle,
            i_state_video_flush => s_video_flush,
            i_state_sound_capture => s_sound_capture,
            o_state_sound_pending => open,
            o_state_sound_held => s_sound_held,
            o_state_sound_drained => s_sound_drained,
            o_state_sound_bus_idle => s_sound_bus_idle,
            i_state_sound_resume => s_sound_resume,
            i_state_sound_cpu_write => s_t80_load,
            iu256_state_sound_cpu => su256_t80_load,
            ou256_state_sound_cpu => su256_t80,
            i_state_fm_write => s_fm_write,
            iu16_state_chip_address => su16_chip_address,
            iu32_state_chip_data => su32_chip_data,
            ou32_state_fm_data => su32_fm_data,
            i_state_sound_memory_access => s_bank_session,
            i_state_sound_memory_request => s_sound_request,
            i_state_sound_memory_write => s_sound_write,
            iu16_state_sound_memory_address => su16_sound_address,
            iu8_state_sound_memory_data => su8_sound_write_data,
            o_state_sound_memory_response => s_sound_response,
            ou8_state_sound_memory_data => su8_sound_read_data,
            iu16_state_adpcm => su512_board_load(335 downto 320),
            ou16_state_adpcm => su16_adpcm,
            i_state_adpcm_write => s_adpcm_write,
            ou32_state_adpcm_data => su32_adpcm_data,
            i_state_rom_flush => s_rom_flush,
            i_state_sdram_prepare => s_sdram_prepare,
            o_state_sdram_aligned => s_sdram_aligned,
            o_state_transport_idle => s_transport_idle,
            o_state_board_idle => s_main_bus_idle,
            iu16_state_mixer => su512_board_load(351 downto 336),
            ou16_state_mixer => su16_mixer,
            iu2_state_fm_startup => su512_board_load(353 downto 352),
            ou2_state_fm_startup => su2_fm_startup,
            i_state_nvram_quiesce => s_nvram_quiesce,
            i_state_legacy_quiesce => s_legacy_quiesce,
            o_state_nvram_quiesced => s_nvram_quiesced,
            i_state_reconcile => s_nvram_reconcile,
            i_state_scores_ready => s_scores_ready,
            iu32_state_cadence => su512_board_load(287 downto 256),
            iu18_state_beam => su512_board_load(305 downto 288),
            ou32_state_cadence => su32_cadence,
            ou18_state_beam => su18_beam,
            o_state_aligned => s_aligned,
            i_state_private_return => s_private_return,
            o_state_rom_identity_valid => s_rom_identity_valid,
            o_state_rom_identity_error => o_state_rom_identity_error,
            ou32_state_rom_identity => ou32_state_rom_identity
        );
    access_barrier : entity work.rabbitpunch_state_machine_access
        generic map (
            GINT_TIMEOUT_CYCLES => GINT_STATE_TIMEOUT_CYCLES
        )
        port map (
            i_clk => i_clk,
            i_reset => s_reset,
            i_acquire => i_state_acquire and s_rom_identity_valid,
            i_cancel => i_state_cancel,
            i_release => i_state_release,
            i_incomplete => i_state_incomplete,
            i_nvram_quiesced => s_nvram_quiesced,
            i_nvram_ready => s_scores_initialized,
            i_legacy_idle => s_legacy_idle,
            i_main_bus_idle => s_main_bus_idle,
            i_sound_bus_idle => s_sound_bus_idle,
            i_main_held => s_main_held,
            i_main_error => s_main_error,
            i_sound_held => s_sound_held,
            i_sound_drained => s_sound_drained,
            i_transport_idle => s_transport_idle,
            i_banks_idle => s_banks_idle,
            i_main_return_held => s_main_return_held,
            i_main_resumed => s_main_resumed,
            i_main_resume_canceled => s_main_canceled,
            i_aligned => s_release_aligned,
            i_scores_ready_load => s_board_load,
            i_scores_ready_data => su512_board_load(354),
            o_scores_ready => s_scores_ready,
            o_ready => s_access_ready,
            o_busy => o_state_busy,
            o_held => s_held,
            o_finished => o_state_finished,
            o_canceled => o_state_canceled,
            ou4_error => ou4_state_error,
            o_reset_drained => o_state_reset_drained,
            o_pause => s_pause,
            o_nvram_quiesce => s_nvram_quiesce,
            o_legacy_quiesce => s_legacy_quiesce,
            o_nvram_reconcile => s_nvram_reconcile,
            o_main_capture => s_main_capture,
            o_sound_capture => s_sound_capture,
            o_capture_cancel => s_capture_cancel,
            o_game_hold => s_game_hold,
            o_video_flush => s_video_flush,
            o_rom_flush => s_rom_flush,
            o_bank_session => s_bank_session,
            o_main_resume => s_main_resume,
            o_private_return => s_private_return,
            o_main_release => s_main_release,
            o_sound_resume => s_sound_resume,
            o_sdram_prepare => s_sdram_prepare
        );
    banks : entity work.rabbitpunch_state_banks
        port map (
            i_clk => i_clk,
            i_initialize => s_reset,
            i_session => s_bank_session,
            i_machine_held => s_held,
            i_apply_begin => i_state_apply_begin,
            i_byte_request => i_state_byte_request,
            o_byte_ready => o_state_byte_ready,
            i_byte_write => i_state_byte_write,
            iu18_byte_address => iu18_state_byte_address,
            iu8_byte_data => iu8_state_byte_data,
            o_byte_response => o_state_byte_response,
            o_byte_error => o_state_byte_error,
            ou8_byte_data => ou8_state_byte_data,
            i_commit => i_state_commit,
            o_committed => o_state_committed,
            o_commit_error => o_state_commit_error,
            o_idle => s_banks_idle,
            ou5_m68k_address => su5_cpu_address,
            iu32_m68k_data => su32_cpu_read_data,
            o_m68k_write => s_cpu_write,
            ou32_m68k_data => su32_cpu_write_data,
            iu256_t80_data => su256_t80,
            ou256_t80_data => su256_t80_load,
            o_t80_load => s_t80_load,
            iu512_board_data => su512_board,
            ou512_board_data => su512_board_load,
            o_board_load => s_board_load,
            ou16_chip_address => su16_chip_address,
            iu32_fm_data => su32_fm_data,
            iu32_adpcm_data => su32_adpcm_data,
            ou32_chip_data => su32_chip_data,
            o_fm_write => s_fm_write,
            o_adpcm_write => s_adpcm_write,
            o_main_request => s_main_request,
            o_main_write => s_main_write,
            ou24_main_address => su24_main_address,
            ou16_main_data => su16_main_write_data,
            ou2_main_bytes => su2_main_bytes,
            i_main_response => s_main_response,
            iu16_main_data => su16_main_read_data,
            o_sound_request => s_sound_request,
            o_sound_write => s_sound_write,
            ou16_sound_address => su16_sound_address,
            ou8_sound_data => su8_sound_write_data,
            i_sound_response => s_sound_response,
            iu8_sound_data => su8_sound_read_data
        );
end architecture;
