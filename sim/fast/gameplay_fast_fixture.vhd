-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.game_program.all;
use work.rabbitpunch_layout.all;

entity gameplay_fast_fixture is
    generic (
        GINT_CAPTURE_FRAME : positive := 1800;
        GINT_COIN_FRAME : positive := 900;
        GINT_START_FRAME : positive := 990;
        GINT_DIP_DEFAULT : natural := 0
    );
    port (
        i_clk : in std_logic;
        iou16_sdram_data : inout unsigned(15 downto 0);
        ou13_sdram_address : out unsigned(12 downto 0);
        ou2_sdram_bank : out unsigned(1 downto 0);
        o_sdram_chip_select : out std_logic;
        o_sdram_write_n : out std_logic;
        o_sdram_row_n : out std_logic;
        o_sdram_column_n : out std_logic;
        o_main_write : out std_logic := '0';
        ou24_main_address : out unsigned(23 downto 0);
        ou16_main_mask : out unsigned(15 downto 0);
        ou16_main_data : out unsigned(15 downto 0);
        o_sound_write : out std_logic := '0';
        ou16_sound_address : out unsigned(15 downto 0);
        ou8_sound_data : out unsigned(7 downto 0);
        o_audio_sample : out std_logic := '0';
        ou16_left_pcm : out unsigned(15 downto 0);
        ou16_right_pcm : out unsigned(15 downto 0);
        ou16_mono_pcm : out unsigned(15 downto 0);
        ou9_adpcm_pcm : out unsigned(8 downto 0);
        o_adpcm_busy : out std_logic;
        o_complete : out std_logic := '0';
        o_capture : out std_logic := '0';
        ou24_rgb : out unsigned(23 downto 0) := (others => '0');
        ou32_sound_writes : out unsigned(31 downto 0) := (others => '0');
        ou16_frame_count : out unsigned(15 downto 0) := (others => '0');
        ou12_maximum_row_clocks : out unsigned(11 downto 0) := (others => '0');
        ou32_cpu_writes : out unsigned(31 downto 0) := (others => '0')
    );
end entity;

