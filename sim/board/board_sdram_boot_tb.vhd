library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity board_sdram_boot_tb is
    generic (
        WRITE_LIMIT : positive := 10000;
        DIP_DEFAULT : natural := 0
    );
end entity;

architecture test of board_sdram_boot_tb is
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
    signal s_reset : std_logic := '1';
    signal s_pause : std_logic := '0';
    signal s_request, s_write, s_paused, s_response_valid : std_logic;
    signal su24_address : unsigned(23 downto 0);
    signal su16_write_data, su16_response_data : unsigned(15 downto 0);
    signal su2_bytes : unsigned(1 downto 0);
    signal s_memory_valid, s_memory_supported, s_rom_request, s_rom_valid, s_io_valid : std_logic;
    signal su16_memory_data, su16_rom_data, su16_io_data : unsigned(15 downto 0);
    signal su18_rom_address : unsigned(17 downto 0);
    signal s_rom_ready, s_rom_idle : std_logic;
    signal s_sound_pending, s_irq_configure, s_irq_twice, s_irq_pending, s_irq_ack : std_logic;
    signal su16_flags : unsigned(15 downto 0);
    signal su9_scroll0_y, su9_scroll0_x, su9_scroll1_y, su9_scroll1_x : unsigned(8 downto 0);
    signal su6_count, su6_priority : unsigned(5 downto 0);
    signal su4_gga_selected : unsigned(3 downto 0);
    signal su4_gga_view : unsigned(3 downto 0) := (others => '0');
    signal su8_gga_data : unsigned(7 downto 0);
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_writes, sint_reads : natural := 0;
    signal s_line_valid, s_pixel_request : std_logic := '0';
    signal s_line_ready, s_line_done, s_pixel_ready, s_pixel_valid, s_pixel_error : std_logic;
    signal s_stop_video, s_video_stopped : std_logic := '0';
    signal su9_line_y, su9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su9_output_x : unsigned(8 downto 0);
    signal su8_output_y, su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal s_sprite_request, s_sprite_valid, s_tile_request, s_tile_valid, s_tile_foreground : std_logic;
    signal su17_sprite_address, su17_tile_address : unsigned(16 downto 0);
    signal su32_sprite_data, su32_tile_data : unsigned(31 downto 0);
    signal sint_lines, sint_pixels, sint_overlap_writes : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    board : entity work.rabbitpunch_board
        port map (
            i_clk => s_clk,
            i_initialize => s_reset,
            i_reset => s_reset,
            i_pause => s_pause,
            o_paused => s_paused,
            i_vblank_start => '0',
            i_half_frame => '0',
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            i_render_bank => '0',
            iu9_line_y => su9_line_y,
            o_line_done => s_line_done,
            o_sprite_rom_request => s_sprite_request,
            ou17_sprite_rom_word_address => su17_sprite_address,
            i_sprite_rom_response_valid => s_sprite_valid,
            iu32_sprite_rom_response_data => su32_sprite_data,
            o_tile_rom_request => s_tile_request,
            ou17_tile_rom_word_address => su17_tile_address,
            o_tile_rom_foreground => s_tile_foreground,
            i_tile_rom_response_valid => s_tile_valid,
            iu32_tile_rom_response_data => su32_tile_data,
            i_pixel_valid => s_pixel_request,
            o_pixel_ready => s_pixel_ready,
            i_pixel_bank => '0',
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su9_line_y(7 downto 0),
            o_pixel_valid => s_pixel_valid,
            o_pixel_error => s_pixel_error,
            ou9_pixel_x => su9_output_x,
            ou8_pixel_y => su8_output_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue,
            o_rom_request => s_rom_request,
            ou18_rom_byte_address => su18_rom_address,
            i_rom_response_valid => s_rom_valid,
            iu16_rom_response_data => su16_rom_data,
            i_view_enable => '0',
            iu5_view_target => TARGET_NONE,
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => to_unsigned(DIP_DEFAULT, 16),
            i_sound_command_read => '0',
            o_sound_command_write => open,
            ou8_sound_command => open,
            o_sound_pending => s_sound_pending,
            ou16_video_flags => su16_flags,
            ou9_scroll0_y => su9_scroll0_y,
            ou9_scroll0_x => su9_scroll0_x,
            ou9_scroll1_y => su9_scroll1_y,
            ou9_scroll1_x => su9_scroll1_x,
            ou6_sprite_count => su6_count,
            ou6_sprite_priority => su6_priority,
            ou4_gga_selected => su4_gga_selected,
            iu4_gga_view_address => su4_gga_view,
            ou8_gga_view_data => su8_gga_data,
            o_gga_write => open,
            ou4_gga_write_address => open,
            ou8_gga_write_data => open,
            o_cpu_request => s_request,
            o_cpu_request_write => s_write,
            ou24_cpu_request_address => su24_address,
            ou16_cpu_request_data => su16_write_data,
            ou2_cpu_request_bytes => su2_bytes
        );
    roms : entity work.rabbitpunch_roms
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            o_ready => s_rom_ready,
            o_idle => s_rom_idle,
            i_loading => '0',
            i_loader_request => '0',
            o_loader_ready => open,
            iu27_loader_byte_address => (others => '0'),
            iu16_loader_data => (others => '0'),
            iu2_loader_bytes => "00",
            o_loader_response_valid => open,
            i_sprite_request => s_sprite_request,
            iu17_sprite_word_address => su17_sprite_address,
            o_sprite_response_valid => s_sprite_valid,
            ou32_sprite_response_data => su32_sprite_data,
            i_tile_request => s_tile_request,
            iu17_tile_word_address => su17_tile_address,
            i_tile_foreground => s_tile_foreground,
            o_tile_response_valid => s_tile_valid,
            ou32_tile_response_data => su32_tile_data,
            i_cpu_request => s_rom_request,
            iu18_cpu_byte_address => su18_rom_address,
            o_cpu_response_valid => s_rom_valid,
            ou16_cpu_response_data => su16_rom_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_sdram_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_chip,
            o_sdram_write_n => s_write_n,
            o_sdram_row_n => s_row_n,
            o_sdram_column_n => s_column_n,
            o_sdram_clock_enable => s_cke
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

    trace : process(s_clk)
        file v_trace : text open write_mode is "rtl_writes.txt";
        variable v_line : line;
        variable vu16_mask : unsigned(15 downto 0);
        variable vint_writes, vint_reads : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_request = '1') then
                if (s_write = '1') then
                    if (s_video_stopped = '0' and sint_lines > 0) then
                        sint_overlap_writes <= sint_overlap_writes + 1;
                    end if;
                    vu16_mask := (others => '0');
                    if (su2_bytes(0) = '1') then
                        vu16_mask(7 downto 0) := (others => '1');
                    end if;
                    if (su2_bytes(1) = '1') then
                        vu16_mask(15 downto 8) := (others => '1');
                    end if;
                    write(v_line, to_hstring(resize(su24_address(19 downto 0), 24)) & " " &
                        to_hstring(vu16_mask) & " " & to_hstring(su16_write_data and vu16_mask));
                    writeline(v_trace, v_line);
                    flush(v_trace);
                    vint_writes := vint_writes + 1;
                else
                    assert (not (su24_address(19 downto 0) = 16#C001E# and s_sound_pending = '1'))
                        report "Boot prefix requires an executing sound CPU" severity failure;
                    vint_reads := vint_reads + 1;
                end if;
            end if;
            sint_writes <= vint_writes;
            sint_reads <= vint_reads;
        end if;
    end process;
    stimulus : process
        file v_state : text open write_mode is "rtl_io_state.txt";
        variable v_line : line;
        constant HEX_CHARACTERS : string := "0123456789abcdef";
        procedure state_word(v_name : string; vu_word : unsigned) is
        begin
            write(v_line, v_name & " " & to_hstring(resize(vu_word, 16)));
            writeline(v_state, v_line);
        end procedure;
    begin
        wait until s_rom_ready = '1';
        for vint_wait in 0 to 99 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        wait until sint_writes = WRITE_LIMIT;
        wait until falling_edge(s_clk);
        s_stop_video <= '1';
        s_pause <= '1';
        wait until s_paused = '1';
        if (s_video_stopped /= '1') then
            wait until s_video_stopped = '1';
        end if;
        for vint_wait in 0 to 2 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_writes = WRITE_LIMIT and s_rom_idle = '1') report "CPU or ROM transport did not drain" severity failure;
        state_word("flags", su16_flags);
        state_word("scroll0_y", su9_scroll0_y);
        state_word("scroll0_x", su9_scroll0_x);
        state_word("scroll1_y", su9_scroll1_y);
        state_word("scroll1_x", su9_scroll1_x);
        state_word("sprite_count", su6_count);
        state_word("sprite_priority", su6_priority);
        state_word("gga_selected", su4_gga_selected);
        for vint_register in 0 to 15 loop
            wait until falling_edge(s_clk);
            su4_gga_view <= to_unsigned(vint_register, 4);
            wait for 1 ns;
            state_word("gga0" & HEX_CHARACTERS(vint_register + 1), su8_gga_data);
        end loop;
        file_close(v_state);
        assert (sint_lines > 0 and sint_pixels = sint_lines * 288 and sint_overlap_writes > 0)
            report "Video did not overlap executing CPU writes" severity failure;
        report "BOARD_VIDEO_LINES=" & integer'image(sint_lines) & " pixels=" & integer'image(sint_pixels) &
            " overlapping_writes=" & integer'image(sint_overlap_writes);
        report "BOARD_SDRAM_BOOT_PASS writes=" & integer'image(sint_writes) & " reads=" & integer'image(sint_reads);
        finish;
        wait;
    end process;
    video_stimulus : process
        variable vint_lines, vint_pixels : natural := 0;
    begin
        wait until s_reset = '0';
        wait until falling_edge(s_clk);
        loop
            exit when s_stop_video = '1';
            if (s_line_ready /= '1') then
                wait until s_line_ready = '1' for 200 us;
                assert (s_line_ready = '1') report "Line renderer not ready" severity failure;
                wait until falling_edge(s_clk);
            end if;
            su9_line_y <= to_unsigned(vint_lines mod 216, 9);
            s_line_valid <= '1';
            wait until falling_edge(s_clk);
            s_line_valid <= '0';
            wait until s_line_done = '1' for 200 us;
            assert (s_line_done = '1') report "Connected line timed out" severity failure;
            wait until falling_edge(s_clk);
            for vint_pixel in 8 to 295 loop
                su9_pixel_x <= to_unsigned(vint_pixel, 9);
                wait for 1 ns;
                if (s_pixel_ready /= '1') then
                    wait until s_pixel_ready = '1' for 2 us;
                    assert (s_pixel_ready = '1') report "Pixel reader not ready" severity failure;
                    wait until falling_edge(s_clk);
                end if;
                s_pixel_request <= '1';
                wait until falling_edge(s_clk);
                s_pixel_request <= '0';
                wait until s_pixel_valid = '1' or s_pixel_error = '1' for 2 us;
                wait for 1 ns;
                assert (s_pixel_valid = '1' and s_pixel_error = '0' and su9_output_x = vint_pixel and
                    su8_output_y = vint_lines mod 216)
                    report "Connected board pixel tag/valid mismatch" severity failure;
                -- This bounded MAME prefix writes only work/bitmap RAM and I/O.
                -- The runner explicitly seeds RAM to MAME startup zeros; RGB stays black.
                assert (su8_red = 0 and su8_green = 0 and su8_blue = 0)
                    report "Connected boot pixel differs from zero palette" severity failure;
                vint_pixels := vint_pixels + 1;
                sint_pixels <= vint_pixels;
                wait until falling_edge(s_clk);
            end loop;
            vint_lines := vint_lines + 1;
            sint_lines <= vint_lines;
        end loop;
        s_video_stopped <= '1';
        wait;
    end process;
    progress : process
        file v_progress : text open write_mode is "boot_progress.txt";
        variable v_line : line;
    begin
        loop
            wait for 250 us;
            write(v_line, time'image(now) & "; writes=" & integer'image(sint_writes) & "; reads=" & integer'image(sint_reads) & "; lines=" & integer'image(sint_lines) & "; stop=" & std_logic'image(s_stop_video) & "; stopped=" & std_logic'image(s_video_stopped) & "; paused=" & std_logic'image(s_paused));
            writeline(v_progress, v_line);
            flush(v_progress);
        end loop;
    end process;
    process
    begin
        wait for 100 ms;
        assert false report "CPU SDRAM boot prefix timeout" severity failure;
    end process;
end architecture;
