-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
-- Diagnostic fixture, not whole-game qualification. All sequencing uses i_clk.
-- Requires the frozen export's passive HALT/IRQ observation ports.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_config.all;
entity state_machine_restore_eval is
    generic (
        GU16_DIP_DEFAULT : unsigned(15 downto 0) := x"0000";
        GBOOL_HISCORE_PROFILE : boolean := false;
        GBOOL_REQUIRE_HISCORE_READY : boolean := false;
        GU192_HISCORE_PROFILE : unsigned(191 downto 0) := (others => '0');
        GBOOL_GAMEPLAY_INPUTS : boolean := false;
        GBOOL_BOOT_RESTORE : boolean := false;
        GBOOL_POST_RESTORE_GAMEPLAY : boolean := false;
        GU32_BOOT_PAD : unsigned(31 downto 0) := (others => '0');
        GU32_ABI_SIGNATURE : unsigned(31 downto 0) := x"52500101";
        GBOOL_CONFIG_IDENTITY : boolean := false;
        GBOOL_SHARED_PRESENTATION : boolean := false;
        GU2_ROTATION : unsigned(1 downto 0) := "01";
        GINT_COIN_FRAME : positive := 900;
        GINT_START_FRAME : positive := 990;
        GINT_ACTION_FRAME : positive := 1290;
        GINT_CHECKPOINT_CYCLES : positive := 120 * 432 * 256 * 7;
        GINT_TRACE_CYCLES : positive := 2 * 432 * 256 * 7;
        GINT_PHASE_TIMEOUT : positive := 240000000
    );
    port (
        o_eval_sound_halted : out std_logic;
        o_eval_shared_ddr : out std_logic;
        ou8_eval_presentation_flags : out unsigned(7 downto 0);
        o_eval_framebuffer_blank : out std_logic;
        o_eval_rotation_overflow : out std_logic;
        ou4_eval_irq : out unsigned(3 downto 0);
        i_clk : in std_logic;
        i_initialize : in std_logic;
        iu128_status : in unsigned(127 downto 0);
        iu2_host_buttons : in unsigned(1 downto 0);
        iu32_joystick0 : in unsigned(31 downto 0);
        iu32_joystick1 : in unsigned(31 downto 0);
        iu11_key_event : in unsigned(10 downto 0);
        i_osd_open : in std_logic;
        i_debug_pause : in std_logic := '0';
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
        iu64_state_ddr_read_data : in unsigned(63 downto 0);
        i_chip_clk : in std_logic;
        ou3_eval_window : out unsigned(2 downto 0);
        o_eval_complete : out std_logic
    );
end entity;
architecture test of state_machine_restore_eval is
    component sdram_chip_model_wide is
        port (
            clk : in std_logic;
            SDRAM_DQ : inout unsigned(15 downto 0);
            SDRAM_A : in unsigned(12 downto 0);
            SDRAM_BA : in unsigned(1 downto 0);
            SDRAM_nCS : in std_logic;
            SDRAM_nWE : in std_logic;
            SDRAM_nRAS : in std_logic;
            SDRAM_nCAS : in std_logic
        );
    end component;
    signal su16_sdram_data : unsigned(15 downto 0);
    signal su32_config_identity : unsigned(31 downto 0);
    signal s_loader_busy, s_loader_valid, s_loader_read, s_loader_write : std_logic;
    signal su8_loader_burst, su8_loader_bytes : unsigned(7 downto 0);
    signal su29_loader_address : unsigned(28 downto 0);
    signal su64_loader_read_data, su64_loader_write_data : unsigned(63 downto 0);
    signal s_slot_busy, s_slot_valid, s_slot_read, s_slot_write : std_logic;
    signal su29_slot_address : unsigned(28 downto 0);
    signal su64_slot_read_data, su64_slot_write_data : unsigned(63 downto 0);
    type t_state is (STATE_LOADING, STATE_PROFILE_START, STATE_PROFILE_SETUP,
        STATE_PROFILE_SEND, STATE_PROFILE_STEP, STATE_PROFILE_END,
        STATE_PROFILE_READY, STATE_WARMUP, STATE_BOOT_RESTORE, STATE_SAVE,
        STATE_WAIT_GO, STATE_TRACE, STATE_WAIT_READY, STATE_DONE);
    signal styp_state : t_state := STATE_LOADING;
    signal s_framework_reset : std_logic := '1';
    signal s_host_download : std_logic := '0';
    signal s_profile_mode, s_profile_download, s_profile_write : std_logic := '0';
    signal sint_profile_byte : natural range 0 to 23 := 0;
    signal su8_profile_data : unsigned(7 downto 0) := (others => '0');
    signal su16_host_index : unsigned(15 downto 0);
    signal su27_host_address : unsigned(26 downto 0);
    signal su8_host_data : unsigned(7 downto 0);
    signal s_host_write : std_logic;
    signal s_save : std_logic := '0';
    signal s_restore : std_logic := '0';
    signal sint_elapsed : natural := 0;
    constant CINT_FRAME_CYCLES : positive := 432 * 256 * 7;
    signal sint_stimulus_frame : natural := 0;
    signal sint_stimulus_phase : natural range 0 to CINT_FRAME_CYCLES - 1 := 0;
    signal sint_motion_phase : natural range 0 to 59 := 0;
    signal s_motion_up : std_logic := '1';
    signal s_post_gameplay : std_logic := '0';
    signal su32_test_joystick : unsigned(31 downto 0);
    signal sint_window : natural range 0 to 6 := 0;
    signal s_operation_succeeded : std_logic := '0';
