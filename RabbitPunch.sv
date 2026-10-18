// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RabbitPunch contributors
// MiSTer port boundary only; game, timing, CPU, audio and loading logic are VHDL.
module emu
(
    `include "sys/emu_ports.vh"
);
assign ADC_BUS = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = '0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign AUDIO_S = 1;
assign AUDIO_R = AUDIO_L;
assign AUDIO_MIX = 0;
assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;
wire clk_sys;
wire [127:0] status;
wire [31:0] joystick0, joystick1;
wire [10:0] key_event;
wire [1:0] host_buttons, sdram_byte_mask;
wire [15:0] menu_mask, score_menu_mask, file_index;
wire [26:0] file_address;
wire [7:0] file_data, upload_data;
wire file_download, file_upload, file_write, file_wait, upload_request;
wire horizontal_blank, vertical_blank;
wire native_pixel_enable, native_horizontal_sync, native_vertical_sync;
wire forced_scandoubler, direct_video;
wire loader_busy, loader_read_valid, loader_read, loader_write;
wire [7:0] loader_burst_count, loader_byte_enables;
wire [28:0] loader_word_address;
wire [63:0] loader_read_data, loader_write_data;
wire crt_pixel_enable, crt_horizontal_sync, crt_vertical_sync;
wire crt_horizontal_blank, crt_vertical_blank;
wire [7:0] crt_red, crt_green, crt_blue;
wire crt_size_enable = direct_video | (~forced_scandoubler & ~(|status[46:44]));
wire [7:0] native_red, native_green, native_blue;
wire loading, downloading, ready, error, underflow, pll_locked;
wire paused, scanout_armed, audio_sample, adpcm_busy;
wire cpu_request, cpu_write, sound_request, sound_write;
wire [23:0] cpu_address;
wire [15:0] cpu_data, sound_address;
wire [7:0] sound_data;
wire [1:0] cpu_bytes;
wire [8:0] beam_x, beam_y;
assign CLK_VIDEO = clk_sys;
assign DDRAM_CLK = clk_sys;
// Hide HDMI/output-effect controls under direct video, preserving score masks.
assign menu_mask = score_menu_mask | {8'd0, (~status[94] | ~crt_size_enable), ~status[94], direct_video, 5'd0};
assign {SDRAM_DQMH, SDRAM_DQML} = sdram_byte_mask;
rabbitpunch_status_led status_led
(
    .i_clk(clk_sys),
    .i_loading(loading),
    .i_downloading(downloading),
    .i_error(error),
    .i_underflow(underflow),
    .o_led(LED_USER)
);

rabbitpunch_host host
(
    .i_clk(clk_sys),
    .iou46_hps_bus(HPS_BUS),
    .iu16_menu_mask(menu_mask),
    .ou128_status(status),
    .ou32_joystick0(joystick0),
    .ou32_joystick1(joystick1),
    .ou11_key_event(key_event),
    .ou2_buttons(host_buttons),
    .o_forced_scandoubler(forced_scandoubler),
    .o_direct_video(direct_video),
    .ou16_sdram_configuration(),
    .o_file_download(file_download),
    .ou16_file_index(file_index),
    .o_file_write(file_write),
    .ou27_file_byte_address(file_address),
    .ou8_file_data(file_data),
    .i_file_wait(file_wait),
    .i_file_upload_request(upload_request),
    .iu8_file_upload_index(8'd4),
    .iu8_file_upload_data(upload_data),
    .o_file_upload(file_upload),
    .o_file_read()
);

rabbitpunch_clocked_machine machine
(
    .i_reference_clk(CLK_50M),
    .o_system_clk(clk_sys),
    .o_sdram_clk(SDRAM_CLK),
    .o_pll_locked(pll_locked),
    .i_cold_reset(1'b0),
    .i_framework_reset(RESET),
    .iu128_status(status),
    .iu2_host_buttons(host_buttons),
    .iu32_joystick0(joystick0),
    .iu32_joystick1(joystick1),
    .iu11_key_event(key_event),
    .i_osd_open(OSD_STATUS),
    .i_debug_pause('0),
    .i_state_pause('0),
    .i_host_download(file_download),
    .i_host_upload(file_upload),
    .o_host_upload_request(upload_request),
    .ou8_host_upload_data(upload_data),
    .ou16_host_menu_mask(score_menu_mask),
    .o_hiscore_enabled(),
    .o_hiscore_config_error(),
    .o_hiscore_initialized(),
    .o_hiscore_saved_valid(),
    .o_hiscore_dirty(),
    .iu16_host_index(file_index),
    .i_host_write(file_write),
    .iu27_host_byte_address(file_address),
    .iu8_host_data(file_data),
    .o_host_wait(file_wait),
    .o_downloading(downloading),
    .o_ddr_owner(),
    .o_pause_request(),
    .o_user_paused(),
    .i_maintenance_access('0),
    .i_maintenance_valid('0),
    .i_maintenance_write('0),
    .iu14_maintenance_byte_address('0),
    .iu8_maintenance_data('0),
    .o_maintenance_ready(),
    .o_maintenance_response_valid(),
    .ou8_maintenance_response_data(),
    .o_maintenance_pause(),
    .ou8_player1(),
    .ou8_player2(),
    .ou8_service(),
    .ou16_dips(),
    .o_ddr_mode(),
    .i_ddr_busy(loader_busy),
    .ou8_ddr_burst_count(loader_burst_count),
    .ou29_ddr_word_address(loader_word_address),
    .iu64_ddr_read_data(loader_read_data),
    .i_ddr_read_valid(loader_read_valid),
    .o_ddr_read(loader_read),
    .ou64_ddr_write_data(loader_write_data),
    .ou8_ddr_byte_enables(loader_byte_enables),
    .o_ddr_write(loader_write),
    .o_paused(paused),
    .i_view_enable('0),
    .iu5_view_target('0),
    .iu15_view_word_address('0),
    .o_view_valid(),
    .ou16_view_data(),
    .ou16_left_pcm(),
    .ou16_right_pcm(),
    .ou9_adpcm_pcm(),
    .ou16_mono_pcm(AUDIO_L),
    .o_audio_sample_marker(audio_sample),
    .o_adpcm_busy(adpcm_busy),
    .i_audio_view_enable('0),
    .iu11_audio_view_address('0),
    .ou8_audio_view_data(),
    .o_audio_debug_request(sound_request),
    .o_audio_debug_write(sound_write),
    .ou16_audio_debug_address(sound_address),
    .ou8_audio_debug_data(sound_data),
    .o_sound_command_write(),
    .ou8_sound_command(),
    .o_sound_pending(),
    .ou16_video_flags(),
    .ou9_scroll0_y(),
    .ou9_scroll0_x(),
    .ou9_scroll1_y(),
    .ou9_scroll1_x(),
    .ou6_sprite_count(),
    .ou6_sprite_priority(),
    .ou4_gga_selected(),
    .iu4_gga_view_address('0),
    .ou8_gga_view_data(),
    .o_gga_write(),
    .ou4_gga_write_address(),
    .ou8_gga_write_data(),
    .o_cpu_request(cpu_request),
    .o_cpu_request_write(cpu_write),
    .ou24_cpu_request_address(cpu_address),
    .ou16_cpu_request_data(cpu_data),
    .ou2_cpu_request_bytes(cpu_bytes),
    .o_image_valid(),
    .o_error(error),
    .o_done(),
    .ou27_bytes_loaded(),
    .iou16_sdram_data(SDRAM_DQ),
    .ou13_sdram_address(SDRAM_A),
    .ou2_sdram_bank(SDRAM_BA),
    .ou2_sdram_byte_mask(sdram_byte_mask),
    .o_sdram_chip_select(SDRAM_nCS),
    .o_sdram_write_n(SDRAM_nWE),
    .o_sdram_row_n(SDRAM_nRAS),
    .o_sdram_column_n(SDRAM_nCAS),
    .o_sdram_clock_enable(SDRAM_CKE),
    .o_ready(ready),
    .o_loading(loading),
    .o_pixel_enable(native_pixel_enable),
    .o_active(),
    .o_hsync(native_horizontal_sync),
    .o_vsync(native_vertical_sync),
    .o_hblank(horizontal_blank),
    .o_vblank(vertical_blank),
    .ou9_output_x(),
    .ou8_output_y(),
    .ou8_red(native_red),
    .ou8_green(native_green),
    .ou8_blue(native_blue),
    .ou9_horizontal_position(beam_x),
    .ou9_vertical_position(beam_y),
    .o_scanout_armed(scanout_armed),
    .o_scanout_underflow(underflow)
);
// Optional CRT geometry keeps a direct native bypass when disabled.
rabbitpunch_crt_adjust
#(
    .GINT_PIXEL_DIVIDER(7),
    .GINT_LINE_PIXELS(432),
    .GINT_FRAME_LINES(256)
) crt_geometry
(
    .i_clk(clk_sys),
    .i_initialize(~pll_locked),
    .i_pixel_enable(native_pixel_enable),
    .i_adjust(status[94]),
    .i_size_enable(crt_size_enable),
    .iu5_horizontal_size(status[99:95]),
    .iu7_horizontal_position(status[106:100]),
    .iu6_vertical_shift(status[112:107]),
    .iu8_red(native_red),
    .iu8_green(native_green),
    .iu8_blue(native_blue),
    .i_horizontal_sync(native_horizontal_sync),
    .i_vertical_sync(native_vertical_sync),
    .i_horizontal_blank(horizontal_blank),
    .i_vertical_blank(vertical_blank),
    .o_pixel_enable(crt_pixel_enable),
    .ou8_red(crt_red),
    .ou8_green(crt_green),
    .ou8_blue(crt_blue),
    .o_horizontal_sync(crt_horizontal_sync),
    .o_vertical_sync(crt_vertical_sync),
    .o_horizontal_blank(crt_horizontal_blank),
    .o_vertical_blank(crt_vertical_blank)
);
// Optional effects remain after the native renderer. Its clocks and line
// ownership are independent of this presentation path.
rabbitpunch_video_options video_options
(
    .i_clk(clk_sys),
    .i_pixel_enable(crt_pixel_enable),
    .iu8_red(crt_red),
    .iu8_green(crt_green),
    .iu8_blue(crt_blue),
    .i_horizontal_sync(crt_horizontal_sync),
    .i_vertical_sync(crt_vertical_sync),
    .i_horizontal_blank(crt_horizontal_blank),
    .i_vertical_blank(crt_vertical_blank),
    .i_forced_scandoubler(forced_scandoubler),
    .i_direct_video(direct_video),
    .iu3_effect(status[46:44]),
    .o_pixel_enable(CE_PIXEL),
    .ou8_red(VGA_R),
    .ou8_green(VGA_G),
    .ou8_blue(VGA_B),
    .o_horizontal_sync(VGA_HS),
    .o_vertical_sync(VGA_VS),
    .o_data_enable(VGA_DE),
    .ou2_scanlines(VGA_SL)
);
// HDMI-only native tap. Native analog RGB/sync remain on video_options above.
// Loader ownership includes the downstream final SDRAM write drain.
rabbitpunch_hdmi_presentation hdmi_presentation
(
    .i_clk(clk_sys),
    .i_initialize(~pll_locked),
    .i_game_ready(ready & ~loading & ~error),
    .i_loader_active(downloading | loading),
    .i_direct_video(direct_video),
    .iu2_rotation(status[114:113]),
    .i_native_pixel_enable(native_pixel_enable),
    .iu8_native_red(native_red),
    .iu8_native_green(native_green),
    .iu8_native_blue(native_blue),
    .i_native_horizontal_sync_n(native_horizontal_sync),
    .i_native_vertical_sync_n(native_vertical_sync),
    .i_native_data_enable(~(horizontal_blank | vertical_blank)),
    .i_presented_pixel_enable(CE_PIXEL),
    .i_presented_vertical_sync(VGA_VS),
    .i_presented_data_enable(VGA_DE),
    .iu12_hdmi_width(HDMI_WIDTH),
    .iu12_hdmi_height(HDMI_HEIGHT),
    .iu2_aspect(status[122:121]),
    .iu3_scale(status[68:66]),
    .ou13_aspect_x(VIDEO_ARX),
    .ou13_aspect_y(VIDEO_ARY),
    .i_framebuffer_vertical_blank(FB_VBL),
    .o_framebuffer_enable(FB_EN),
    .o_framebuffer_force_blank(FB_FORCE_BLANK),
    .ou5_framebuffer_format(FB_FORMAT),
    .ou12_framebuffer_width(FB_WIDTH),
    .ou12_framebuffer_height(FB_HEIGHT),
    .ou32_framebuffer_base(FB_BASE),
    .ou14_framebuffer_stride(FB_STRIDE),
    .o_rotation_active(),
    .ou2_applied_rotation(),
    .o_discard_frame(),
    .o_queue_overflow(),
    .o_queue_empty(),
    .iu8_loader_burst_count(loader_burst_count),
    .iu29_loader_word_address(loader_word_address),
    .iu64_loader_write_data(loader_write_data),
    .iu8_loader_byte_enables(loader_byte_enables),
    .i_loader_read(loader_read),
    .i_loader_write(loader_write),
    .o_loader_busy(loader_busy),
    .o_loader_read_valid(loader_read_valid),
    .ou64_loader_read_data(loader_read_data),
    .i_ddr_busy(DDRAM_BUSY),
    .i_ddr_read_valid(DDRAM_DOUT_READY),
    .iu64_ddr_read_data(DDRAM_DOUT),
    .ou8_ddr_burst_count(DDRAM_BURSTCNT),
    .ou29_ddr_word_address(DDRAM_ADDR),
    .ou64_ddr_write_data(DDRAM_DIN),
    .ou8_ddr_byte_enables(DDRAM_BE),
    .o_ddr_read(DDRAM_RD),
    .o_ddr_write(DDRAM_WE)
);
`ifdef DEBUG_ISSP
`ifndef RABBITPUNCH_BUILD_ID
`define RABBITPUNCH_BUILD_ID 32'h00000000
`endif
rabbitpunch_debug #(.GU32_BUILD_ID(`RABBITPUNCH_BUILD_ID)) debug_probe
(
    .i_clk(clk_sys),
    .i_pixel_enable(native_pixel_enable),
    .i_visible(~(horizontal_blank | vertical_blank)),
    .i_vertical_sync(native_vertical_sync),
    .iu9_beam_x(beam_x),
    .iu9_beam_y(beam_y),
    .iu16_status({5'd0, RESET, adpcm_busy, file_download, paused, scanout_armed,
                  underflow, error, downloading, loading, ready, pll_locked}),
    .i_cpu_request(cpu_request),
    .i_cpu_write(cpu_write),
    .iu24_cpu_address(cpu_address),
    .iu16_cpu_data(cpu_data),
    .iu2_cpu_bytes(cpu_bytes),
    .i_sound_request(sound_request),
    .i_sound_write(sound_write),
    .iu16_sound_address(sound_address),
    .iu8_sound_data(sound_data),
    .i_audio_sample(audio_sample),
    .ou511_snapshot()
);
`endif
endmodule
