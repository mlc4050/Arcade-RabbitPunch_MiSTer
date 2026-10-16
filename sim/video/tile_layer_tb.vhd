library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tile_test_support.all;

entity tile_layer_tb is
    generic (G_CAPTURE : boolean := false);
end entity;

architecture test of tile_layer_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_valid, s_foreground : std_logic := '0';
    signal su9_x, su9_y, su9_scroll_x, su9_scroll_y : unsigned(8 downto 0) := (others => '0');
    signal su16_flags : unsigned(15 downto 0) := (others => '0');
    signal s_ready, s_ram_request, s_rom_request, s_rom_foreground, s_pixel_valid, s_opaque : std_logic;
    signal su13_ram_address : unsigned(12 downto 0);
    signal su17_rom_address : unsigned(16 downto 0);
    signal su9_pixel_x, su9_pixel_y, su9_palette_index : unsigned(8 downto 0);
    signal s_ram_valid, s_rom_valid, s_ram_pending, s_rom_pending : std_logic := '0';
    signal su16_ram_data : unsigned(15 downto 0) := (others => '0');
    signal su32_rom_data : unsigned(31 downto 0) := (others => '0');
    signal sint_force_ram_delay, sint_force_rom_delay : integer := -1;
    signal sint_accepted, sint_completed, sint_ram_requests, sint_rom_requests, sint_visible : natural := 0;
    signal s_dump : std_logic := '0';

    -- Synthetic runs never read capture files. Both modes exercise the same DUT
    -- and responder timing; the captured-data scoreboard is independently sampled.
    impure function vectors(v_filename : string; vint_count, vint_width : positive)
        return t_unsigned_words is
        variable v_empty : t_unsigned_words(0 to vint_count - 1)(vint_width - 1 downto 0);
    begin
        if (G_CAPTURE) then
            return read_hex(v_filename, vint_count, vint_width);
        end if;
        v_empty := (others => (others => '0'));
        return v_empty;
    end function;
    constant C_VRAM : t_unsigned_words := vectors("vram.hex", 8192, 16);
    constant C_SETTINGS : t_unsigned_words := vectors("settings.hex", 5, 16);
    constant C_TILES0 : t_unsigned_words := vectors("tiles0.hex", 131072, 32);
    constant C_TILES1 : t_unsigned_words := vectors("tiles1.hex", 131072, 32);
    constant C_EXPECTED : t_unsigned_words := vectors("expected.hex", 124416, 10);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_tile_layer
        port map (
            i_clk => s_clk, i_reset => s_reset, i_request_valid => s_valid,
            o_request_ready => s_ready, iu9_pixel_x => su9_x, iu9_pixel_y => su9_y,
            iu9_scroll_x => su9_scroll_x, iu9_scroll_y => su9_scroll_y,
            iu16_video_flags => su16_flags, i_foreground => s_foreground,
            o_ram_request => s_ram_request, ou13_ram_word_address => su13_ram_address,
            i_ram_response_valid => s_ram_valid, iu16_ram_response_data => su16_ram_data,
            o_rom_request => s_rom_request, ou17_rom_word_address => su17_rom_address,
            o_rom_foreground => s_rom_foreground, i_rom_response_valid => s_rom_valid,
            iu32_rom_response_data => su32_rom_data, o_pixel_valid => s_pixel_valid,
            ou9_pixel_x => su9_pixel_x, ou9_pixel_y => su9_pixel_y,
            ou9_palette_index => su9_palette_index, o_opaque => s_opaque
        );

    responders : process(s_clk)
        variable vint_ram_delay, vint_rom_delay : natural := 0;
        variable vu13_saved_ram_address : unsigned(12 downto 0);
        variable vu17_saved_rom_address : unsigned(16 downto 0);
        variable vint_saved_foreground : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            -- Accepted external requests survive reset and must be drained.
            s_ram_valid <= '0';
            if (s_ram_request = '1') then
                assert (s_ram_pending = '0') report "Overlapping tile RAM requests" severity failure;
                s_ram_pending <= '1';
                vu13_saved_ram_address := su13_ram_address;
                vint_ram_delay := delay_cycles(to_integer(su13_ram_address));
                if (sint_force_ram_delay >= 0) then
                    vint_ram_delay := sint_force_ram_delay;
                end if;
            elsif (s_ram_pending = '1') then
                if (vint_ram_delay = 0) then
                    s_ram_pending <= '0';
                    s_ram_valid <= '1';
                    if (G_CAPTURE) then
                        su16_ram_data <= C_VRAM(to_integer(vu13_saved_ram_address));
                    else
                        su16_ram_data <= descriptor(to_integer(vu13_saved_ram_address));
                    end if;
                else
                    vint_ram_delay := vint_ram_delay - 1;
                end if;
            end if;
            s_rom_valid <= '0';
            if (s_rom_request = '1') then
                assert (s_rom_pending = '0') report "Overlapping tile ROM requests" severity failure;
                s_rom_pending <= '1';
                vu17_saved_rom_address := su17_rom_address;
                vint_saved_foreground := 0;
                if (s_rom_foreground = '1') then
                    vint_saved_foreground := 1;
                end if;
                vint_rom_delay := delay_cycles(to_integer(su17_rom_address));
                if (sint_force_rom_delay >= 0) then
                    vint_rom_delay := sint_force_rom_delay;
                end if;
            elsif (s_rom_pending = '1') then
                if (vint_rom_delay = 0) then
                    s_rom_pending <= '0';
                    s_rom_valid <= '1';
                    if (G_CAPTURE and vint_saved_foreground = 1) then
                        su32_rom_data <= C_TILES1(to_integer(vu17_saved_rom_address));
                    elsif (G_CAPTURE) then
                        su32_rom_data <= C_TILES0(to_integer(vu17_saved_rom_address));
                    else
                        su32_rom_data <= packed_row(vu17_saved_rom_address, vint_saved_foreground);
                    end if;
                else
                    vint_rom_delay := vint_rom_delay - 1;
                end if;
            end if;
        end if;
    end process;

    scoreboard : process(s_clk)
        type t_expected_row is record
            address, code, row, x, y, palette, foreground : natural;
        end record;
        type t_row_queue is array (0 to 16383) of t_expected_row;
        type t_seen is array (0 to 124415) of boolean;
        variable v_queue : t_row_queue;
        variable v_seen : t_seen := (others => false);
        variable v_actual : t_unsigned_words(0 to 124415)(9 downto 0);
        variable vint_accepted, vint_completed, vint_ram_requests, vint_rom_requests : natural := 0;
        variable vint_pixels, vint_visible, vint_sx, vint_sy, vint_foreground, vint_pen, vint_position : natural := 0;
        variable vu16_entry : unsigned(15 downto 0);
        variable v_line : line;
        file v_output : text;
    begin
        if (rising_edge(s_clk)) then
            if (s_reset = '1') then
                vint_accepted := 0;
                vint_completed := 0;
                vint_ram_requests := 0;
                vint_rom_requests := 0;
                vint_pixels := 0;
            else
                if (s_valid = '1' and s_ready = '1') then
                    if (not G_CAPTURE) then
                        assert (vint_accepted < 16384) report "Expected-row queue overflow" severity failure;
                        vint_sx := (to_integer(su9_x) + to_integer(su9_scroll_x)) mod 512;
                        vint_sy := (to_integer(su9_y) + to_integer(su9_scroll_y)) mod 512;
                        vint_foreground := 0;
                        if (s_foreground = '1') then
                            vint_foreground := 1;
                        end if;
                        v_queue(vint_accepted).address := vint_foreground * 4096 + (vint_sx / 8) * 64 + vint_sy / 8;
                        vu16_entry := descriptor(v_queue(vint_accepted).address);
                        v_queue(vint_accepted).code := to_integer(vu16_entry(12 downto 0));
                        if (su16_flags(10 + vint_foreground) = '1') then
                            v_queue(vint_accepted).code := 8192 + to_integer(vu16_entry(11 downto 0));
                        end if;
                        v_queue(vint_accepted).palette := to_integer(vu16_entry(15 downto 13));
                        if (su16_flags(4 + vint_foreground) = '1') then
                            v_queue(vint_accepted).palette := v_queue(vint_accepted).palette + 8;
                        end if;
                        v_queue(vint_accepted).row := vint_sy mod 8;
                        v_queue(vint_accepted).x := (to_integer(su9_x) - vint_sx mod 8) mod 512;
                        v_queue(vint_accepted).y := to_integer(su9_y);
                        v_queue(vint_accepted).foreground := vint_foreground;
                    end if;
                    vint_accepted := vint_accepted + 1;
                end if;
                if (s_ram_request = '1') then
                    if (not G_CAPTURE) then
                        assert (vint_ram_requests < vint_accepted) report "Unaccepted RAM request" severity failure;
                        assert (to_integer(su13_ram_address) = v_queue(vint_ram_requests).address)
                            report "Column-major tile address mismatch" severity failure;
                    end if;
                    vint_ram_requests := vint_ram_requests + 1;
                end if;
                if (s_rom_request = '1') then
                    if (not G_CAPTURE) then
                        assert (vint_rom_requests < vint_accepted) report "Unaccepted ROM request" severity failure;
                        assert (to_integer(su17_rom_address) = v_queue(vint_rom_requests).code * 8 +
                            v_queue(vint_rom_requests).row and
                            s_rom_foreground = bit_value(v_queue(vint_rom_requests).foreground))
                            report "Tile code/row/ROM bank mismatch" severity failure;
                    end if;
                    vint_rom_requests := vint_rom_requests + 1;
                end if;
                if (s_pixel_valid = '1') then
                    if (G_CAPTURE) then
                        if (su9_pixel_x >= 8 and su9_pixel_x < 296 and su9_pixel_y < 216) then
                            vint_foreground := to_integer(su9_palette_index(8 downto 8));
                            vint_position := vint_foreground * 62208 + to_integer(su9_pixel_y) * 288 + to_integer(su9_pixel_x) - 8;
                            assert (not v_seen(vint_position)) report "Repeated captured tile pixel" severity failure;
                            assert ((s_opaque & su9_palette_index) = C_EXPECTED(vint_position))
                                report "Captured tile pixel mismatch at " & integer'image(vint_position) severity failure;
                            v_seen(vint_position) := true;
                            v_actual(vint_position) := s_opaque & su9_palette_index;
                            vint_visible := vint_visible + 1;
                        end if;
                    else
                        assert (vint_completed < vint_accepted) report "Unaccepted pixel row" severity failure;
                        vint_foreground := v_queue(vint_completed).foreground;
                        vint_pen := pen(v_queue(vint_completed).code, v_queue(vint_completed).row, vint_pixels, vint_foreground);
                        assert (to_integer(su9_pixel_x) = (v_queue(vint_completed).x + vint_pixels) mod 512 and
                            to_integer(su9_pixel_y) = v_queue(vint_completed).y and
                            to_integer(su9_palette_index) = vint_foreground * 256 + v_queue(vint_completed).palette * 16 + vint_pen)
                            report "Queued tile coordinate/palette mismatch" severity failure;
                        assert ((s_opaque = '0') = (vint_foreground = 1 and vint_pen = 15))
                            report "Queued tile opacity mismatch" severity failure;
                        vint_pixels := vint_pixels + 1;
                        if (vint_pixels = 8) then
                            vint_pixels := 0;
                            vint_completed := vint_completed + 1;
                        end if;
                    end if;
                end if;
            end if;
            if (s_dump = '1') then
                file_open(v_output, "pixels.hex", write_mode);
                for vint_pixel in v_actual'range loop
                    assert (v_seen(vint_pixel)) report "Missing captured tile pixel" severity failure;
                    write(v_line, to_hstring(v_actual(vint_pixel)));
                    writeline(v_output, v_line);
                end loop;
                file_close(v_output);
            end if;
            sint_accepted <= vint_accepted;
            sint_completed <= vint_completed;
            sint_ram_requests <= vint_ram_requests;
            sint_rom_requests <= vint_rom_requests;
            sint_visible <= vint_visible;
        end if;
    end process;

    stimulus : process
        variable vint_dx, vint_dy, vint_flags, vint_x : natural;
        procedure send_row(vint_px, vint_py, vint_dx, vint_dy, vint_flags, vint_foreground : natural) is
        begin
            wait until falling_edge(s_clk) and s_ready = '1';
            su9_x <= to_unsigned(vint_px, 9);
            su9_y <= to_unsigned(vint_py, 9);
            su9_scroll_x <= to_unsigned(vint_dx, 9);
            su9_scroll_y <= to_unsigned(vint_dy, 9);
            su16_flags <= to_unsigned(vint_flags, 16);
            s_foreground <= bit_value(vint_foreground);
            s_valid <= '1';
            wait until falling_edge(s_clk);
            s_valid <= '0';
            su9_x <= not to_unsigned(vint_px, 9);
            su9_y <= not to_unsigned(vint_py, 9);
            su9_scroll_x <= not to_unsigned(vint_dx, 9);
            su9_scroll_y <= not to_unsigned(vint_dy, 9);
            su16_flags <= not to_unsigned(vint_flags, 16);
            s_foreground <= not bit_value(vint_foreground);
        end procedure;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        if (G_CAPTURE) then
            for vint_foreground in 0 to 1 loop
                vint_dx := to_integer(C_SETTINGS(vint_foreground * 2 + 2)) mod 512;
                vint_dy := to_integer(C_SETTINGS(vint_foreground * 2 + 1)) mod 512;
                for vint_y in 0 to 215 loop
                    vint_x := 8;
                    while (vint_x < 296) loop
                        send_row(vint_x, vint_y, vint_dx, vint_dy, to_integer(C_SETTINGS(0)), vint_foreground);
                        vint_x := vint_x - (vint_x + vint_dx) mod 8 + 8;
                    end loop;
                end loop;
            end loop;
            wait until falling_edge(s_clk) and sint_visible = 124416;
            for vint_cycle in 1 to 32 loop
                wait until falling_edge(s_clk);
            end loop;
            assert (s_ram_pending = '0' and s_rom_pending = '0' and
                sint_accepted = sint_ram_requests and sint_accepted = sint_rom_requests)
                report "Captured tile transactions missing or repeated" severity failure;
            s_dump <= '1';
            wait until falling_edge(s_clk);
            s_dump <= '0';
            report "TILE_CAPTURE_PASS: " & integer'image(sint_accepted) &
                " rows; 124416 visible layer pixels and opacity bits identical";
        else
            for vint_foreground in 0 to 1 loop
                for vint_column in 0 to 63 loop
                    for vint_row in 0 to 63 loop
                        vint_dx := (vint_column * 31 + vint_row * 7) mod 512;
                        vint_dy := (vint_column * 17 + vint_row * 29) mod 512;
                        vint_flags := (vint_column mod 2) * 16#400# +
                            ((vint_column / 2) mod 2) * 16#800# +
                            (vint_row mod 2) * 16#10# + ((vint_row / 2) mod 2) * 16#20#;
                        send_row((vint_column * 8 + vint_row mod 8 - vint_dx) mod 512,
                            (vint_row * 8 + vint_column mod 8 - vint_dy) mod 512,
                            vint_dx, vint_dy, vint_flags, vint_foreground);
                    end loop;
                end loop;
            end loop;
            wait until falling_edge(s_clk) and sint_completed = 8192;
            assert (sint_accepted = 8192 and sint_ram_requests = 8192 and sint_rom_requests = 8192)
                report "Missing or repeated tile transactions" severity failure;
            sint_force_ram_delay <= 0;
            sint_force_rom_delay <= 100;
            send_row(13, 19, 3, 5, 16#430#, 0);
            wait until falling_edge(s_clk) and s_rom_pending = '1';
            sint_force_ram_delay <= 20;
            send_row(511, 511, 7, 9, 16#C30#, 1);
            wait until falling_edge(s_clk) and s_ram_pending = '1';
            assert (s_rom_pending = '1') report "Reset did not overlap RAM and ROM requests" severity failure;
            s_reset <= '1';
            for vint_cycle in 1 to 3 loop
                wait until falling_edge(s_clk);
            end loop;
            s_reset <= '0';
            wait until falling_edge(s_clk) and s_ready = '1';
            assert (s_ram_pending = '0') report "Lookup ready before stale RAM drained" severity failure;
            sint_force_ram_delay <= -1;
            sint_force_rom_delay <= -1;
            for vint_row in 0 to 63 loop
                vint_flags := 0;
                if (vint_row mod 2 = 1) then
                    vint_flags := 16#C30#;
                end if;
                send_row((vint_row * 7) mod 512, (vint_row * 13) mod 512,
                    (vint_row * 11) mod 512, (vint_row * 3) mod 512, vint_flags, vint_row mod 2);
            end loop;
            wait until falling_edge(s_clk) and sint_completed = 64;
            assert (sint_accepted = 64 and sint_ram_requests = 64 and sint_rom_requests = 64)
                report "Post-reset transaction mismatch" severity failure;
            report "TILE_LAYER_PASS: 8256 queued rows, 66048 pixels; all tilemap addresses, banks, wrap, waits and reset";
        end if;
        std.env.finish;
        wait;
    end process;

    watchdog : process
    begin
        wait for 20 ms;
        assert false report "Tile-layer timeout" severity failure;
    end process;
end architecture;
