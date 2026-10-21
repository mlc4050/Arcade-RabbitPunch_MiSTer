-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_config.all;

-- Physical clock boundary for the single-clock machine. The shifted clock
-- drives only the external SDRAM pin; game reset never resets the PLL.
entity rabbitpunch_clocked_machine is
    generic (
        GINT_SDRAM_READ_CAPTURE_ADJUST : natural range 0 to 2 := 1;
        GSTR_SDRAM_PHASE_SHIFT : string := "5357 ps";
        GINT_IMAGE_BYTES : positive := CINT_ROM_IMAGE_SIZE;
        GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000";
        GBOOL_STATE_CAPABLE : boolean := false
    );
    port (
        i_reference_clk : in std_logic;
        o_system_clk : out std_logic;
        o_sdram_clk : out std_logic;
        o_pll_locked : out std_logic;
        i_cold_reset : in std_logic;
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
        o_scanout_underflow : out std_logic;
        i_state_capture : in std_logic := '0';
        i_state_cancel : in std_logic := '0';
        o_state_pending : out std_logic := '0';
        o_state_held : out std_logic := '0';
        o_state_error : out std_logic := '0';
        i_state_resume : in std_logic := '0';
        o_state_return_held : out std_logic := '0';
        i_state_release : in std_logic := '0';
        o_state_resumed : out std_logic := '0';
        o_state_canceled : out std_logic := '0';
        iu5_state_cpu_address : in unsigned(4 downto 0) := (others => '0');
        i_state_cpu_write : in std_logic := '0';
        iu32_state_cpu_data : in unsigned(31 downto 0) := (others => '0');
        ou32_state_cpu_data : out unsigned(31 downto 0) := (others => '0');
        o_state_cpu_stopped : out std_logic := '0';
        ou52_state_cpu_bus : out unsigned(51 downto 0) := (others => '0');
        i_state_hold : in std_logic := '0';
        i_state_load : in std_logic := '0';
        iu224_state_io : in unsigned(223 downto 0) := (others => '0');
        ou224_state_io : out unsigned(223 downto 0) := (others => '0');
        iu4_state_irq : in unsigned(3 downto 0) := (others => '0');
        ou4_state_irq : out unsigned(3 downto 0) := (others => '0');
        i_state_memory_access : in std_logic := '0';
        i_state_memory_request : in std_logic := '0';
        i_state_memory_write : in std_logic := '0';
        iu24_state_memory_address : in unsigned(23 downto 0) := (others => '0');
        iu16_state_memory_data : in unsigned(15 downto 0) := (others => '0');
        iu2_state_memory_bytes : in unsigned(1 downto 0) := (others => '0');
        o_state_memory_response : out std_logic := '0';
        ou16_state_memory_data : out unsigned(15 downto 0) := (others => '0');
        o_state_memory_busy : out std_logic := '0';
        o_maintenance_idle : out std_logic := '0';
        i_state_video_flush : in std_logic := '0';
        i_state_sound_capture : in std_logic := '0';
        o_state_sound_pending : out std_logic := '0';
        o_state_sound_held : out std_logic := '0';
        o_state_sound_drained : out std_logic := '0';
        o_state_sound_bus_idle : out std_logic := '0';
        i_state_sound_resume : in std_logic := '0';
        i_state_sound_cpu_write : in std_logic := '0';
        iu256_state_sound_cpu : in unsigned(255 downto 0) := (others => '0');
        ou256_state_sound_cpu : out unsigned(255 downto 0) := (others => '0');
        i_state_fm_write : in std_logic := '0';
        iu16_state_chip_address : in unsigned(15 downto 0) := (others => '0');
        iu32_state_chip_data : in unsigned(31 downto 0) := (others => '0');
        ou32_state_fm_data : out unsigned(31 downto 0) := (others => '0');
        i_state_sound_memory_access : in std_logic := '0';
        i_state_sound_memory_request : in std_logic := '0';
        i_state_sound_memory_write : in std_logic := '0';
        iu16_state_sound_memory_address : in unsigned(15 downto 0) := (others => '0');
        iu8_state_sound_memory_data : in unsigned(7 downto 0) := (others => '0');
        o_state_sound_memory_response : out std_logic := '0';
        ou8_state_sound_memory_data : out unsigned(7 downto 0) := (others => '0');
        iu16_state_adpcm : in unsigned(15 downto 0) := (others => '0');
        ou16_state_adpcm : out unsigned(15 downto 0) := (others => '0');
        i_state_adpcm_write : in std_logic := '0';
        ou32_state_adpcm_data : out unsigned(31 downto 0) := (others => '0');
        i_state_rom_flush : in std_logic := '0';
        o_state_transport_idle : out std_logic := '0';
        o_state_board_idle : out std_logic := '0';
        iu16_state_mixer : in unsigned(15 downto 0) := (others => '0');
        ou16_state_mixer : out unsigned(15 downto 0) := (others => '0');
        iu2_state_fm_startup : in unsigned(1 downto 0) := (others => '0');
        ou2_state_fm_startup : out unsigned(1 downto 0) := (others => '0');
        i_state_nvram_quiesce : in std_logic := '0';
        i_state_legacy_quiesce : in std_logic := '0';
        o_state_nvram_quiesced : out std_logic := '0';
        i_state_reconcile : in std_logic := '0';
        i_state_scores_ready : in std_logic := '0';
        iu32_state_cadence : in unsigned(31 downto 0) := (others => '0');
        iu18_state_beam : in unsigned(17 downto 0) := (others => '0');
        ou32_state_cadence : out unsigned(31 downto 0) := (others => '0');
        ou18_state_beam : out unsigned(17 downto 0) := (others => '0');
        o_state_aligned : out std_logic := '0';
        i_state_private_return : in std_logic := '0';
        o_state_rom_identity_valid : out std_logic := '0';
        o_state_rom_identity_error : out std_logic := '0';
        ou32_state_rom_identity : out unsigned(31 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_clocked_machine is
    signal s_system_clk, s_locked, s_initialize, s_framework_reset : std_logic;
begin
    o_system_clk <= s_system_clk;
    o_pll_locked <= s_locked;
    pll : entity work.rabbitpunch_pll
        generic map (
            GSTR_SDRAM_PHASE_SHIFT => GSTR_SDRAM_PHASE_SHIFT
        )
        port map (
            i_reference_clk => i_reference_clk,
            i_reset => i_cold_reset,
            o_system_clk => s_system_clk,
            o_sdram_clk => o_sdram_clk,
            o_locked => s_locked
        );
    initialization : entity work.rabbitpunch_reset_release
        port map (
            i_clk => s_system_clk,
            i_asynchronous_reset => i_cold_reset or not s_locked,
            o_reset => s_initialize
        );
    gameplay_reset : entity work.rabbitpunch_reset_release
        port map (
            i_clk => s_system_clk,
            i_asynchronous_reset => i_framework_reset,
            o_reset => s_framework_reset
        );
    machine : entity work.rabbitpunch_machine
        generic map (
            GINT_SDRAM_READ_CAPTURE_ADJUST => GINT_SDRAM_READ_CAPTURE_ADJUST,
            GINT_IMAGE_BYTES => GINT_IMAGE_BYTES,
            GU16_DIP_DEFAULT => GU16_DIP_DEFAULT,
            GBOOL_STATE_CAPABLE => GBOOL_STATE_CAPABLE
        )
        port map (
            i_clk => s_system_clk,
            i_initialize => s_initialize,
            i_framework_reset => s_framework_reset,
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
            o_ready => o_ready,
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
            i_state_capture => i_state_capture,
            i_state_cancel => i_state_cancel,
            o_state_pending => o_state_pending,
            o_state_held => o_state_held,
            o_state_error => o_state_error,
            i_state_resume => i_state_resume,
            o_state_return_held => o_state_return_held,
            i_state_release => i_state_release,
            o_state_resumed => o_state_resumed,
            o_state_canceled => o_state_canceled,
            iu5_state_cpu_address => iu5_state_cpu_address,
            i_state_cpu_write => i_state_cpu_write,
            iu32_state_cpu_data => iu32_state_cpu_data,
            ou32_state_cpu_data => ou32_state_cpu_data,
            o_state_cpu_stopped => o_state_cpu_stopped,
            ou52_state_cpu_bus => ou52_state_cpu_bus,
            i_state_hold => i_state_hold,
            i_state_load => i_state_load,
            iu224_state_io => iu224_state_io,
            ou224_state_io => ou224_state_io,
            iu4_state_irq => iu4_state_irq,
            ou4_state_irq => ou4_state_irq,
            i_state_memory_access => i_state_memory_access,
            i_state_memory_request => i_state_memory_request,
            i_state_memory_write => i_state_memory_write,
            iu24_state_memory_address => iu24_state_memory_address,
            iu16_state_memory_data => iu16_state_memory_data,
            iu2_state_memory_bytes => iu2_state_memory_bytes,
            o_state_memory_response => o_state_memory_response,
            ou16_state_memory_data => ou16_state_memory_data,
            o_state_memory_busy => o_state_memory_busy,
            o_maintenance_idle => o_maintenance_idle,
            i_state_video_flush => i_state_video_flush,
            i_state_sound_capture => i_state_sound_capture,
            o_state_sound_pending => o_state_sound_pending,
            o_state_sound_held => o_state_sound_held,
            o_state_sound_drained => o_state_sound_drained,
            o_state_sound_bus_idle => o_state_sound_bus_idle,
            i_state_sound_resume => i_state_sound_resume,
            i_state_sound_cpu_write => i_state_sound_cpu_write,
            iu256_state_sound_cpu => iu256_state_sound_cpu,
            ou256_state_sound_cpu => ou256_state_sound_cpu,
            i_state_fm_write => i_state_fm_write,
            iu16_state_chip_address => iu16_state_chip_address,
            iu32_state_chip_data => iu32_state_chip_data,
            ou32_state_fm_data => ou32_state_fm_data,
            i_state_sound_memory_access => i_state_sound_memory_access,
            i_state_sound_memory_request => i_state_sound_memory_request,
            i_state_sound_memory_write => i_state_sound_memory_write,
            iu16_state_sound_memory_address => iu16_state_sound_memory_address,
            iu8_state_sound_memory_data => iu8_state_sound_memory_data,
            o_state_sound_memory_response => o_state_sound_memory_response,
            ou8_state_sound_memory_data => ou8_state_sound_memory_data,
            iu16_state_adpcm => iu16_state_adpcm,
            ou16_state_adpcm => ou16_state_adpcm,
            i_state_adpcm_write => i_state_adpcm_write,
            ou32_state_adpcm_data => ou32_state_adpcm_data,
            i_state_rom_flush => i_state_rom_flush,
            o_state_transport_idle => o_state_transport_idle,
            o_state_board_idle => o_state_board_idle,
            iu16_state_mixer => iu16_state_mixer,
            ou16_state_mixer => ou16_state_mixer,
            iu2_state_fm_startup => iu2_state_fm_startup,
            ou2_state_fm_startup => ou2_state_fm_startup,
            i_state_nvram_quiesce => i_state_nvram_quiesce,
            i_state_legacy_quiesce => i_state_legacy_quiesce,
            o_state_nvram_quiesced => o_state_nvram_quiesced,
            i_state_reconcile => i_state_reconcile,
            i_state_scores_ready => i_state_scores_ready,
            iu32_state_cadence => iu32_state_cadence,
            iu18_state_beam => iu18_state_beam,
            ou32_state_cadence => ou32_state_cadence,
            ou18_state_beam => ou18_state_beam,
            o_state_aligned => o_state_aligned,
            i_state_private_return => i_state_private_return,
            o_state_rom_identity_valid => o_state_rom_identity_valid,
            o_state_rom_identity_error => o_state_rom_identity_error,
            ou32_state_rom_identity => ou32_state_rom_identity
        );
end architecture;
