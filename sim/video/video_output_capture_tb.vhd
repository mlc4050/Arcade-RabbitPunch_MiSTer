library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tile_test_support.all;
use work.rabbitpunch_layout.all;

entity video_output_capture_tb is
end entity;

architecture test of video_output_capture_tb is
    constant C_SETTINGS : t_unsigned_words := read_hex("video_settings.hex", 7, 16);
    constant C_SPRITES : t_unsigned_words := read_hex("spriteram.hex", 2048, 16);
    constant C_TILES : t_unsigned_words := read_hex("vram.hex", 8192, 16);
    constant C_SPRITE_ROM : t_unsigned_words := read_hex("sprites.hex", 131072, 32);
    constant C_TILE_ROM0 : t_unsigned_words := read_hex("tiles0.hex", 131072, 32);
    constant C_TILE_ROM1 : t_unsigned_words := read_hex("tiles1.hex", 131072, 32);
    constant C_BITMAP : t_unsigned_words := read_hex("bitmap.hex", 32768, 16);
    constant C_PALETTE : t_unsigned_words := read_hex("palette.hex", 1024, 16);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_line_valid, s_bank : std_logic := '0';
    signal s_line_ready, s_line_done : std_logic;
    signal su9_line_y, su9_background_x, su9_background_y, su9_foreground_x, su9_foreground_y : unsigned(8 downto 0) := (others => '0');
    signal su6_count, su6_priority : unsigned(5 downto 0) := (others => '0');
    signal su16_flags : unsigned(15 downto 0) := (others => '0');
    type t_rom_addresses is array (0 to 1) of unsigned(16 downto 0);
    type t_rom_words is array (0 to 1) of unsigned(31 downto 0);
    signal su2_rom_request : unsigned(1 downto 0);
    signal su2_rom_valid, su2_rom_pending : unsigned(1 downto 0) := "00";
    signal su17_rom_addresses : t_rom_addresses;
    signal su32_rom_words : t_rom_words := (others => (others => '0'));
    signal s_rom_foreground : std_logic;
    signal s_cpu_request, s_preload_done : std_logic := '0';
    signal s_cpu_response : std_logic;
    signal s_patch_request, s_patch_done : std_logic := '0';
    signal su24_cpu_address : unsigned(23 downto 0) := (others => '0');
    signal su16_cpu_data : unsigned(15 downto 0) := (others => '0');
    signal sint_cpu_writes : natural := 0;
    signal s_pixel_valid, s_pixel_bank : std_logic := '0';
    signal s_pixel_ready, s_output_valid, s_output_error : std_logic;
    signal su9_pixel_x, su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_pixel_y, su8_output_y : unsigned(7 downto 0) := (others => '0');
    signal su16_pixel_flags : unsigned(15 downto 0) := (others => '0');
    signal su8_red, su8_green, su8_blue : unsigned(7 downto 0);
    signal su24_output_rgb, su24_first_rgb : unsigned(23 downto 0);
    signal s_record, s_expect_error : std_logic := '0';
    signal s_force_delay : std_logic := '0';
    signal sint_lines_done, sint_pixels, sint_max_cycles : natural := 0;
    signal s_scan_enable, s_scan_active, s_scan_underflow : std_logic;
    signal su9_scan_x : unsigned(8 downto 0);
    signal su8_scan_y, su8_scan_red, su8_scan_green, su8_scan_blue : unsigned(7 downto 0);
    signal su24_scan_rgb : unsigned(23 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    su24_output_rgb <= su8_red & su8_green & su8_blue;
    su24_scan_rgb <= su8_scan_red & su8_scan_green & su8_scan_blue;
    scanout : entity work.rabbitpunch_video_output
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pixel_enable => s_pixel_valid,
            i_active => '1',
            i_hsync => su9_pixel_x(0),
            i_vsync => su8_pixel_y(0),
            i_hblank => '0',
            i_vblank => '0',
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            o_pixel_request => open,
            i_pixel_ready => s_pixel_ready,
            i_rgb_valid => s_output_valid,
            i_rgb_error => s_output_error,
            iu9_rgb_x => su9_output_x,
            iu8_rgb_y => su8_output_y,
            iu8_red => su8_red,
            iu8_green => su8_green,
            iu8_blue => su8_blue,
            o_pixel_enable => s_scan_enable,
            o_active => s_scan_active,
            o_hsync => open,
            o_vsync => open,
            o_hblank => open,
            o_vblank => open,
            ou9_pixel_x => su9_scan_x,
            ou8_pixel_y => su8_scan_y,
            ou8_red => su8_scan_red,
            ou8_green => su8_scan_green,
            ou8_blue => su8_scan_blue,
            o_underflow => s_scan_underflow
        );
    dut : entity work.rabbitpunch_board_video
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            i_render_bank => s_bank,
            iu9_line_y => su9_line_y,
            iu6_sprite_count => su6_count,
            iu6_sprite_priority => su6_priority,
            iu9_background_scroll_x => su9_background_x,
            iu9_background_scroll_y => su9_background_y,
            iu9_foreground_scroll_x => su9_foreground_x,
            iu9_foreground_scroll_y => su9_foreground_y,
            iu16_video_flags => su16_flags,
            o_line_done => s_line_done,
            o_sprite_rom_request => su2_rom_request(0),
            ou17_sprite_rom_word_address => su17_rom_addresses(0),
            i_sprite_rom_response_valid => su2_rom_valid(0),
            iu32_sprite_rom_response_data => su32_rom_words(0),
            o_tile_rom_request => su2_rom_request(1),
            ou17_tile_rom_word_address => su17_rom_addresses(1),
            o_tile_rom_foreground => s_rom_foreground,
            i_tile_rom_response_valid => su2_rom_valid(1),
            iu32_tile_rom_response_data => su32_rom_words(1),
            i_pixel_valid => s_pixel_valid,
            o_pixel_ready => s_pixel_ready,
            i_pixel_bank => s_pixel_bank,
            iu9_pixel_x => su9_pixel_x,
            iu8_pixel_y => su8_pixel_y,
            iu16_pixel_video_flags => su16_pixel_flags,
            o_pixel_valid => s_output_valid,
            o_pixel_error => s_output_error,
            ou9_pixel_x => su9_output_x,
            ou8_pixel_y => su8_output_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue,
            i_request => s_cpu_request,
            i_request_write => '1',
            iu24_request_address => su24_cpu_address,
            iu16_request_data => su16_cpu_data,
            iu2_request_bytes => "11",
            o_request_supported => open,
            o_response_valid => s_cpu_response,
            ou16_response_data => open,
            o_rom_request => open,
            ou18_rom_byte_address => open,
            i_rom_response_valid => '0',
            iu16_rom_response_data => (others => '0'),
            i_view_enable => '0',
            iu5_view_target => TARGET_NONE,
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open
        );
    cpu_traffic : process
        procedure write_word(vint_address : natural; vu16_data : unsigned(15 downto 0)) is
            variable vint_wait : natural := 0;
        begin
            wait until falling_edge(s_clk);
            s_cpu_request <= '1';
            su24_cpu_address <= to_unsigned(vint_address, 24);
            su16_cpu_data <= vu16_data;
            wait until falling_edge(s_clk);
            s_cpu_request <= '0';
            while (s_cpu_response /= '1' and vint_wait < 100) loop
                wait until falling_edge(s_clk);
                vint_wait := vint_wait + 1;
            end loop;
            assert (s_cpu_response = '1') report "Board video CPU write timed out" severity failure;
            wait until falling_edge(s_clk);
        end procedure;
        variable vint_writes : natural := 0;
        variable v_patch_applied : boolean := false;
    begin
        for vint_word in C_SPRITES'range loop
            write_word(16#60000# + vint_word * 2, C_SPRITES(vint_word));
        end loop;
        for vint_word in C_TILES'range loop
            write_word(16#80000# + vint_word * 2, C_TILES(vint_word));
        end loop;
        for vint_word in C_BITMAP'range loop
            write_word(16#40000# + vint_word * 2, C_BITMAP(vint_word));
        end loop;
        for vint_word in C_PALETTE'range loop
            write_word(16#A0000# + vint_word * 2, C_PALETTE(vint_word));
        end loop;
        s_preload_done <= '1';
        -- Competing CPU transactions use the real work-RAM bank throughout
        -- render/scanout. This is transaction stimulus, not executing fx68k.
        loop
            if (s_patch_request = '1' and not v_patch_applied) then
                -- X=8, Y=0 selects the high nibble of bitmap word 3.
                -- Force pen 1 and make its palette entry green through CPU writes.
                write_word(16#40006#, x"1FFF");
                write_word(16#A0000# + (512 + to_integer(C_SETTINGS(0)(3 downto 0)) * 16 + 1) * 2, x"03E0");
                v_patch_applied := true;
                s_patch_done <= '1';
            end if;
            write_word(16#FC000# + (vint_writes mod 8192) * 2, to_unsigned(vint_writes mod 65536, 16));
            vint_writes := vint_writes + 1;
            sint_cpu_writes <= vint_writes;
        end loop;
    end process;

    external_memory : process(s_clk)
        type t_delays is array (0 to 1) of natural;
        variable v_rom_delay : t_delays := (others => 0);
        variable v_rom_address : t_rom_addresses;
        variable v_foreground : boolean;
    begin
        if (rising_edge(s_clk)) then
            su2_rom_valid <= "00";
            for vint_channel in 0 to 1 loop
                if (su2_rom_request(vint_channel) = '1') then
                    assert (su2_rom_pending(vint_channel) = '0') report "Overlapping video graphics reads" severity failure;
                    su2_rom_pending(vint_channel) <= '1';
                    v_rom_address(vint_channel) := su17_rom_addresses(vint_channel);
                    v_rom_delay(vint_channel) := delay_cycles(to_integer(su17_rom_addresses(vint_channel)));
                    if (s_force_delay = '1') then
                        v_rom_delay(vint_channel) := 20;
                    end if;
                    if (vint_channel = 1) then
                        v_foreground := s_rom_foreground = '1';
                    end if;
                elsif (su2_rom_pending(vint_channel) = '1') then
                    if (v_rom_delay(vint_channel) = 0) then
                        su2_rom_pending(vint_channel) <= '0';
                        su2_rom_valid(vint_channel) <= '1';
                        if (vint_channel = 0) then
                            su32_rom_words(vint_channel) <= C_SPRITE_ROM(to_integer(v_rom_address(vint_channel)));
                        elsif (v_foreground) then
                            su32_rom_words(vint_channel) <= C_TILE_ROM1(to_integer(v_rom_address(vint_channel)));
                        else
                            su32_rom_words(vint_channel) <= C_TILE_ROM0(to_integer(v_rom_address(vint_channel)));
                        end if;
                    else
                        v_rom_delay(vint_channel) := v_rom_delay(vint_channel) - 1;
                    end if;
                end if;
            end loop;
        end if;
    end process;

    scoreboard : process(s_clk)
        file v_output : text open write_mode is "pixels.hex";
        variable v_line : line;
        variable vint_clock, vint_started, vint_max, vint_pixels, vint_lines : natural := 0;
        type t_accepted_pixel is record
            x, y, accepted_clock : natural;
        end record;
        type t_pipeline is array (0 to 7) of t_accepted_pixel;
        variable v_pipeline : t_pipeline;
        variable vint_accepted, vint_returned : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            if (s_reset = '1') then
                vint_lines := 0;
                vint_accepted := 0;
                vint_returned := 0;
            else
                if (s_pixel_valid = '1' and s_pixel_ready = '1') then
                    assert (vint_accepted - vint_returned < 8) report "Pixel pipeline overflow" severity failure;
                    v_pipeline(vint_accepted mod 8) := (to_integer(su9_pixel_x), to_integer(su8_pixel_y), vint_clock);
                    vint_accepted := vint_accepted + 1;
                end if;
                if (s_output_valid = '1' or s_output_error = '1') then
                    assert (vint_returned < vint_accepted) report "Unrequested video output" severity failure;
                    assert (vint_clock - v_pipeline(vint_returned mod 8).accepted_clock = 5 and
                        to_integer(su9_output_x) = v_pipeline(vint_returned mod 8).x and
                        to_integer(su8_output_y) = v_pipeline(vint_returned mod 8).y)
                        report "Video streaming latency/tag mismatch" severity failure;
                    vint_returned := vint_returned + 1;
                end if;
                if (s_line_valid = '1' and s_line_ready = '1') then
                    vint_started := vint_clock;
                end if;
                if (s_line_done = '1') then
                    vint_lines := vint_lines + 1;
                    if (vint_clock - vint_started > vint_max) then
                        vint_max := vint_clock - vint_started;
                    end if;
                end if;
                if (s_output_error = '1') then
                    assert (s_expect_error = '1' and s_output_valid = '0')
                        report "Unexpected video pixel alignment error" severity failure;
                end if;
                if (s_scan_enable = '1' and s_scan_active = '1' and s_record = '1') then
                    assert (s_scan_underflow = '0') report "Fixed RGB output latency mismatch" severity failure;
                    assert (to_integer(su9_scan_x) = vint_pixels mod 288 + 8 and
                        to_integer(su8_scan_y) = vint_pixels / 288) report "Video output pixel ordering mismatch" severity failure;
                    write(v_line, to_hstring(su24_scan_rgb));
                    writeline(v_output, v_line);
                    if (vint_pixels = 0) then
                        su24_first_rgb <= su24_output_rgb;
                    end if;
                    vint_pixels := vint_pixels + 1;
                end if;
            end if;
            sint_lines_done <= vint_lines;
            sint_pixels <= vint_pixels;
            sint_max_cycles <= vint_max;
        end if;
    end process;
    stimulus : process
        procedure begin_line(vint_y : natural) is
        begin
            wait until falling_edge(s_clk) and s_line_ready = '1';
            su9_line_y <= to_unsigned(vint_y, 9);
            s_bank <= bit_value(vint_y mod 2);
            su6_count <= C_SETTINGS(5)(5 downto 0);
            su6_priority <= C_SETTINGS(6)(5 downto 0);
            su16_flags <= C_SETTINGS(0);
            su9_background_y <= C_SETTINGS(1)(8 downto 0);
            su9_background_x <= C_SETTINGS(2)(8 downto 0);
            su9_foreground_y <= C_SETTINGS(3)(8 downto 0);
            su9_foreground_x <= C_SETTINGS(4)(8 downto 0);
            s_line_valid <= '1';
            wait until falling_edge(s_clk);
            s_line_valid <= '0';
            su9_line_y <= not to_unsigned(vint_y, 9);
            s_bank <= not bit_value(vint_y mod 2);
            su6_count <= not C_SETTINGS(5)(5 downto 0);
            su6_priority <= not C_SETTINGS(6)(5 downto 0);
            su16_flags <= not C_SETTINGS(0);
            su9_background_y <= not C_SETTINGS(1)(8 downto 0);
            su9_background_x <= not C_SETTINGS(2)(8 downto 0);
            su9_foreground_y <= not C_SETTINGS(3)(8 downto 0);
            su9_foreground_x <= not C_SETTINGS(4)(8 downto 0);
        end procedure;
        procedure set_pixel(vint_x, vint_y, vint_bank : natural) is
        begin
            su9_pixel_x <= to_unsigned(vint_x, 9);
            su8_pixel_y <= to_unsigned(vint_y, 8);
            s_pixel_bank <= bit_value(vint_bank);
            su16_pixel_flags <= C_SETTINGS(0);
            s_pixel_valid <= '1';
        end procedure;
    begin
        wait until falling_edge(s_clk) and s_preload_done = '1';
        s_reset <= '0';
        begin_line(0);
        wait until falling_edge(s_clk) and sint_lines_done = 1;
        s_record <= '1';
        for vint_y in 0 to 215 loop
            if (vint_y < 215) then
                begin_line(vint_y + 1);
            end if;
            for vint_x in 8 to 295 loop
                wait until falling_edge(s_clk);
                set_pixel(vint_x, vint_y, vint_y mod 2);
                wait until rising_edge(s_clk);
                assert (s_pixel_ready = '1') report "Video failed one-pixel-per-clock streaming" severity failure;
            end loop;
            wait until falling_edge(s_clk);
            s_pixel_valid <= '0';
            su9_pixel_x <= (others => '1');
            su8_pixel_y <= (others => '1');
            s_pixel_bank <= not bit_value(vint_y mod 2);
            su16_pixel_flags <= not C_SETTINGS(0);
            wait until falling_edge(s_clk) and sint_pixels = (vint_y + 1) * 288;
            if (vint_y < 215 and sint_lines_done < vint_y + 2) then
                wait until falling_edge(s_clk) and sint_lines_done >= vint_y + 2;
            end if;
        end loop;
        s_record <= '0';
        -- Wrong line tags must produce an explicit error, never a mixed pixel.
        s_expect_error <= '1';
        set_pixel(8, 214, 1);
        wait until rising_edge(s_clk);
        assert (s_pixel_ready = '1') report "Tag-error test was not accepted" severity failure;
        wait until falling_edge(s_clk);
        s_pixel_valid <= '0';
        wait until falling_edge(s_clk) and s_output_error = '1';
        wait until falling_edge(s_clk);
        s_expect_error <= '0';

        -- Reset with a ROM fetch and a pixel in flight, then re-render a known line.
        s_force_delay <= '1';
        begin_line(0);
        wait until falling_edge(s_clk) and su2_rom_pending /= "00";
        set_pixel(8, 215, 1);
        wait until rising_edge(s_clk);
        assert (s_pixel_ready = '1') report "Reset pixel was not accepted" severity failure;
        wait until falling_edge(s_clk);
        s_pixel_valid <= '0';
        s_reset <= '1';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        s_force_delay <= '0';
        wait until falling_edge(s_clk) and s_line_ready = '1';
        assert (su2_rom_pending = "00")
            report "Video reset left external work pending" severity failure;
        begin_line(0);
        wait until falling_edge(s_clk) and sint_lines_done = 1;
        set_pixel(8, 0, 0);
        wait until rising_edge(s_clk);
        assert (s_pixel_ready = '1') report "Post-reset pixel not accepted" severity failure;
        wait until falling_edge(s_clk);
        s_pixel_valid <= '0';
        wait until falling_edge(s_clk) and s_output_valid = '1';
        assert (su24_output_rgb = su24_first_rgb and su9_output_x = 8 and su8_output_y = 0)
            report "Post-reset video did not reproduce first pixel" severity failure;
        -- Prove CPU writes change actual bitmap/palette scanout, rather than
        -- merely exercising an unrelated work-RAM port during rendering.
        s_patch_request <= '1';
        wait until falling_edge(s_clk) and s_patch_done = '1';
        s_patch_request <= '0';
        set_pixel(8, 0, 0);
        wait until rising_edge(s_clk);
        assert (s_pixel_ready = '1') report "Live-update pixel not accepted" severity failure;
        wait until falling_edge(s_clk);
        s_pixel_valid <= '0';
        wait until falling_edge(s_clk) and s_output_valid = '1';
        assert (su24_output_rgb = x"00FF00" and su9_output_x = 8 and su8_output_y = 0)
            report "CPU bitmap/palette writes did not change RGB scanout" severity failure;
        assert (sint_cpu_writes > 1000) report "Concurrent CPU traffic missing" severity failure;
        assert (sint_pixels = 62208) report "Video frame pixel count mismatch" severity failure;
        report "VIDEO_OUTPUT_CAPTURE_PASS: 62208 native RGB pixels; max_cycles=" & integer'image(sint_max_cycles) &
            "; cpu_writes=" & integer'image(sint_cpu_writes) &
            "; shared board RAM, live bitmap/palette update, native scanout, tags and reset";
        std.env.finish;
        wait;
    end process;
    liveness : process(s_clk)
        variable vint_idle : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_preload_done = '0' or s_reset = '1' or s_line_done = '1' or
                (s_line_valid = '1' and s_line_ready = '1') or s_output_valid = '1' or s_output_error = '1') then
                vint_idle := 0;
            else
                vint_idle := vint_idle + 1;
                assert (vint_idle < 20000) report "Video pipeline stalled; lines=" & integer'image(sint_lines_done) &
                    "; pixels=" & integer'image(sint_pixels) severity failure;
            end if;
        end if;
    end process;
    progress : process
        file v_progress : text open write_mode is "progress.txt";
        variable v_line : line;
    begin
        loop
            wait for 250 us;
            write(v_line, time'image(now) & "; preloaded=" & std_logic'image(s_preload_done) &
                "; lines=" & integer'image(sint_lines_done) & "; pixels=" & integer'image(sint_pixels) &
                "; cpu_writes=" & integer'image(sint_cpu_writes));
            writeline(v_progress, v_line);
            flush(v_progress);
        end loop;
    end process;
end architecture;