begin
    o_eval_shared_ddr <= '1' when GBOOL_SHARED_PRESENTATION else '0';
    separate_ddr : if (not GBOOL_SHARED_PRESENTATION) generate
        s_loader_busy <= i_ddr_busy;
        s_loader_valid <= i_ddr_read_valid;
        su64_loader_read_data <= iu64_ddr_read_data;
        ou8_ddr_burst_count <= su8_loader_burst;
        ou29_ddr_word_address <= su29_loader_address;
        ou64_ddr_write_data <= su64_loader_write_data;
        ou8_ddr_byte_enables <= su8_loader_bytes;
        o_ddr_read <= s_loader_read;
        o_ddr_write <= s_loader_write;
        s_slot_busy <= i_state_ddr_busy;
        s_slot_valid <= i_state_ddr_read_valid;
        su64_slot_read_data <= iu64_state_ddr_read_data;
        o_state_ddr_read <= s_slot_read;
        o_state_ddr_write <= s_slot_write;
        ou29_state_ddr_word_address <= su29_slot_address;
        ou64_state_ddr_write_data <= su64_slot_write_data;
        o_eval_framebuffer_blank <= '0';
        o_eval_rotation_overflow <= '0';
        ou8_eval_presentation_flags <= (others => '0');
    end generate;
    shared_ddr : if (GBOOL_SHARED_PRESENTATION) generate
        signal s_framebuffer_enable : std_logic;
        signal su2_applied_rotation : unsigned(1 downto 0);
    begin
        -- Passive status: blank, applied mode, framebuffer enable, state flush,
        -- download, loading and ready. This tap drives no machine input.
        ou8_eval_presentation_flags <= o_eval_framebuffer_blank & su2_applied_rotation &
            s_framebuffer_enable & o_state_presentation_flush & o_downloading & o_loading & o_ready;
        o_state_ddr_read <= '0';
        o_state_ddr_write <= '0';
        ou29_state_ddr_word_address <= (others => '0');
        ou64_state_ddr_write_data <= (others => '0');
        presentation : entity work.rabbitpunch_state_hdmi_presentation
            port map (
                i_clk => i_clk,
                i_initialize => i_initialize,
                i_game_ready => o_ready and not (o_loading or o_error),
                i_loader_active => o_loading or o_downloading,
                i_direct_video => '0',
                iu2_rotation => GU2_ROTATION,
                i_native_pixel_enable => o_pixel_enable,
                iu8_native_red => ou8_red,
                iu8_native_green => ou8_green,
                iu8_native_blue => ou8_blue,
                i_native_horizontal_sync_n => o_hsync,
                i_native_vertical_sync_n => o_vsync,
                i_native_data_enable => not (o_hblank or o_vblank),
                i_presented_pixel_enable => o_pixel_enable,
                i_presented_vertical_sync => not o_vsync,
                i_presented_data_enable => not (o_hblank or o_vblank),
                iu12_hdmi_width => to_unsigned(1920, 12),
                iu12_hdmi_height => to_unsigned(1080, 12),
                iu2_aspect => "00",
                iu3_scale => "000",
                ou13_aspect_x => open,
                ou13_aspect_y => open,
                i_framebuffer_vertical_blank => not o_vsync,
                o_framebuffer_enable => s_framebuffer_enable,
                o_framebuffer_force_blank => o_eval_framebuffer_blank,
                ou5_framebuffer_format => open,
                ou12_framebuffer_width => open,
                ou12_framebuffer_height => open,
                ou32_framebuffer_base => open,
                ou14_framebuffer_stride => open,
                o_rotation_active => open,
                ou2_applied_rotation => su2_applied_rotation,
                o_discard_frame => open,
                o_queue_overflow => o_eval_rotation_overflow,
                o_queue_empty => open,
                iu8_loader_burst_count => su8_loader_burst,
                iu29_loader_word_address => su29_loader_address,
                iu64_loader_write_data => su64_loader_write_data,
                iu8_loader_byte_enables => su8_loader_bytes,
                i_loader_read => s_loader_read,
                i_loader_write => s_loader_write,
                o_loader_busy => s_loader_busy,
                o_loader_read_valid => s_loader_valid,
                ou64_loader_read_data => su64_loader_read_data,
                i_state_flush => o_state_presentation_flush,
                i_state_active => o_state_busy,
                i_state_read => s_slot_read,
                i_state_write => s_slot_write,
                iu29_state_word_address => su29_slot_address,
                iu64_state_write_data => su64_slot_write_data,
                iu8_state_byte_enables => x"FF",
                o_state_busy => s_slot_busy,
                o_state_read_valid => s_slot_valid,
                ou64_state_read_data => su64_slot_read_data,
                i_ddr_busy => i_ddr_busy,
                i_ddr_read_valid => i_ddr_read_valid,
                iu64_ddr_read_data => iu64_ddr_read_data,
                ou8_ddr_burst_count => ou8_ddr_burst_count,
                ou29_ddr_word_address => ou29_ddr_word_address,
                ou64_ddr_write_data => ou64_ddr_write_data,
                ou8_ddr_byte_enables => ou8_ddr_byte_enables,
                o_ddr_read => o_ddr_read,
                o_ddr_write => o_ddr_write
            );
    end generate;
    su32_config_identity <= (31 downto 17 => '0') & o_hiscore_enabled & ou16_dips
        when GBOOL_CONFIG_IDENTITY else (others => '0');
    assert (not GBOOL_REQUIRE_HISCORE_READY or GBOOL_HISCORE_PROFILE)
        report "Ready-score coverage requires the normal host descriptor" severity failure;
    su16_host_index <= to_unsigned(3, 16) when s_profile_mode = '1' else iu16_host_index;
    su27_host_address <= to_unsigned(sint_profile_byte, 27) when s_profile_mode = '1' else iu27_host_byte_address;
    su8_host_data <= su8_profile_data when s_profile_mode = '1' else iu8_host_data;
    s_host_write <= s_profile_write when s_profile_mode = '1' else i_host_write;
    assert (not GBOOL_POST_RESTORE_GAMEPLAY or (GBOOL_BOOT_RESTORE and not GBOOL_GAMEPLAY_INPUTS))
        report "Post-restore gameplay requires a cold baseline" severity failure;
    assert (not (GBOOL_GAMEPLAY_INPUTS or GBOOL_POST_RESTORE_GAMEPLAY) or (GINT_COIN_FRAME < GINT_START_FRAME and
        GINT_START_FRAME < GINT_ACTION_FRAME and
        GINT_ACTION_FRAME * CINT_FRAME_CYCLES < GINT_CHECKPOINT_CYCLES))
        report "Gameplay inputs must precede the saved checkpoint" severity failure;
    test_pad : process(all)
        variable vu32_actions : unsigned(31 downto 0);
    begin
        vu32_actions := iu32_joystick0;
        if (GBOOL_BOOT_RESTORE and s_post_gameplay = '0') then
            vu32_actions := vu32_actions or GU32_BOOT_PAD;
        end if;
        if (GBOOL_GAMEPLAY_INPUTS or s_post_gameplay = '1') then
            if (sint_stimulus_frame >= GINT_COIN_FRAME and sint_stimulus_frame < GINT_COIN_FRAME + 6) then
                vu32_actions(CINT_JOY_COIN) := '1';
            end if;
            if (sint_stimulus_frame >= GINT_START_FRAME and sint_stimulus_frame < GINT_START_FRAME + 6) then
                vu32_actions(CINT_JOY_START) := '1';
            end if;
            if (sint_stimulus_frame >= GINT_ACTION_FRAME) then
                vu32_actions(CINT_JOY_FIRE_PUNCH) := '1';
                if (sint_stimulus_frame >= GINT_ACTION_FRAME + 30 and sint_stimulus_frame < GINT_ACTION_FRAME + 36) then
                    vu32_actions(CINT_JOY_MISSILE) := '1';
                elsif (s_motion_up = '1') then
                    vu32_actions(3) := '1';
                else
                    vu32_actions(2) := '1';
                end if;
            end if;
        end if;
        su32_test_joystick <= vu32_actions;
    end process;
    -- Only warmup advances the input script. The selected pad level remains
    -- identical throughout SAVE continuation and both restored windows.
    test_input_clock : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                sint_stimulus_frame <= 0;
                sint_stimulus_phase <= 0;
                sint_motion_phase <= 0;
                s_motion_up <= '1';
            elsif ((GBOOL_GAMEPLAY_INPUTS or s_post_gameplay = '1') and styp_state = STATE_WARMUP) then
                if (sint_stimulus_phase = CINT_FRAME_CYCLES - 1) then
                    sint_stimulus_phase <= 0;
                    sint_stimulus_frame <= sint_stimulus_frame + 1;
                    if (sint_motion_phase = 59) then
                        sint_motion_phase <= 0;
                        s_motion_up <= not s_motion_up;
                    else
                        sint_motion_phase <= sint_motion_phase + 1;
                    end if;
                else
                    sint_stimulus_phase <= sint_stimulus_phase + 1;
                end if;
            end if;
        end if;
    end process;
    chip : sdram_chip_model_wide
        port map (
            clk => i_chip_clk,
            SDRAM_DQ => su16_sdram_data,
            SDRAM_A => ou13_sdram_address,
            SDRAM_BA => ou2_sdram_bank,
            SDRAM_nCS => o_sdram_chip_select,
            SDRAM_nWE => o_sdram_write_n,
            SDRAM_nRAS => o_sdram_row_n,
            SDRAM_nCAS => o_sdram_column_n
        );
    machine : entity work.rabbitpunch_state_machine
        generic map (
            GINT_SDRAM_READ_CAPTURE_ADJUST => 1,
            GINT_IMAGE_BYTES => 16#210000#,
            GU16_DIP_DEFAULT => GU16_DIP_DEFAULT
        )
        port map (
            o_eval_sound_halted => o_eval_sound_halted,
            ou4_eval_irq => ou4_eval_irq,
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_framework_reset => s_framework_reset,
            iu128_status => iu128_status,
            iu2_host_buttons => iu2_host_buttons,
            iu32_joystick0 => su32_test_joystick,
            iu32_joystick1 => iu32_joystick1,
            iu11_key_event => iu11_key_event,
            i_osd_open => i_osd_open,
            i_debug_pause => i_debug_pause,
            i_host_download => s_host_download or s_profile_download,
            i_host_upload => i_host_upload,
            o_host_upload_request => o_host_upload_request,
            ou8_host_upload_data => ou8_host_upload_data,
            ou16_host_menu_mask => ou16_host_menu_mask,
            o_hiscore_enabled => o_hiscore_enabled,
            o_hiscore_config_error => o_hiscore_config_error,
            o_hiscore_initialized => o_hiscore_initialized,
            o_hiscore_saved_valid => o_hiscore_saved_valid,
            o_hiscore_dirty => o_hiscore_dirty,
            iu16_host_index => su16_host_index,
            i_host_write => s_host_write,
            iu27_host_byte_address => su27_host_address,
            iu8_host_data => su8_host_data,
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
            i_ddr_busy => s_loader_busy,
            ou8_ddr_burst_count => su8_loader_burst,
            ou29_ddr_word_address => su29_loader_address,
            iu64_ddr_read_data => su64_loader_read_data,
            i_ddr_read_valid => s_loader_valid,
            o_ddr_read => s_loader_read,
            ou64_ddr_write_data => su64_loader_write_data,
            ou8_ddr_byte_enables => su8_loader_bytes,
            o_ddr_write => s_loader_write,
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
            iou16_sdram_data => su16_sdram_data,
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
            o_state_cpu_stopped => o_state_cpu_stopped,
            ou52_state_cpu_bus => ou52_state_cpu_bus,
            i_state_save => s_save,
            i_state_restore => s_restore,
            i_state_cancel => '0',
            iu2_state_slot => (others => '0'),
            iu32_state_abi_signature => GU32_ABI_SIGNATURE,
            iu32_state_config_identity => su32_config_identity,
            o_state_ready => o_state_ready,
            o_state_busy => o_state_busy,
            o_state_finished => o_state_finished,
            o_state_success => o_state_success,
            o_state_restoring => o_state_restoring,
            o_state_incomplete => o_state_incomplete,
            o_state_run_release => o_state_run_release,
            o_state_presentation_flush => o_state_presentation_flush,
            ou8_state_error => ou8_state_error,
            o_state_rom_identity_valid => o_state_rom_identity_valid,
            o_state_rom_identity_error => o_state_rom_identity_error,
            ou32_state_rom_identity => ou32_state_rom_identity,
            o_state_ddr_read => s_slot_read,
            o_state_ddr_write => s_slot_write,
            ou29_state_ddr_word_address => su29_slot_address,
            ou64_state_ddr_write_data => su64_slot_write_data,
            i_state_ddr_busy => s_slot_busy,
            i_state_ddr_read_valid => s_slot_valid,
            iu64_state_ddr_read_data => su64_slot_read_data
        );
    operation_flow : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_save <= '0';
            s_restore <= '0';
            s_profile_write <= '0';
            if (i_initialize = '1') then
                styp_state <= STATE_LOADING;
                s_framework_reset <= '1';
                s_host_download <= '0';
                s_profile_mode <= '0';
                s_profile_download <= '0';
                sint_profile_byte <= 0;
                su8_profile_data <= (others => '0');
                sint_elapsed <= 0;
                sint_window <= 0;
                s_operation_succeeded <= '0';
                s_post_gameplay <= '0';
                ou3_eval_window <= "000";
                o_eval_complete <= '0';
            else
                assert (sint_elapsed < GINT_PHASE_TIMEOUT)
                    report "Restore fixture phase timeout" severity failure;
                assert (o_state_rom_identity_error = '0')
                    report "ROM identity error" severity failure;
                if (o_state_finished = '1') then
                    assert (o_state_success = '1' and o_state_incomplete = '0' and ou8_state_error = 0)
                        report "State service operation failed" severity failure;
                    s_operation_succeeded <= '1';
                end if;
                sint_elapsed <= sint_elapsed + 1;
                case styp_state is
                    when STATE_LOADING =>
                        if (sint_elapsed = 4) then
                            s_host_download <= '1';
                        elsif (sint_elapsed = 12) then
                            s_host_download <= '0';
                        elsif (sint_elapsed = 20) then
                            s_framework_reset <= '0';
                        end if;
                        if (o_ready = '1') then
                            assert (o_image_valid = '1' and o_error = '0' and
                                ou27_bytes_loaded = 16#210000#)
                                report "Full real-ROM DDR load required" severity failure;
                            sint_elapsed <= 0;
                            if (GBOOL_HISCORE_PROFILE) then
                                s_profile_mode <= '1';
                                styp_state <= STATE_PROFILE_START;
                            elsif (GBOOL_BOOT_RESTORE) then
                                styp_state <= STATE_BOOT_RESTORE;
                            else
                                styp_state <= STATE_WARMUP;
                            end if;
                        end if;
                    when STATE_PROFILE_START =>
                        s_profile_download <= '1';
                        sint_profile_byte <= 0;
                        sint_elapsed <= 0;
                        styp_state <= STATE_PROFILE_SETUP;
                    when STATE_PROFILE_SETUP =>
                        if (sint_elapsed = 3) then
                            styp_state <= STATE_PROFILE_SEND;
                        end if;
                    when STATE_PROFILE_SEND =>
                        if (o_host_wait = '0') then
                            su8_profile_data <= GU192_HISCORE_PROFILE(
                                (23 - sint_profile_byte) * 8 + 7 downto (23 - sint_profile_byte) * 8);
                            s_profile_write <= '1';
                            styp_state <= STATE_PROFILE_STEP;
                        end if;
                    when STATE_PROFILE_STEP =>
                        if (sint_profile_byte = 23) then
                            styp_state <= STATE_PROFILE_END;
                        else
                            sint_profile_byte <= sint_profile_byte + 1;
                            styp_state <= STATE_PROFILE_SEND;
                        end if;
                    when STATE_PROFILE_END =>
                        s_profile_download <= '0';
                        sint_elapsed <= 0;
                        styp_state <= STATE_PROFILE_READY;
                    when STATE_PROFILE_READY =>
                        if (sint_elapsed = 3) then
                            assert (o_hiscore_enabled = '1' and o_hiscore_config_error = '0')
                                report "Normal high-score descriptor was rejected" severity failure;
                            s_profile_mode <= '0';
                            sint_elapsed <= 0;
                            if (GBOOL_BOOT_RESTORE) then
                                styp_state <= STATE_BOOT_RESTORE;
                            else
                                styp_state <= STATE_WARMUP;
                            end if;
                        end if;
                    when STATE_WARMUP =>
                        if (sint_elapsed = GINT_CHECKPOINT_CYCLES) then
                            assert (o_state_ready = '1' and o_state_rom_identity_valid = '1')
                                report "Checkpoint is not state-ready" severity failure;
                            styp_state <= STATE_SAVE;
                            sint_elapsed <= 0;
                        end if;
                    when STATE_SAVE =>
                        assert (not GBOOL_REQUIRE_HISCORE_READY or
                            (o_hiscore_initialized = '1' and
                            (GBOOL_BOOT_RESTORE or o_hiscore_saved_valid = '1')))
                            report "Required initialized score table was not reached" severity failure;
                        s_operation_succeeded <= '0';
                        s_save <= '1';
                        sint_elapsed <= 0;
                        styp_state <= STATE_WAIT_GO;
                    when STATE_BOOT_RESTORE =>
                        -- The external DDR model supplies an ordinary persisted
                        -- slot. The real validator/apply/return path owns the
                        -- first operation; no CPU or RAM state is deposited.
                        if (o_state_ready = '1') then
                            assert (o_state_rom_identity_valid = '1')
                                report "Cold restore has no ROM identity" severity failure;
                            s_operation_succeeded <= '0';
                            s_restore <= '1';
                            sint_elapsed <= 0;
                            styp_state <= STATE_WAIT_GO;
                        end if;
                    when STATE_WAIT_GO =>
                        if (o_state_run_release = '1') then
                            sint_window <= sint_window + 1;
                            ou3_eval_window <= to_unsigned(sint_window + 1, 3);
                            sint_elapsed <= 0;
                            styp_state <= STATE_TRACE;
                        end if;
                    when STATE_TRACE =>
                        if (sint_elapsed = GINT_TRACE_CYCLES - 1) then
                            ou3_eval_window <= "000";
                            sint_elapsed <= 0;
                            styp_state <= STATE_WAIT_READY;
                        end if;
                    when STATE_WAIT_READY =>
                        if (o_state_ready = '1' and o_state_busy = '0' and s_operation_succeeded = '1') then
                            assert (o_state_incomplete = '0' and ou8_state_error = 0)
                                report "State operation failed" severity failure;
                            sint_elapsed <= 0;
                            if (sint_window = 6) then
                                o_eval_complete <= '1';
                                styp_state <= STATE_DONE;
                            elsif (sint_window = 3) then
                                if (GBOOL_POST_RESTORE_GAMEPLAY) then
                                    s_post_gameplay <= '1';
                                    styp_state <= STATE_WARMUP;
                                else
                                    styp_state <= STATE_SAVE;
                                end if;
                            else
                                s_operation_succeeded <= '0';
                                s_restore <= '1';
                                styp_state <= STATE_WAIT_GO;
                            end if;
                        end if;
                    when STATE_DONE =>
                        sint_elapsed <= 0;
                end case;
            end if;
        end if;
    end process;
end architecture;
