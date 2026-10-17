library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity system_download_tb is
end entity;

architecture test of system_download_tb is
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
    system : entity work.rabbitpunch_system
        generic map (sint_IMAGE_BYTES => 32)
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
            iu5_view_target => TARGET_WORKRAM,
            iu15_view_word_address => (others => '0'),
            o_view_valid => s_view_valid,
            ou16_view_data => su16_view_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => (others => '0'),
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
            variable vu16_word : unsigned(15 downto 0);
        begin
            s_download <= '1';
            for vint_word in 0 to 15 loop
                if (s_word_ready /= '1') then
                    wait until s_word_ready = '1' for 200 us;
                end if;
                assert (s_word_ready = '1') report "System image stream stalled" severity failure;
                wait until falling_edge(s_clk);
                -- SP=$000ffffc, PC=$8, MOVE.W #value,$000fc000, BRA back to MOVE.
                case vint_word is
                    when 0 => vu16_word := x"000F";
                    when 1 => vu16_word := x"FFFC";
                    when 2 => vu16_word := x"0000";
                    when 3 => vu16_word := x"0008";
                    when 4 => vu16_word := x"33FC";
                    when 5 => vu16_word := vu16_value;
                    when 6 => vu16_word := x"000F";
                    when 7 => vu16_word := x"C000";
                    when 8 => vu16_word := x"60F6";
                    when others => vu16_word := x"4E71";
                end case;
                su27_address <= to_unsigned(vint_word * 2, 27);
                su16_data <= vu16_word(7 downto 0) & vu16_word(15 downto 8);
                s_word_valid <= '1';
                cycles(1);
                s_word_valid <= '0';
                su27_address <= (others => '1');
                su16_data <= (others => '1');
            end loop;
            s_download <= '0';
            wait until s_ready = '1' for 10 us;
            assert (s_ready = '1' and s_image_valid = '1' and s_error = '0' and su27_loaded = 32)
                report "System did not start complete program image" severity failure;
            su16_expected <= vu16_value;
            cycles(1);
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
        assert (s_loading = '0' and s_image_valid = '1' and sint_stream_words = 32)
            report "Soft reset restarted or invalidated the image download" severity failure;
        s_game_reset <= '0';
        wait_writes(vint_before + 3);
        inspect_word;
        -- An interrupted image must not restart the CPU on partially replaced ROM.
        s_download <= '1';
        if (s_word_ready /= '1') then
            wait until s_word_ready = '1' for 10 us;
        end if;
        assert (s_word_ready = '1') report "Short-image stream never became ready" severity failure;
        cycles(1);
        su27_address <= (others => '0');
        su16_data <= x"0F00";
        s_word_valid <= '1';
        cycles(1);
        s_word_valid <= '0';
        s_download <= '0';
        wait until s_error = '1' for 10 us;
        cycles(8);
        assert (s_error = '1' and s_ready = '0' and s_image_valid = '0' and
            s_loading = '0' and su27_loaded = 2 and sint_stream_words = 33)
            report "Partial image did not hold the logical system reset" severity failure;
        load_program(x"CAFE");
        vint_before := sint_cpu_writes;
        wait_writes(vint_before + 3);
        inspect_word;
        assert (sint_stream_words = 49 and s_error = '0')
            report "Logical system did not recover from a partial image" severity failure;
        s_pause <= '1';
        report "SYSTEM_DOWNLOAD_PASS images=3 rejected_images=1 stream_words=" & integer'image(sint_stream_words) &
            " cpu_writes=" & integer'image(sint_cpu_writes);
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "System downloaded-program timeout" severity failure;
    end process;
end architecture;
