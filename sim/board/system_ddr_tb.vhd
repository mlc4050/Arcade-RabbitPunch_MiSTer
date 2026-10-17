library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity system_ddr_tb is
end entity;

architecture test of system_ddr_tb is
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
    signal su16_mono_pcm : unsigned(15 downto 0);
    signal s_copy_initialize : std_logic := '1';
    signal s_copy_start : std_logic := '0';
    signal s_copy_done, s_ddr_busy, s_ddr_read, s_ddr_write : std_logic;
    signal s_ddr_valid : std_logic := '0';
    signal su8_ddr_burst, su8_ddr_bytes : unsigned(7 downto 0);
    signal su29_ddr_address : unsigned(28 downto 0);
    signal su64_ddr_data, su64_ddr_write_data : unsigned(63 downto 0) := (others => '0');
    signal sint_cycles, sint_ddr_reads : natural := 0;
    signal sint_epoch : natural range 0 to 1 := 0;
    function image_word(vint_index, vint_epoch : natural) return unsigned is
        variable vu16_word : unsigned(15 downto 0);
    begin
        case vint_index is
            when 0 => vu16_word := x"000F";
            when 1 => vu16_word := x"FFFC";
            when 2 => vu16_word := x"0000";
            when 3 => vu16_word := x"0008";
            when 4 => vu16_word := x"33FC";
            when 5 =>
                if (vint_epoch = 0) then
                    vu16_word := x"CAFE";
                else
                    vu16_word := x"BEEF";
                end if;
            when 6 => vu16_word := x"000F";
            when 7 => vu16_word := x"C000";
            when 8 => vu16_word := x"60F6";
            when others => vu16_word := x"4E71";
        end case;
        return vu16_word(7 downto 0) & vu16_word(15 downto 8);
    end function;
    signal s_clk : std_logic := '0';
    signal s_download, s_word_valid, s_pause, s_game_reset, s_view_enable : std_logic := '0';
    signal s_word_ready, s_ready, s_loading, s_image_valid, s_error, s_done, s_paused, s_view_valid : std_logic;
    signal s_cpu_request, s_cpu_write : std_logic;
    signal su27_address, su27_loaded : unsigned(26 downto 0) := (others => '0');
    signal su16_data, su16_cpu_data, su16_view_data : unsigned(15 downto 0) := (others => '0');
    signal su16_expected : unsigned(15 downto 0) := x"CAFE";
    signal su24_cpu_address : unsigned(23 downto 0);
    signal su2_cpu_bytes : unsigned(1 downto 0);
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_cpu_writes, sint_stream_words : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_ddr_busy <= '1' when sint_cycles mod 23 < 7 else '0';
    copy_from_ddr : entity work.rabbitpunch_ddr_copy
        generic map (GINT_IMAGE_BYTES => 64)
        port map (
            i_clk => s_clk,
            i_initialize => s_copy_initialize,
            i_start => s_copy_start,
            o_active => s_download,
            o_done => s_copy_done,
            o_word_valid => s_word_valid,
            i_word_ready => s_word_ready,
            ou27_word_byte_address => su27_address,
            ou16_word_data => su16_data,
            i_ddr_busy => s_ddr_busy,
            ou8_ddr_burst_count => su8_ddr_burst,
            ou29_ddr_word_address => su29_ddr_address,
            iu64_ddr_read_data => su64_ddr_data,
            i_ddr_read_valid => s_ddr_valid,
            o_ddr_read => s_ddr_read,
            ou64_ddr_write_data => su64_ddr_write_data,
            ou8_ddr_byte_enables => su8_ddr_bytes,
            o_ddr_write => s_ddr_write
        );
    ddr_backend : process(s_clk)
        variable v_pending : boolean := false;
        variable vint_delay, vint_granule, vint_epoch : natural := 0;
        variable vu64_reply : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            sint_cycles <= sint_cycles + 1;
            s_ddr_valid <= '0';
            su64_ddr_data <= x"BAD0BAD1BAD2BAD3";
            assert (s_ddr_write = '0') report "Image copy wrote DDR staging memory" severity failure;
            if (s_ddr_read = '1') then
                assert (s_ddr_busy = '0' and not v_pending and su8_ddr_burst = 1 and su8_ddr_bytes = x"FF" and
                    su29_ddr_address = to_unsigned(16#6000000# + sint_ddr_reads mod 8, 29))
                    report "System DDR read contract/address violation" severity failure;
                vint_granule := sint_ddr_reads mod 8;
                vint_epoch := sint_epoch;
                vint_delay := 3 + (sint_ddr_reads mod 5) * 7;
                v_pending := true;
                sint_ddr_reads <= sint_ddr_reads + 1;
            elsif (v_pending) then
                if (vint_delay = 0) then
                    for vint_word in 0 to 3 loop
                        vu64_reply(vint_word * 16 + 15 downto vint_word * 16) := image_word(vint_granule * 4 + vint_word, vint_epoch);
                    end loop;
                    su64_ddr_data <= vu64_reply;
                    s_ddr_valid <= '1';
                    v_pending := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
        end if;
    end process;
    system : entity work.rabbitpunch_system
        generic map (GINT_IMAGE_BYTES => 64)
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            i_game_reset => s_game_reset,
            i_pause => s_pause,
            o_paused => s_paused,
            i_vblank_start => '0',
            i_half_frame => '0',
            i_line_valid => '0',
            o_line_ready => open,
            i_render_bank => '0',
            iu9_line_y => (others => '0'),
            o_line_done => open,
            i_pixel_valid => '0',
            o_pixel_ready => open,
            i_pixel_bank => '0',
            iu9_pixel_x => (others => '0'),
            iu8_pixel_y => (others => '0'),
            o_pixel_valid => open,
            o_pixel_error => open,
            ou9_pixel_x => open,
            ou8_pixel_y => open,
            ou8_red => open,
            ou8_green => open,
            ou8_blue => open,
            i_view_enable => s_view_enable,
            iu5_view_target => CU5_TARGET_WORKRAM,
            iu15_view_word_address => (others => '0'),
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => (others => '0'),
            i_sound_cpu_enable => '0',
            i_ym_enable => '0',
            i_ym_half_enable => '0',
            i_adpcm_enable => '0',
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            ou9_adpcm_pcm => open,
            ou16_mono_pcm => su16_mono_pcm,
            o_audio_sample_marker => open,
            o_adpcm_busy => open,
            i_audio_view_enable => '0',
            iu11_audio_view_address => (others => '0'),
            ou8_audio_view_data => open,
            o_audio_debug_request => open,
            o_audio_debug_write => open,
            ou16_audio_debug_address => open,
            ou8_audio_debug_data => open,
            i_sound_command_read => '0',
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
            i_download => s_download,
            i_word_valid => s_word_valid,
            o_word_ready => s_word_ready,
            iu27_word_byte_address => su27_address,
            iu16_word_data => su16_data,
            o_image_valid => s_image_valid,
            o_error => s_error,
            o_done => s_done,
            ou27_bytes_loaded => su27_loaded,
            iou16_sdram_data => su16_dq,
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
    chip : sdram_chip_model_wide
        port map (
            clk => s_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_sdram_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_chip,
            SDRAM_nWE => s_write_n,
            SDRAM_nRAS => s_row_n,
            SDRAM_nCAS => s_column_n
        );

    pcm_defined : process(s_clk)
    begin
        if (rising_edge(s_clk) and now > 1 us) then
            assert (su16_mono_pcm = 0) report "Disabled audio clocks must keep mixed PCM silent" severity failure;
            for vint_bit in su16_mono_pcm'range loop
                assert (su16_mono_pcm(vint_bit) = '0' or su16_mono_pcm(vint_bit) = '1')
                    report "Mixed PCM is undefined during startup/reset/playback" severity failure;
            end loop;
        end if;
    end process;
    monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_word_valid = '1' and s_word_ready = '1') then
                sint_stream_words <= sint_stream_words + 1;
            end if;
            if (s_loading = '1') then
                assert (s_cpu_request /= '1') report "CPU requested during image loading" severity failure;
            end if;
            if (s_cpu_request = '1' and s_cpu_write = '1') then
                assert (su24_cpu_address = 16#0FC000# and su2_cpu_bytes = "11" and su16_cpu_data = su16_expected)
                    report "Downloaded 68000 program wrote the wrong value/address" severity failure;
                sint_cpu_writes <= sint_cpu_writes + 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_before : natural;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure load_program(vu16_value : unsigned(15 downto 0)) is
        begin
            wait until falling_edge(s_clk);
            if (vu16_value = x"CAFE") then
                sint_epoch <= 0;
            else
                sint_epoch <= 1;
            end if;
            su16_expected <= vu16_value;
            s_copy_initialize <= '0';
            s_copy_start <= '1';
            cycles(1);
            s_copy_start <= '0';
            wait until s_ready = '1' for 300 us;
            assert (s_ready = '1' and s_image_valid = '1' and s_error = '0' and su27_loaded = 64 and s_download = '0')
                report "DDR-copied image did not drain into system and release reset" severity failure;
            cycles(2);
        end procedure;
        procedure wait_writes(vint_target : natural) is
        begin
            if (sint_cpu_writes < vint_target) then
                wait until sint_cpu_writes >= vint_target for 100 us;
            end if;
            assert (sint_cpu_writes >= vint_target) report "Downloaded CPU program did not execute" severity failure;
            cycles(1);
        end procedure;
        procedure inspect_word is
        begin
            s_pause <= '1';
            wait until s_paused = '1' for 10 us;
            assert (s_paused = '1') report "Downloaded CPU did not pause" severity failure;
            cycles(3);
            s_view_enable <= '1';
            cycles(3);
            assert (s_view_valid = '1' and su16_view_data = su16_expected)
                report "Downloaded program write did not reach native RAM" severity failure;
            s_view_enable <= '0';
            cycles(1);
            s_pause <= '0';
            cycles(1);
        end procedure;
    begin
        cycles(4);
        assert (s_ready = '0' and s_image_valid = '0' and sint_cpu_writes = 0)
            report "System ran before an image existed" severity failure;
        load_program(x"CAFE");
        wait_writes(3);
        inspect_word;
        vint_before := sint_cpu_writes;
        wait_writes(vint_before + 2);
        load_program(x"BEEF");
        vint_before := sint_cpu_writes;
        wait_writes(vint_before + 3);
        inspect_word;
        vint_before := sint_cpu_writes;
        s_game_reset <= '1';
        cycles(100);
        assert (s_loading = '0' and s_image_valid = '1' and sint_stream_words = 64 and sint_ddr_reads = 16)
            report "Soft reset restarted or invalidated the image download" severity failure;
        s_game_reset <= '0';
        wait_writes(vint_before + 3);
        inspect_word;
        assert (sint_stream_words = 64 and sint_ddr_reads = 16 and s_error = '0')
            report "DDR-to-system copy counts or soft-reset no-recopy contract failed" severity failure;
        s_pause <= '1';
        report "SYSTEM_DDR_PASS images=2 copied_words=64 ddr_reads=16 hot_image_replacement=checked soft_reset_without_recopy=checked native_ram=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "System downloaded-program timeout" severity failure;
    end process;
end architecture;