architecture test of gameplay_fast_fixture is
    constant CINT_HEADER_WORDS : positive := 16;
    signal s_main_phase_enable, s_fractional_sound, s_fractional_ym, s_fractional_half, s_fractional_adpcm : std_logic;
    signal s_download, s_word_valid, s_pause, s_game_reset, s_view_enable : std_logic := '0';
    signal s_word_ready, s_ready, s_loading, s_image_valid, s_error, s_done, s_paused, s_view_valid : std_logic;
    signal s_cpu_request, s_cpu_write : std_logic;
    signal su27_address, su27_loaded : unsigned(26 downto 0) := (others => '0');
    signal su16_data, su16_cpu_data, su16_view_data : unsigned(15 downto 0) := (others => '0');
    signal su24_cpu_address : unsigned(23 downto 0);
    signal su2_cpu_bytes : unsigned(1 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal s_run : std_logic := '0';
    signal s_adpcm_busy, s_sample_marker, s_audio_request, s_audio_write, s_sound_pending : std_logic;
    signal s_previous_sample : std_logic := '0';
    signal sint_sample_delay : natural range 0 to 4 := 0;
    signal sint_frame_count : natural := 0;
    signal su8_player1, su8_service : unsigned(7 downto 0) := (others => '0');
    signal su16_left_pcm, su16_right_pcm, su16_mono_pcm : unsigned(15 downto 0);
    signal su9_adpcm_pcm : unsigned(8 downto 0);
    signal su16_audio_address : unsigned(15 downto 0);
    signal su8_audio_data, su8_audio_view_data : unsigned(7 downto 0);
    signal s_audio_view : std_logic := '0';
    signal s_vblank_start, s_half_frame, s_line_valid, s_line_ready, s_render_bank, s_line_done : std_logic := '0';
    signal s_pixel_request, s_pixel_ready, s_pixel_bank, s_rgb_valid, s_rgb_error : std_logic := '0';
    signal su9_line_y, su9_pixel_x, su9_rgb_x : unsigned(8 downto 0) := (others => '0');
    signal su8_pixel_y, su8_rgb_y, su8_red, su8_green, su8_blue : unsigned(7 downto 0) := (others => '0');
    signal s_output_enable, s_output_active, s_output_sync, s_armed, s_underflow : std_logic := '0';
    signal su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_output_y, su8_output_red, su8_output_green, su8_output_blue : unsigned(7 downto 0) := (others => '0');

begin
    -- Physical active-high board inputs, after the separately tested pad/key adapter.
    -- SERVICE bit 4 is Coin 1, bit 5 is Start 1; bit 0 is Service Credit.
    su8_service <= x"10" when sint_frame_count >= GINT_COIN_FRAME and sint_frame_count < GINT_COIN_FRAME + 6 else
                   x"20" when sint_frame_count >= GINT_START_FRAME and sint_frame_count < GINT_START_FRAME + 6 else
                   x"00";
    -- Hold Shoot during play, pulse Missile, alternate vertical motion each second.
    su8_player1 <= x"30" when sint_frame_count >= GINT_START_FRAME + 30 and sint_frame_count < GINT_START_FRAME + 36 else
                   x"21" when sint_frame_count >= GINT_START_FRAME + 6 and (sint_frame_count / 60) mod 2 = 0 else
                   x"22" when sint_frame_count >= GINT_START_FRAME + 6 else
                   x"00";
    ou16_left_pcm <= su16_left_pcm;
    ou16_right_pcm <= su16_right_pcm;
    ou16_mono_pcm <= su16_mono_pcm;
    ou9_adpcm_pcm <= su9_adpcm_pcm;
    o_adpcm_busy <= s_adpcm_busy;
    audio_capture : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_audio_sample <= '0';
            s_previous_sample <= s_sample_marker;
            if (s_run = '0') then
                sint_sample_delay <= 0;
            elsif (s_sample_marker = '1' and s_previous_sample = '0') then
                sint_sample_delay <= 4;
            elsif (sint_sample_delay > 0) then
                sint_sample_delay <= sint_sample_delay - 1;
                if (sint_sample_delay = 1) then
                    o_audio_sample <= '1';
                end if;
            end if;
        end if;
    end process;
    ou13_sdram_address <= su13_sdram_address;
    ou2_sdram_bank <= su2_bank;
    o_sdram_chip_select <= s_chip;
    o_sdram_write_n <= s_write_n;
    o_sdram_row_n <= s_row_n;
    o_sdram_column_n <= s_column_n;
    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => i_clk,
            i_reset => '0',
            o_pixel_enable => open,
            o_main_phase_enable => s_main_phase_enable,
            o_sound_cpu_enable => s_fractional_sound,
            o_ym_enable => s_fractional_ym,
            o_ym_half_enable => s_fractional_half,
            o_adpcm_enable => s_fractional_adpcm
        );
    scanout : entity work.rabbitpunch_scanout
        port map (
            i_clk => i_clk,
            i_initialize => '0',
            i_game_ready => s_ready,
            o_main_phase_enable => open,
            o_sound_cpu_enable => open,
            o_ym_enable => open,
            o_ym_half_enable => open,
            o_adpcm_enable => open,
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
            o_pixel_enable => s_output_enable,
            o_active => s_output_active,
            o_hsync => open,
            o_vsync => s_output_sync,
            o_hblank => open,
            o_vblank => open,
            ou9_output_x => su9_output_x,
            ou8_output_y => su8_output_y,
            ou8_red => su8_output_red,
            ou8_green => su8_output_green,
            ou8_blue => su8_output_blue,
            ou9_horizontal_position => open,
            ou9_vertical_position => open,
            o_armed => s_armed,
            o_underflow => s_underflow
        );
    system : entity work.rabbitpunch_system
        generic map (
            GINT_IMAGE_BYTES => CINT_HEADER_WORDS * 2,
            GBOOL_EXTERNAL_PHASE_ENABLE => true,
            GINT_SDRAM_READ_CAPTURE_ADJUST => 1
        )
        port map (
            i_clk => i_clk,
            i_main_phase_enable => s_main_phase_enable,
            i_initialize => '0',
            i_game_reset => s_game_reset,
            i_pause => not s_run or s_pause,
            o_paused => s_paused,
            i_vblank_start => s_vblank_start,
            i_half_frame => s_half_frame,
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            i_render_bank => s_render_bank,
            iu9_line_y => su9_line_y,
            o_line_done => s_line_done,
            i_pixel_valid => s_pixel_request,
            o_pixel_ready => s_pixel_ready,
            i_pixel_bank => s_pixel_bank,
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            o_pixel_valid => s_rgb_valid,
            o_pixel_error => s_rgb_error,
            ou9_pixel_x => su9_rgb_x,
            ou8_pixel_y => su8_rgb_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue,
            i_view_enable => s_view_enable,
            iu5_view_target => CU5_TARGET_WORKRAM,
            iu15_view_word_address => (others => '0'),
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => su8_player1,
            iu8_player2 => (others => '0'),
            iu8_service => su8_service,
            iu16_dips => to_unsigned(GINT_DIP_DEFAULT, 16),
            i_sound_cpu_enable => s_fractional_sound and s_run,
            i_ym_enable => s_fractional_ym,
            i_ym_half_enable => s_fractional_half,
            i_adpcm_enable => s_fractional_adpcm,
            ou16_left_pcm => su16_left_pcm,
            ou16_right_pcm => su16_right_pcm,
            ou9_adpcm_pcm => su9_adpcm_pcm,
            ou16_mono_pcm => su16_mono_pcm,
            o_audio_sample_marker => s_sample_marker,
            o_adpcm_busy => s_adpcm_busy,
            i_audio_view_enable => s_audio_view,
            iu11_audio_view_address => (others => '0'),
            ou8_audio_view_data => su8_audio_view_data,
            o_audio_debug_request => s_audio_request,
            o_audio_debug_write => s_audio_write,
            ou16_audio_debug_address => su16_audio_address,
            ou8_audio_debug_data => su8_audio_data,
            i_sound_command_read => '0',
            o_sound_command_write => open,
            ou8_sound_command => open,
            o_sound_pending => s_sound_pending,
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
            i_download => s_download,
            i_word_valid => s_word_valid,
            o_word_ready => s_word_ready,
            iu27_word_byte_address => su27_address,
            iu16_word_data => su16_data,
            o_image_valid => s_image_valid,
            o_error => s_error,
            o_done => s_done,
            ou27_bytes_loaded => su27_loaded,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => su13_sdram_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_chip,
            o_sdram_write_n => s_write_n,
            o_sdram_row_n => s_row_n,
            o_sdram_column_n => s_column_n,
            o_sdram_clock_enable => s_cke,
            o_ready => s_ready,
            o_loading => s_loading
        );
    monitor : process(i_clk)
        variable vint_pixels : natural range 0 to 62208 := 0;
        variable vint_frames, vint_main, vint_sound, vint_lines, vint_render_cycles : natural := 0;
        variable vint_maximum_row_clocks : natural := 0;
        variable v_rendering, v_capture : boolean := false;
        variable vu16_mask : unsigned(15 downto 0);
    begin
        if (rising_edge(i_clk)) then
            ou16_frame_count <= to_unsigned(vint_frames, 16);
            sint_frame_count <= vint_frames;
            ou32_sound_writes <= to_unsigned(vint_sound, 32);
            ou12_maximum_row_clocks <= to_unsigned(vint_maximum_row_clocks, 12);
            o_capture <= '0';
            o_main_write <= '0';
            o_sound_write <= '0';
            ou32_cpu_writes <= to_unsigned(vint_main, 32);
            if (s_ready = '1') then
                assert (s_error = '0' and s_underflow = '0') report "Live game load/scanout failure" severity failure;
            end if;
            if (s_line_valid = '1' and s_line_ready = '1') then
                assert (not v_rendering) report "Overlapping live game rows" severity failure;
                v_rendering := true;
                vint_render_cycles := 0;
            end if;
            if (v_rendering) then
                vint_render_cycles := vint_render_cycles + 1;
            end if;
            if (s_line_done = '1') then
                assert (v_rendering and vint_render_cycles <= 3024) report "Live game row missed its deadline" severity failure;
                v_rendering := false;
                vint_lines := vint_lines + 1;
                if (vint_render_cycles > vint_maximum_row_clocks) then
                    vint_maximum_row_clocks := vint_render_cycles;
                end if;
            end if;
            if (s_run = '1') then
                if (s_cpu_request = '1' and s_cpu_write = '1') then
                    o_main_write <= '1';
                    ou24_main_address <= su24_cpu_address and x"0FFFFF";
                    vu16_mask := (others => '0');
                    if (su2_cpu_bytes(0) = '1') then
                        vu16_mask(7 downto 0) := (others => '1');
                    end if;
                    if (su2_cpu_bytes(1) = '1') then
                        vu16_mask(15 downto 8) := (others => '1');
                    end if;
                    ou16_main_mask <= vu16_mask;
                    ou16_main_data <= su16_cpu_data and vu16_mask;
                    vint_main := vint_main + 1;
                end if;
                if (s_audio_request = '1' and s_audio_write = '1') then
                    o_sound_write <= '1';
                    vint_sound := vint_sound + 1;
                    ou16_sound_address <= su16_audio_address;
                    ou8_sound_data <= su8_audio_data;
                end if;
                if (s_vblank_start = '1') then
                    vint_frames := vint_frames + 1;
                end if;
                if (s_output_enable = '1' and s_output_active = '1') then
                    if (vint_frames >= GINT_CAPTURE_FRAME and vint_pixels = 0 and su9_output_x = 8 and su8_output_y = 0) then
                        v_capture := true;
                    end if;
                    if (v_capture and vint_pixels < 62208) then
                        assert (su9_output_x = 8 + vint_pixels mod 288 and su8_output_y = vint_pixels / 288)
                            report "Live game capture coordinate ordering mismatch" severity failure;
                        o_capture <= '1';
                        ou24_rgb <= su8_output_red & su8_output_green & su8_output_blue;
                        vint_pixels := vint_pixels + 1;
                        if (vint_pixels = 62208) then
                            o_complete <= '1';
                            s_pause <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    -- Only the real reset-vector header is downloaded; external chip ROM is preloaded by transport.
    stimulus : process(i_clk)
        type t_download_state is (STATE_START, STATE_WAIT_READY, STATE_DROP_VALID, STATE_DRAIN, STATE_DELAY, STATE_RUN);
        variable v_download_state : t_download_state := STATE_START;
        variable vint_word : natural range 0 to CINT_HEADER_WORDS - 1 := 0;
        variable vint_delay : natural range 0 to 9334 := 0;
    begin
        if (rising_edge(i_clk)) then
            case v_download_state is
                when STATE_START =>
                    s_download <= '1';
                    v_download_state := STATE_WAIT_READY;
                when STATE_WAIT_READY =>
                    if (s_word_ready = '1') then
                        su27_address <= to_unsigned(vint_word * 2, 27);
                        su16_data <= program_word(vint_word);
                        s_word_valid <= '1';
                        v_download_state := STATE_DROP_VALID;
                    end if;
                when STATE_DROP_VALID =>
                    s_word_valid <= '0';
                    if (vint_word = CINT_HEADER_WORDS - 1) then
                        s_download <= '0';
                        v_download_state := STATE_DRAIN;
                    else
                        vint_word := vint_word + 1;
                        v_download_state := STATE_WAIT_READY;
                    end if;
                when STATE_DRAIN =>
                    if (s_ready = '1') then
                        assert (s_image_valid = '1' and s_error = '0')
                            report "Live-game header failed load validation" severity failure;
                        v_download_state := STATE_DELAY;
                    end if;
                when STATE_DELAY =>
                    if (vint_delay = 9334) then
                        s_run <= '1';
                        v_download_state := STATE_RUN;
                    else
                        vint_delay := vint_delay + 1;
                    end if;
                when STATE_RUN =>
                    null;
            end case;
        end if;
    end process;
end architecture;
