-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_config.all;
use work.rabbitpunch_state_abi.all;

-- Experimental complete MiSTer composition. State controls stay disabled
-- until full-game continuation and physical timing gates pass.

entity rabbitpunch_state_emu is
    generic (
        GBOOL_ENABLE_STATES : boolean := false;
        GBOOL_DEBUG_ENABLE : boolean := false;
        GU32_BUILD_ID : unsigned(31 downto 0) := (others => '0')
    );
    port (
        i_clk_50m : in std_logic;
        i_reset : in std_logic;
        iou46_hps_bus : inout unsigned(45 downto 0);
        o_clk_video : out std_logic;
        o_ce_pixel : out std_logic;
        ou13_video_arx : out unsigned(12 downto 0);
        ou13_video_ary : out unsigned(12 downto 0);
        ou8_vga_r : out unsigned(7 downto 0);
        ou8_vga_g : out unsigned(7 downto 0);
        ou8_vga_b : out unsigned(7 downto 0);
        o_vga_hs : out std_logic;
        o_vga_vs : out std_logic;
        o_vga_de : out std_logic;
        o_vga_f1 : out std_logic;
        ou2_vga_sl : out unsigned(1 downto 0);
        o_vga_scaler : out std_logic;
        o_vga_disable : out std_logic;
        iu12_hdmi_width : in unsigned(11 downto 0);
        iu12_hdmi_height : in unsigned(11 downto 0);
        o_hdmi_freeze : out std_logic;
        o_hdmi_blackout : out std_logic;
        o_hdmi_bob_deint : out std_logic;
        iu6_lfb_fmt : in unsigned(5 downto 0);
        iu32_lfb_base : in unsigned(31 downto 0);
        iu12_lfb_width : in unsigned(11 downto 0);
        iu12_lfb_height : in unsigned(11 downto 0);
        iu14_lfb_stride : in unsigned(13 downto 0);
        o_fb_en : out std_logic;
        ou5_fb_format : out unsigned(4 downto 0);
        ou12_fb_width : out unsigned(11 downto 0);
        ou12_fb_height : out unsigned(11 downto 0);
        ou32_fb_base : out unsigned(31 downto 0);
        ou14_fb_stride : out unsigned(13 downto 0);
        i_fb_vbl : in std_logic;
        i_fb_ll : in std_logic;
        o_fb_force_blank : out std_logic;
        o_led_user : out std_logic;
        ou2_led_power : out unsigned(1 downto 0);
        ou2_led_disk : out unsigned(1 downto 0);
        ou2_buttons : out unsigned(1 downto 0);
        i_clk_audio : in std_logic;
        ou16_audio_l : out unsigned(15 downto 0);
        ou16_audio_r : out unsigned(15 downto 0);
        o_audio_s : out std_logic;
        ou2_audio_mix : out unsigned(1 downto 0);
        iou4_adc_bus : inout unsigned(3 downto 0);
        o_sd_sck : out std_logic;
        o_sd_mosi : out std_logic;
        i_sd_miso : in std_logic;
        o_sd_cs : out std_logic;
        i_sd_cd : in std_logic;
        o_ddram_clk : out std_logic;
        i_ddram_busy : in std_logic;
        ou8_ddram_burstcnt : out unsigned(7 downto 0);
        ou29_ddram_addr : out unsigned(28 downto 0);
        iu64_ddram_dout : in unsigned(63 downto 0);
        i_ddram_dout_ready : in std_logic;
        o_ddram_rd : out std_logic;
        ou64_ddram_din : out unsigned(63 downto 0);
        ou8_ddram_be : out unsigned(7 downto 0);
        o_ddram_we : out std_logic;
        o_sdram_clk : out std_logic;
        o_sdram_cke : out std_logic;
        ou13_sdram_a : out unsigned(12 downto 0);
        ou2_sdram_ba : out unsigned(1 downto 0);
        iou16_sdram_dq : inout unsigned(15 downto 0);
        o_sdram_dqml : out std_logic;
        o_sdram_dqmh : out std_logic;
        o_sdram_ncs : out std_logic;
        o_sdram_ncas : out std_logic;
        o_sdram_nras : out std_logic;
        o_sdram_nwe : out std_logic;
        i_uart_cts : in std_logic;
        o_uart_rts : out std_logic;
        i_uart_rxd : in std_logic;
        o_uart_txd : out std_logic;
        o_uart_dtr : out std_logic;
        i_uart_dsr : in std_logic;
        iu7_user_in : in unsigned(6 downto 0);
        ou7_user_out : out unsigned(6 downto 0);
        i_osd_status : in std_logic
    );
end entity;

architecture rtl of rabbitpunch_state_emu is
    signal s_pin_clk_video : std_logic;
    signal s_pin_ce_pixel : std_logic;
    signal su13_pin_video_arx : unsigned(12 downto 0);
    signal su13_pin_video_ary : unsigned(12 downto 0);
    signal su8_pin_vga_r : unsigned(7 downto 0);
    signal su8_pin_vga_g : unsigned(7 downto 0);
    signal su8_pin_vga_b : unsigned(7 downto 0);
    signal s_pin_vga_hs : std_logic;
    signal s_pin_vga_vs : std_logic;
    signal s_pin_vga_de : std_logic;
    signal s_pin_vga_f1 : std_logic;
    signal su2_pin_vga_sl : unsigned(1 downto 0);
    signal s_pin_vga_scaler : std_logic;
    signal s_pin_vga_disable : std_logic;
    signal s_pin_hdmi_freeze : std_logic;
    signal s_pin_hdmi_blackout : std_logic;
    signal s_pin_hdmi_bob_deint : std_logic;
    signal s_pin_fb_en : std_logic;
    signal su5_pin_fb_format : unsigned(4 downto 0);
    signal su12_pin_fb_width : unsigned(11 downto 0);
    signal su12_pin_fb_height : unsigned(11 downto 0);
    signal su32_pin_fb_base : unsigned(31 downto 0);
    signal su14_pin_fb_stride : unsigned(13 downto 0);
    signal s_pin_fb_force_blank : std_logic;
    signal s_pin_led_user : std_logic;
    signal su2_pin_led_power : unsigned(1 downto 0);
    signal su2_pin_led_disk : unsigned(1 downto 0);
    signal su2_pin_buttons : unsigned(1 downto 0);
    signal su16_pin_audio_l : unsigned(15 downto 0);
    signal su16_pin_audio_r : unsigned(15 downto 0);
    signal s_pin_audio_s : std_logic;
    signal su2_pin_audio_mix : unsigned(1 downto 0);
    signal s_pin_sd_sck : std_logic;
    signal s_pin_sd_mosi : std_logic;
    signal s_pin_sd_cs : std_logic;
    signal s_pin_ddram_clk : std_logic;
    signal su8_pin_ddram_burstcnt : unsigned(7 downto 0);
    signal su29_pin_ddram_addr : unsigned(28 downto 0);
    signal s_pin_ddram_rd : std_logic;
    signal su64_pin_ddram_din : unsigned(63 downto 0);
    signal su8_pin_ddram_be : unsigned(7 downto 0);
    signal s_pin_ddram_we : std_logic;
    signal s_pin_sdram_clk : std_logic;
    signal s_pin_sdram_cke : std_logic;
    signal su13_pin_sdram_a : unsigned(12 downto 0);
    signal su2_pin_sdram_ba : unsigned(1 downto 0);
    signal s_pin_sdram_dqml : std_logic;
    signal s_pin_sdram_dqmh : std_logic;
    signal s_pin_sdram_ncs : std_logic;
    signal s_pin_sdram_ncas : std_logic;
    signal s_pin_sdram_nras : std_logic;
    signal s_pin_sdram_nwe : std_logic;
    signal s_pin_uart_rts : std_logic;
    signal s_pin_uart_txd : std_logic;
    signal s_pin_uart_dtr : std_logic;
    signal su7_pin_user_out : unsigned(6 downto 0);
    signal s_clk_sys : std_logic;
    signal su128_status : unsigned(127 downto 0);
    signal su32_joystick0 : unsigned(31 downto 0);
    signal su32_joystick1 : unsigned(31 downto 0);
    signal su32_game_joystick0, su32_game_joystick1 : unsigned(31 downto 0);
    signal su11_key_event : unsigned(10 downto 0);
    signal su2_host_buttons : unsigned(1 downto 0);
    signal su2_sdram_byte_mask : unsigned(1 downto 0);
    signal su16_menu_mask : unsigned(15 downto 0);
    signal su16_score_menu_mask : unsigned(15 downto 0);
    signal su16_file_index : unsigned(15 downto 0);
    signal su27_file_address : unsigned(26 downto 0);
    signal su8_file_data : unsigned(7 downto 0);
    signal su8_upload_data : unsigned(7 downto 0);
    signal s_file_download : std_logic;
    signal s_file_upload : std_logic;
    signal s_file_write : std_logic;
    signal s_file_wait : std_logic;
    signal s_upload_request : std_logic;
    signal s_horizontal_blank : std_logic;
    signal s_vertical_blank : std_logic;
    signal s_native_pixel_enable : std_logic;
    signal s_native_horizontal_sync : std_logic;
    signal s_native_vertical_sync : std_logic;
    signal s_forced_scandoubler : std_logic;
    signal s_direct_video : std_logic;
    signal s_loader_busy : std_logic;
    signal s_loader_read_valid : std_logic;
    signal s_loader_read : std_logic;
    signal s_loader_write : std_logic;
    signal su8_loader_burst_count : unsigned(7 downto 0);
    signal su8_loader_byte_enables : unsigned(7 downto 0);
    signal su29_loader_word_address : unsigned(28 downto 0);
    signal su64_loader_read_data : unsigned(63 downto 0);
    signal su64_loader_write_data : unsigned(63 downto 0);
    signal s_crt_pixel_enable : std_logic;
    signal s_crt_horizontal_sync : std_logic;
    signal s_crt_vertical_sync : std_logic;
    signal s_crt_horizontal_blank : std_logic;
    signal s_crt_vertical_blank : std_logic;
    signal su8_crt_red : unsigned(7 downto 0);
    signal su8_crt_green : unsigned(7 downto 0);
    signal su8_crt_blue : unsigned(7 downto 0);
    signal s_crt_size_enable : std_logic;
    signal su8_native_red : unsigned(7 downto 0);
    signal su8_native_green : unsigned(7 downto 0);
    signal su8_native_blue : unsigned(7 downto 0);
    signal s_loading : std_logic;
    signal s_downloading : std_logic;
    signal s_ready : std_logic;
    signal s_error : std_logic;
    signal s_underflow : std_logic;
    signal s_pll_locked : std_logic;
    signal s_paused : std_logic;
    signal s_scanout_armed : std_logic;
    signal s_audio_sample : std_logic;
    signal s_adpcm_busy : std_logic;
    signal s_cpu_request : std_logic;
    signal s_cpu_write : std_logic;
    signal s_sound_request : std_logic;
    signal s_sound_write : std_logic;
    signal su24_cpu_address : unsigned(23 downto 0);
    signal su16_cpu_data : unsigned(15 downto 0);
    signal su16_sound_address : unsigned(15 downto 0);
    signal su8_sound_data : unsigned(7 downto 0);
    signal su2_cpu_bytes : unsigned(1 downto 0);
    signal su9_beam_x : unsigned(8 downto 0);
    signal su9_beam_y : unsigned(8 downto 0);
    signal s_initialize : std_logic;
    signal s_framework_reset : std_logic;
    signal s_ui_reset : std_logic;
    signal s_state_save : std_logic;
    signal s_state_restore : std_logic;
    signal s_state_ready : std_logic;
    signal s_state_busy : std_logic;
    signal s_state_finished : std_logic;
    signal s_state_success : std_logic;
    signal s_state_flush : std_logic;
    signal s_state_unavailable : std_logic;
    signal s_state_save_unavailable, s_state_incomplete : std_logic;
    signal s_status_set : std_logic;
    signal su128_status_data : unsigned(127 downto 0);
    signal su2_state_slot : unsigned(1 downto 0);
    signal s_state_read : std_logic;
    signal s_state_write : std_logic;
    signal s_state_ddr_busy : std_logic;
    signal s_state_read_valid : std_logic;
    signal su29_state_address : unsigned(28 downto 0);
    signal su64_state_write_data : unsigned(63 downto 0);
    signal su64_state_read_data : unsigned(63 downto 0);
    signal su16_dips : unsigned(15 downto 0);
    signal s_hiscore_enabled : std_logic;
    signal su32_config_identity : unsigned(31 downto 0);
begin
    su32_game_joystick0 <= F_STATE_GAME_ACTIONS(su32_joystick0, GBOOL_ENABLE_STATES);
    su32_game_joystick1 <= F_STATE_GAME_ACTIONS(su32_joystick1, GBOOL_ENABLE_STATES);
    o_clk_video <= s_pin_clk_video;
    o_ce_pixel <= s_pin_ce_pixel;
    ou13_video_arx <= su13_pin_video_arx;
    ou13_video_ary <= su13_pin_video_ary;
    ou8_vga_r <= su8_pin_vga_r;
    ou8_vga_g <= su8_pin_vga_g;
    ou8_vga_b <= su8_pin_vga_b;
    o_vga_hs <= s_pin_vga_hs;
    o_vga_vs <= s_pin_vga_vs;
    o_vga_de <= s_pin_vga_de;
    o_vga_f1 <= s_pin_vga_f1;
    ou2_vga_sl <= su2_pin_vga_sl;
    o_vga_scaler <= s_pin_vga_scaler;
    o_vga_disable <= s_pin_vga_disable;
    o_hdmi_freeze <= s_pin_hdmi_freeze;
    o_hdmi_blackout <= s_pin_hdmi_blackout;
    o_hdmi_bob_deint <= s_pin_hdmi_bob_deint;
    o_fb_en <= s_pin_fb_en;
    ou5_fb_format <= su5_pin_fb_format;
    ou12_fb_width <= su12_pin_fb_width;
    ou12_fb_height <= su12_pin_fb_height;
    ou32_fb_base <= su32_pin_fb_base;
    ou14_fb_stride <= su14_pin_fb_stride;
    o_fb_force_blank <= s_pin_fb_force_blank;
    o_led_user <= s_pin_led_user;
    ou2_led_power <= su2_pin_led_power;
    ou2_led_disk <= su2_pin_led_disk;
    ou2_buttons <= su2_pin_buttons;
    ou16_audio_l <= su16_pin_audio_l;
    ou16_audio_r <= su16_pin_audio_r;
    o_audio_s <= s_pin_audio_s;
    ou2_audio_mix <= su2_pin_audio_mix;
    o_sd_sck <= s_pin_sd_sck;
    o_sd_mosi <= s_pin_sd_mosi;
    o_sd_cs <= s_pin_sd_cs;
    o_ddram_clk <= s_pin_ddram_clk;
    ou8_ddram_burstcnt <= su8_pin_ddram_burstcnt;
    ou29_ddram_addr <= su29_pin_ddram_addr;
    o_ddram_rd <= s_pin_ddram_rd;
    ou64_ddram_din <= su64_pin_ddram_din;
    ou8_ddram_be <= su8_pin_ddram_be;
    o_ddram_we <= s_pin_ddram_we;
    o_sdram_clk <= s_pin_sdram_clk;
    o_sdram_cke <= s_pin_sdram_cke;
    ou13_sdram_a <= su13_pin_sdram_a;
    ou2_sdram_ba <= su2_pin_sdram_ba;
    o_sdram_dqml <= s_pin_sdram_dqml;
    o_sdram_dqmh <= s_pin_sdram_dqmh;
    o_sdram_ncs <= s_pin_sdram_ncs;
    o_sdram_ncas <= s_pin_sdram_ncas;
    o_sdram_nras <= s_pin_sdram_nras;
    o_sdram_nwe <= s_pin_sdram_nwe;
    o_uart_rts <= s_pin_uart_rts;
    o_uart_txd <= s_pin_uart_txd;
    o_uart_dtr <= s_pin_uart_dtr;
    ou7_user_out <= su7_pin_user_out;
    iou4_adc_bus <= (others => 'Z');
    s_pin_sd_sck <= 'Z';
    s_pin_sd_mosi <= 'Z';
    s_pin_sd_cs <= 'Z';
    su7_pin_user_out <= (others => '1');
    s_pin_uart_rts <= '0';
    s_pin_uart_txd <= '0';
    s_pin_uart_dtr <= '0';
    s_pin_vga_f1 <= '0';
    s_pin_vga_scaler <= '0';
    s_pin_vga_disable <= '0';
    s_pin_hdmi_freeze <= '0';
    s_pin_hdmi_blackout <= '0';
    s_pin_hdmi_bob_deint <= '0';
    su2_pin_led_disk <= (others => '0');
    su2_pin_led_power <= (others => '0');
    su2_pin_buttons <= (others => '0');
    s_pin_audio_s <= '1';
    su16_pin_audio_r <= su16_pin_audio_l;
    s_pin_clk_video <= s_clk_sys;
    s_pin_ddram_clk <= s_clk_sys;
    s_pin_sdram_dqmh <= su2_sdram_byte_mask(1);
    s_pin_sdram_dqml <= su2_sdram_byte_mask(0);
    s_crt_size_enable <= s_direct_video or not s_forced_scandoubler when su128_status(46 downto 44) = 0 else s_direct_video;
    su16_menu_mask <= su16_score_menu_mask or (15 downto 10 => '0') & s_state_save_unavailable & s_state_unavailable & (not su128_status(94) or not s_crt_size_enable) & not su128_status(94) & s_direct_video & (4 downto 0 => '0');
    s_ui_reset <= s_initialize or s_framework_reset or su128_status(0) or su2_host_buttons(1) or s_downloading or s_loading;
    su32_config_identity <= (31 downto 17 => '0') & s_hiscore_enabled & su16_dips;
    pll : entity work.rabbitpunch_pll
        generic map (
            GSTR_SDRAM_PHASE_SHIFT => "5357 ps"
        )
        port map (
            i_reference_clk => i_clk_50m,
            i_reset => '0',
            o_system_clk => s_clk_sys,
            o_sdram_clk => s_pin_sdram_clk,
            o_locked => s_pll_locked
        );

    initialization : entity work.rabbitpunch_reset_release
        port map (
            i_clk => s_clk_sys,
            i_asynchronous_reset => not s_pll_locked,
            o_reset => s_initialize
        );

    framework_reset : entity work.rabbitpunch_reset_release
        port map (
            i_clk => s_clk_sys,
            i_asynchronous_reset => i_reset,
            o_reset => s_framework_reset
        );

    status_led : entity work.rabbitpunch_status_led
        port map (
            i_clk => s_clk_sys,
            i_loading => s_loading,
            i_downloading => s_downloading,
            i_error => s_error,
            i_underflow => s_underflow,
            o_led => s_pin_led_user
        );

    host : entity work.rabbitpunch_host
        generic map (
            GSTR_CONFIG_STRING => F_STATE_CONFIG(GBOOL_ENABLE_STATES)
        )
        port map (
            i_clk => s_clk_sys,
            iou46_hps_bus => iou46_hps_bus,
            iu16_menu_mask => su16_menu_mask,
            ou128_status => su128_status,
            ou2_audio_mix => su2_pin_audio_mix,
            ou32_joystick0 => su32_joystick0,
            ou32_joystick1 => su32_joystick1,
            ou11_key_event => su11_key_event,
            ou2_buttons => su2_host_buttons,
            o_forced_scandoubler => s_forced_scandoubler,
            o_direct_video => s_direct_video,
            ou16_sdram_configuration => open,
            o_file_download => s_file_download,
            ou16_file_index => su16_file_index,
            o_file_write => s_file_write,
            ou27_file_byte_address => su27_file_address,
            ou8_file_data => su8_file_data,
            i_file_wait => s_file_wait,
            i_file_upload_request => s_upload_request,
            iu8_file_upload_index => to_unsigned(4, 8),
            iu8_file_upload_data => su8_upload_data,
            o_file_upload => s_file_upload,
            o_file_read => open,
            i_status_set => s_status_set,
            iu128_status_data => su128_status_data
        );

    machine : entity work.rabbitpunch_state_machine
        generic map (
            GINT_SDRAM_READ_CAPTURE_ADJUST => 1
        )
        port map (
            i_framework_reset => s_framework_reset,
            iu128_status => su128_status,
            iu2_host_buttons => su2_host_buttons,
            iu32_joystick0 => su32_game_joystick0,
            iu32_joystick1 => su32_game_joystick1,
            iu11_key_event => su11_key_event,
            i_osd_open => i_osd_status,
            i_debug_pause => '0',
            i_host_download => s_file_download,
            i_host_upload => s_file_upload,
            o_host_upload_request => s_upload_request,
            ou8_host_upload_data => su8_upload_data,
            ou16_host_menu_mask => su16_score_menu_mask,
            o_hiscore_enabled => s_hiscore_enabled,
            o_hiscore_config_error => open,
            o_hiscore_initialized => open,
            o_hiscore_saved_valid => open,
            o_hiscore_dirty => open,
            iu16_host_index => su16_file_index,
            i_host_write => s_file_write,
            iu27_host_byte_address => su27_file_address,
            iu8_host_data => su8_file_data,
            o_host_wait => s_file_wait,
            o_downloading => s_downloading,
            o_ddr_owner => open,
            o_pause_request => open,
            o_user_paused => open,
            i_maintenance_access => '0',
            i_maintenance_valid => '0',
            i_maintenance_write => '0',
            iu14_maintenance_byte_address => (others => '0'),
            iu8_maintenance_data => (others => '0'),
            o_maintenance_ready => open,
            o_maintenance_response_valid => open,
            ou8_maintenance_response_data => open,
            o_maintenance_pause => open,
            ou8_player1 => open,
            ou8_player2 => open,
            ou8_service => open,
            ou16_dips => su16_dips,
            o_ddr_mode => open,
            i_ddr_busy => s_loader_busy,
            ou8_ddr_burst_count => su8_loader_burst_count,
            ou29_ddr_word_address => su29_loader_word_address,
            iu64_ddr_read_data => su64_loader_read_data,
            i_ddr_read_valid => s_loader_read_valid,
            o_ddr_read => s_loader_read,
            ou64_ddr_write_data => su64_loader_write_data,
            ou8_ddr_byte_enables => su8_loader_byte_enables,
            o_ddr_write => s_loader_write,
            o_paused => s_paused,
            i_view_enable => '0',
            iu5_view_target => (others => '0'),
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            ou9_adpcm_pcm => open,
            ou16_mono_pcm => su16_pin_audio_l,
            o_audio_sample_marker => s_audio_sample,
            o_adpcm_busy => s_adpcm_busy,
            i_audio_view_enable => '0',
            iu11_audio_view_address => (others => '0'),
            ou8_audio_view_data => open,
            o_audio_debug_request => s_sound_request,
            o_audio_debug_write => s_sound_write,
            ou16_audio_debug_address => su16_sound_address,
            ou8_audio_debug_data => su8_sound_data,
            o_sound_command_write => open,
            ou8_sound_command => open,
            o_sound_pending => open,
            ou16_video_flags => open,
            ou9_scroll0_y => open,
            ou9_scroll0_x => open,
            ou9_scroll1_y => open,
            ou9_scroll1_x => open,
            ou6_sprite_count => open,
            ou6_sprite_priority => open,
            ou4_gga_selected => open,
            iu4_gga_view_address => (others => '0'),
            ou8_gga_view_data => open,
            o_gga_write => open,
            ou4_gga_write_address => open,
            ou8_gga_write_data => open,
            o_cpu_request => s_cpu_request,
            o_cpu_request_write => s_cpu_write,
            ou24_cpu_request_address => su24_cpu_address,
            ou16_cpu_request_data => su16_cpu_data,
            ou2_cpu_request_bytes => su2_cpu_bytes,
            o_image_valid => open,
            o_error => s_error,
            o_done => open,
            ou27_bytes_loaded => open,
            iou16_sdram_data => iou16_sdram_dq,
            ou13_sdram_address => su13_pin_sdram_a,
            ou2_sdram_bank => su2_pin_sdram_ba,
            ou2_sdram_byte_mask => su2_sdram_byte_mask,
            o_sdram_chip_select => s_pin_sdram_ncs,
            o_sdram_write_n => s_pin_sdram_nwe,
            o_sdram_row_n => s_pin_sdram_nras,
            o_sdram_column_n => s_pin_sdram_ncas,
            o_sdram_clock_enable => s_pin_sdram_cke,
            o_ready => s_ready,
            o_loading => s_loading,
            o_pixel_enable => s_native_pixel_enable,
            o_active => open,
            o_hsync => s_native_horizontal_sync,
            o_vsync => s_native_vertical_sync,
            o_hblank => s_horizontal_blank,
            o_vblank => s_vertical_blank,
            ou9_output_x => open,
            ou8_output_y => open,
            ou8_red => su8_native_red,
            ou8_green => su8_native_green,
            ou8_blue => su8_native_blue,
            ou9_horizontal_position => su9_beam_x,
            ou9_vertical_position => su9_beam_y,
            o_scanout_armed => s_scanout_armed,
            o_scanout_underflow => s_underflow,
            i_clk => s_clk_sys,
            i_initialize => s_initialize,
            i_state_save => s_state_save,
            i_state_restore => s_state_restore,
            i_state_cancel => s_ui_reset,
            iu2_state_slot => su2_state_slot,
            iu32_state_abi_signature => CU32_ABI_SIGNATURE,
            iu32_state_config_identity => su32_config_identity,
            o_state_ready => s_state_ready,
            o_state_busy => s_state_busy,
            o_state_finished => s_state_finished,
            o_state_success => s_state_success,
            o_state_presentation_flush => s_state_flush,
            o_state_ddr_read => s_state_read,
            o_state_ddr_write => s_state_write,
            ou29_state_ddr_word_address => su29_state_address,
            ou64_state_ddr_write_data => su64_state_write_data,
            i_state_ddr_busy => s_state_ddr_busy,
            i_state_ddr_read_valid => s_state_read_valid,
            iu64_state_ddr_read_data => su64_state_read_data,
            o_state_cpu_stopped => open,
            ou52_state_cpu_bus => open,
            o_state_restoring => open,
            o_state_incomplete => s_state_incomplete,
            o_state_run_release => open,
            ou8_state_error => open,
            o_state_rom_identity_valid => open,
            o_state_rom_identity_error => open,
            ou32_state_rom_identity => open
        );

    crt_geometry : entity work.rabbitpunch_crt_adjust
        port map (
            i_clk => s_clk_sys,
            i_initialize => s_initialize or s_state_flush,
            i_pixel_enable => s_native_pixel_enable,
            i_adjust => su128_status(94),
            i_size_enable => s_crt_size_enable,
            iu5_horizontal_size => su128_status(99 downto 95),
            iu7_horizontal_position => su128_status(106 downto 100),
            iu6_vertical_shift => su128_status(112 downto 107),
            iu8_red => su8_native_red,
            iu8_green => su8_native_green,
            iu8_blue => su8_native_blue,
            i_horizontal_sync => s_native_horizontal_sync,
            i_vertical_sync => s_native_vertical_sync,
            i_horizontal_blank => s_horizontal_blank,
            i_vertical_blank => s_vertical_blank,
            o_pixel_enable => s_crt_pixel_enable,
            ou8_red => su8_crt_red,
            ou8_green => su8_crt_green,
            ou8_blue => su8_crt_blue,
            o_horizontal_sync => s_crt_horizontal_sync,
            o_vertical_sync => s_crt_vertical_sync,
            o_horizontal_blank => s_crt_horizontal_blank,
            o_vertical_blank => s_crt_vertical_blank
        );

    video_options : entity work.rabbitpunch_video_options
        port map (
            i_clk => s_clk_sys,
            i_pixel_enable => s_crt_pixel_enable,
            iu8_red => su8_crt_red,
            iu8_green => su8_crt_green,
            iu8_blue => su8_crt_blue,
            i_horizontal_sync => s_crt_horizontal_sync,
            i_vertical_sync => s_crt_vertical_sync,
            i_horizontal_blank => s_crt_horizontal_blank,
            i_vertical_blank => s_crt_vertical_blank,
            i_forced_scandoubler => s_forced_scandoubler,
            i_direct_video => s_direct_video,
            iu3_effect => su128_status(46 downto 44),
            o_pixel_enable => s_pin_ce_pixel,
            ou8_red => su8_pin_vga_r,
            ou8_green => su8_pin_vga_g,
            ou8_blue => su8_pin_vga_b,
            o_horizontal_sync => s_pin_vga_hs,
            o_vertical_sync => s_pin_vga_vs,
            o_data_enable => s_pin_vga_de,
            ou2_scanlines => su2_pin_vga_sl
        );

    hdmi_presentation : entity work.rabbitpunch_state_hdmi_presentation
        port map (
            i_clk => s_clk_sys,
            i_initialize => not s_pll_locked,
            i_game_ready => s_ready and not s_loading and not s_error,
            i_loader_active => s_downloading or s_loading,
            i_direct_video => s_direct_video,
            iu2_rotation => su128_status(114 downto 113),
            i_native_pixel_enable => s_native_pixel_enable,
            iu8_native_red => su8_native_red,
            iu8_native_green => su8_native_green,
            iu8_native_blue => su8_native_blue,
            i_native_horizontal_sync_n => s_native_horizontal_sync,
            i_native_vertical_sync_n => s_native_vertical_sync,
            i_presented_pixel_enable => s_pin_ce_pixel,
            i_presented_vertical_sync => s_pin_vga_vs,
            i_presented_data_enable => s_pin_vga_de,
            iu12_hdmi_width => iu12_hdmi_width,
            iu12_hdmi_height => iu12_hdmi_height,
            iu2_aspect => su128_status(122 downto 121),
            iu3_scale => su128_status(68 downto 66),
            ou13_aspect_x => su13_pin_video_arx,
            ou13_aspect_y => su13_pin_video_ary,
            i_framebuffer_vertical_blank => i_fb_vbl,
            o_framebuffer_enable => s_pin_fb_en,
            o_framebuffer_force_blank => s_pin_fb_force_blank,
            ou5_framebuffer_format => su5_pin_fb_format,
            ou12_framebuffer_width => su12_pin_fb_width,
            ou12_framebuffer_height => su12_pin_fb_height,
            ou32_framebuffer_base => su32_pin_fb_base,
            ou14_framebuffer_stride => su14_pin_fb_stride,
            o_rotation_active => open,
            ou2_applied_rotation => open,
            o_discard_frame => open,
            o_queue_overflow => open,
            o_queue_empty => open,
            iu8_loader_burst_count => su8_loader_burst_count,
            iu29_loader_word_address => su29_loader_word_address,
            iu64_loader_write_data => su64_loader_write_data,
            iu8_loader_byte_enables => su8_loader_byte_enables,
            i_loader_read => s_loader_read,
            i_loader_write => s_loader_write,
            o_loader_busy => s_loader_busy,
            o_loader_read_valid => s_loader_read_valid,
            ou64_loader_read_data => su64_loader_read_data,
            i_ddr_busy => i_ddram_busy,
            i_ddr_read_valid => i_ddram_dout_ready,
            iu64_ddr_read_data => iu64_ddram_dout,
            ou8_ddr_burst_count => su8_pin_ddram_burstcnt,
            ou29_ddr_word_address => su29_pin_ddram_addr,
            ou64_ddr_write_data => su64_pin_ddram_din,
            ou8_ddr_byte_enables => su8_pin_ddram_be,
            o_ddr_read => s_pin_ddram_rd,
            o_ddr_write => s_pin_ddram_we,
            i_native_data_enable => not (s_horizontal_blank or s_vertical_blank),
            i_state_flush => s_state_flush,
            i_state_active => s_state_busy,
            i_state_read => s_state_read,
            i_state_write => s_state_write,
            iu29_state_word_address => su29_state_address,
            iu64_state_write_data => su64_state_write_data,
            iu8_state_byte_enables => x"FF",
            o_state_busy => s_state_ddr_busy,
            o_state_read_valid => s_state_read_valid,
            ou64_state_read_data => su64_state_read_data
        );

    -- Preserve the production instrumentation boundary when this composition
    -- is selected for an instrumented build. It never drives guest state.
    debug_enabled : if (GBOOL_DEBUG_ENABLE) generate
        debug_probe : entity work.rabbitpunch_debug
            generic map (
                GU32_BUILD_ID => GU32_BUILD_ID
            )
            port map (
                i_clk => s_clk_sys,
                i_pixel_enable => s_native_pixel_enable,
                i_visible => not (s_horizontal_blank or s_vertical_blank),
                i_vertical_sync => s_native_vertical_sync,
                iu9_beam_x => su9_beam_x,
                iu9_beam_y => su9_beam_y,
                iu16_status => "00000" & i_reset & s_adpcm_busy & s_file_download &
                    s_paused & s_scanout_armed & s_underflow & s_error &
                    s_downloading & s_loading & s_ready & s_pll_locked,
                i_cpu_request => s_cpu_request,
                i_cpu_write => s_cpu_write,
                iu24_cpu_address => su24_cpu_address,
                iu16_cpu_data => su16_cpu_data,
                iu2_cpu_bytes => su2_cpu_bytes,
                i_sound_request => s_sound_request,
                i_sound_write => s_sound_write,
                iu16_sound_address => su16_sound_address,
                iu8_sound_data => su8_sound_data,
                i_audio_sample => s_audio_sample,
                ou511_snapshot => open
            );
    end generate;

    state_controls : entity work.rabbitpunch_state_controls
        generic map (
            GBOOL_ENABLE => GBOOL_ENABLE_STATES
        )
        port map (
            i_clk => s_clk_sys,
            i_initialize => s_ui_reset,
            iu128_status => su128_status,
            iu32_joystick0 => su32_joystick0,
            iu32_joystick1 => su32_joystick1,
            i_service_ready => s_state_ready,
            i_service_busy => s_state_busy,
            i_service_finished => s_state_finished,
            i_service_success => s_state_success,
            i_service_incomplete => s_state_incomplete,
            o_save => s_state_save,
            o_restore => s_state_restore,
            ou2_slot => su2_state_slot,
            o_unavailable => s_state_unavailable,
            o_save_unavailable => s_state_save_unavailable,
            o_status_set => s_status_set,
            ou128_status_data => su128_status_data
        );

end architecture;
