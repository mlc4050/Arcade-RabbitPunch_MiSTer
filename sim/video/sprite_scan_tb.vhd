library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity sprite_scan_tb is
    generic (
        G_DRAW : boolean := false;
        G_LINE : boolean := false
    );
end entity;

architecture test of sprite_scan_tb is
    constant C_COUNTS : t_unsigned_words := read_hex("counts.hex", 3, 32);
    constant C_LINES : t_unsigned_words := read_hex("lines.hex", to_integer(C_COUNTS(0)), 64);
    constant C_OFFSETS : t_unsigned_words := read_hex("offsets.hex", C_LINES'length, 64);
    constant C_EXPECTED : t_unsigned_words := read_hex("expected.hex", to_integer(C_COUNTS(1)), 64);
    constant C_ADDRESSES : t_unsigned_words := read_hex("addresses.hex", to_integer(C_COUNTS(2)), 11);
    constant C_RAM : t_unsigned_words := read_hex("ram.hex", 2048, 16);
    impure function drawing_vectors(v_filename : string; vint_count, vint_width : positive)
        return t_unsigned_words is
        variable v_empty : t_unsigned_words(0 to vint_count - 1)(vint_width - 1 downto 0);
    begin
        if (G_DRAW) then
            return read_hex(v_filename, vint_count, vint_width);
        end if;
        v_empty := (others => (others => '0'));
        return v_empty;
    end function;
    constant C_GRAPHICS : t_unsigned_words := drawing_vectors("sprites.hex", 131072, 32);
    constant C_PIXELS : t_unsigned_words := drawing_vectors("pixels.hex", C_EXPECTED'length * 16, 10);
    impure function line_vectors return t_unsigned_words is
        variable v_empty : t_unsigned_words(0 to 0)(15 downto 0) := (others => (others => '0'));
    begin
        if (G_LINE) then
            return read_hex("line_entries.hex", C_LINES'length * 512, 16);
        end if;
        return v_empty;
    end function;
    constant C_LINE_ENTRIES : t_unsigned_words := line_vectors;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_line_valid, s_line_ready, s_scan_done, s_ram_request, s_ram_valid : std_logic := '0';
    signal su9_line_y : unsigned(8 downto 0) := (others => '0');
    signal su6_count, su6_priority : unsigned(5 downto 0) := (others => '0');
    signal su16_flags, su16_ram_data : unsigned(15 downto 0) := (others => '0');
    signal su11_ram_address, su11_code : unsigned(10 downto 0);
    signal su6_index : unsigned(5 downto 0);
    signal su5_row : unsigned(4 downto 0);
    signal su9_x, su9_y : unsigned(8 downto 0);
    signal su4_palette : unsigned(3 downto 0);
    signal s_row_valid, s_row_ready, s_horizontal_flip, s_vertical_flip, s_behind : std_logic;
    signal s_pending, s_begin_line, s_checking, s_force_stall : std_logic := '0';
    signal sint_case, sint_requests, sint_rows, sint_cycles, sint_max_cycles : natural := 0;
    signal su64_actual : unsigned(63 downto 0);
    signal s_consumer_ready, s_draw_ready, s_rom_request, s_rom_valid : std_logic := '0';
    signal s_pixel_valid, s_pixel_opaque, s_pixel_behind : std_logic := '0';
    signal su17_rom_address : unsigned(16 downto 0);
    signal su32_rom_data : unsigned(31 downto 0) := (others => '0');
    signal su9_pixel_x, su9_pixel_y : unsigned(8 downto 0);
    signal su10_pixel_index : unsigned(9 downto 0);
    signal sint_draw_pixels : natural := 0;
    signal s_line_candidate_ready : std_logic := '1';
    signal s_line_finish, s_line_done, s_line_store_ready : std_logic := '0';
    signal s_view_enable, s_view_ready, s_view_valid : std_logic := '0';
    signal su9_view_x : unsigned(8 downto 0) := (others => '0');
    signal su9_view_y : unsigned(8 downto 0);
    signal su16_view_entry : unsigned(15 downto 0);
    signal su6_draw_index : unsigned(5 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    su64_actual <= to_unsigned(0, 17) & s_behind & s_vertical_flip & s_horizontal_flip &
        su4_palette & su9_y & su9_x & su5_row & su11_code & su6_index;
    s_row_ready <= s_consumer_ready and s_draw_ready and s_line_candidate_ready when G_DRAW else s_consumer_ready;
    drawing : if G_DRAW generate
        drawer : entity work.rabbitpunch_sprite_row
            port map (
                i_clk => s_clk,
                i_reset => s_reset,
                i_row_valid => s_row_valid and s_consumer_ready and s_line_candidate_ready,
                o_row_ready => s_draw_ready,
                iu11_sprite_code => su11_code,
                iu5_sprite_row => su5_row,
                iu9_pixel_x => su9_x,
                iu9_pixel_y => su9_y,
                iu4_palette => su4_palette,
                i_horizontal_flip => s_horizontal_flip,
                i_vertical_flip => s_vertical_flip,
                i_behind_foreground => s_behind,
                o_rom_request => s_rom_request,
                ou17_rom_word_address => su17_rom_address,
                i_rom_response_valid => s_rom_valid,
                iu32_rom_response_data => su32_rom_data,
                o_pixel_valid => s_pixel_valid,
                ou9_pixel_x => su9_pixel_x,
                ou9_pixel_y => su9_pixel_y,
                ou10_palette_index => su10_pixel_index,
                o_opaque => s_pixel_opaque,
                o_behind_foreground => s_pixel_behind
            );
        graphics : process(s_clk)
            variable v_pending : boolean := false;
            variable vint_delay : natural := 0;
            variable vu17_address : unsigned(16 downto 0);
        begin
            if (rising_edge(s_clk)) then
                s_rom_valid <= '0';
                if (s_rom_request = '1') then
                    assert (not v_pending) report "Overlapping scan/draw ROM requests" severity failure;
                    v_pending := true;
                    vu17_address := su17_rom_address;
                    vint_delay := delay_cycles(to_integer(su17_rom_address));
                elsif (v_pending) then
                    if (vint_delay = 0) then
                        v_pending := false;
                        s_rom_valid <= '1';
                        su32_rom_data <= C_GRAPHICS(to_integer(vu17_address));
                    else
                        vint_delay := vint_delay - 1;
                    end if;
                end if;
            end if;
        end process;
    end generate;
    line_storage : if G_LINE generate
        line_ram : entity work.rabbitpunch_sprite_line
            port map (
                i_clk => s_clk,
                i_reset => s_reset,
                i_line_start => s_begin_line,
                o_line_ready => s_line_store_ready,
                i_render_bank => bit_value(sint_case mod 2),
                iu9_line_y => C_LINES(sint_case)(8 downto 0),
                i_line_finish => s_line_finish,
                o_line_done => s_line_done,
                i_candidate_valid => s_pixel_valid,
                o_candidate_ready => s_line_candidate_ready,
                iu9_candidate_x => su9_pixel_x,
                iu6_candidate_index => su6_draw_index,
                iu8_candidate_palette => su10_pixel_index(7 downto 0),
                i_candidate_behind_foreground => s_pixel_behind,
                i_view_enable => s_view_enable,
                o_view_ready => s_view_ready,
                i_view_bank => bit_value(sint_case mod 2),
                iu9_view_x => su9_view_x,
                o_view_valid => s_view_valid,
                ou9_view_line_y => su9_view_y,
                ou16_view_entry => su16_view_entry
            );
        check_line : process(s_clk)
            variable vint_x : natural := 0;
        begin
            if (rising_edge(s_clk)) then
                if (s_row_valid = '1' and s_row_ready = '1') then
                    su6_draw_index <= su6_index;
                end if;
                if (s_pixel_valid = '1') then
                    assert (s_line_candidate_ready = '1') report "Line RAM could not accept drawer pixel" severity failure;
                end if;
                if (s_view_valid = '1') then
                    assert (su16_view_entry = C_LINE_ENTRIES(sint_case * 512 + vint_x))
                        report "Integrated sprite line entry mismatch at case " & integer'image(sint_case) &
                            " x=" & integer'image(vint_x) severity failure;
                    assert (su9_view_y = C_LINES(sint_case)(8 downto 0))
                        report "Integrated sprite line Y mismatch" severity failure;
                end if;
                if (s_view_enable = '1' and s_view_ready = '1') then
                    vint_x := to_integer(su9_view_x);
                end if;
            end if;
        end process;
    end generate;
    dut : entity work.rabbitpunch_sprite_scan
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_line_valid => s_line_valid,
            o_line_ready => s_line_ready,
            iu9_line_y => su9_line_y,
            iu6_sprite_count => su6_count,
            iu6_sprite_priority => su6_priority,
            iu16_video_flags => su16_flags,
            o_scan_done => s_scan_done,
            o_ram_request => s_ram_request,
            ou11_ram_word_address => su11_ram_address,
            i_ram_response_valid => s_ram_valid,
            iu16_ram_response_data => su16_ram_data,
            o_row_valid => s_row_valid,
            i_row_ready => s_row_ready,
            ou6_sprite_index => su6_index,
            ou11_sprite_code => su11_code,
            ou5_sprite_row => su5_row,
            ou9_pixel_x => su9_x,
            ou9_pixel_y => su9_y,
            ou4_palette => su4_palette,
            o_horizontal_flip => s_horizontal_flip,
            o_vertical_flip => s_vertical_flip,
            o_behind_foreground => s_behind
        );

    readiness : process(s_clk)
        variable vint_phase : natural := 0;
    begin
        if (falling_edge(s_clk)) then
            vint_phase := (vint_phase + 1) mod 23;
            s_consumer_ready <= '0';
            if (s_force_stall = '0' and vint_phase < 5) then
                s_consumer_ready <= '1';
            end if;
        end if;
    end process;

    responder : process(s_clk)
        variable vint_delay : natural := 0;
        variable vu11_address : unsigned(10 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_ram_valid <= '0';
            if (s_ram_request = '1') then
                assert (s_pending = '0') report "Overlapping sprite descriptor requests" severity failure;
                s_pending <= '1';
                vu11_address := su11_ram_address;
                vint_delay := delay_cycles(to_integer(su11_ram_address));
                if (sint_case = 0) then
                    vint_delay := 11;
                end if;
            elsif (s_pending = '1') then
                if (vint_delay = 0) then
                    s_pending <= '0';
                    s_ram_valid <= '1';
                    su16_ram_data <= C_RAM(to_integer(vu11_address));
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
        end if;
    end process;

    scoreboard : process(s_clk)
        variable vint_requests, vint_rows, vint_cycles, vint_max_cycles : natural := 0;
        variable vint_row_offset, vint_address_offset, vint_row_end, vint_address_end : natural;
        variable v_stalled : boolean := false;
        variable vu64_stalled : unsigned(63 downto 0);
        variable vint_draw_pixels, vint_draw_row, vint_pixel : natural := 0;
        variable vu64_expected_row : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            if (s_begin_line = '1') then
                vint_requests := 0;
                vint_rows := 0;
                vint_cycles := 0;
                v_stalled := false;
                vint_draw_pixels := 0;
            end if;
            if (s_reset = '1') then
                v_stalled := false;
            elsif (s_checking = '1') then
                vint_cycles := vint_cycles + 1;
                vint_row_offset := to_integer(C_OFFSETS(sint_case)(31 downto 0));
                vint_address_offset := to_integer(C_OFFSETS(sint_case)(63 downto 32));
                vint_row_end := C_EXPECTED'length;
                vint_address_end := C_ADDRESSES'length;
                if (sint_case < C_LINES'high) then
                    vint_row_end := to_integer(C_OFFSETS(sint_case + 1)(31 downto 0));
                    vint_address_end := to_integer(C_OFFSETS(sint_case + 1)(63 downto 32));
                end if;
                if (s_ram_request = '1') then
                    assert (vint_address_offset + vint_requests < vint_address_end)
                        report "Extra sprite descriptor read" severity failure;
                    assert (su11_ram_address = C_ADDRESSES(vint_address_offset + vint_requests))
                        report "Sprite descriptor read order mismatch" severity failure;
                    vint_requests := vint_requests + 1;
                end if;
                if (v_stalled) then
                    assert (s_row_valid = '1' and su64_actual = vu64_stalled)
                        report "Queued sprite metadata changed under backpressure" severity failure;
                end if;
                v_stalled := s_row_valid = '1' and s_row_ready = '0';
                vu64_stalled := su64_actual;
                if (s_row_valid = '1' and s_row_ready = '1') then
                    assert (vint_row_offset + vint_rows < vint_row_end) report "Extra sprite row" severity failure;
                    assert (su64_actual = C_EXPECTED(vint_row_offset + vint_rows))
                        report "Sprite scan metadata mismatch at line case " & integer'image(sint_case) severity failure;
                    vint_rows := vint_rows + 1;
                end if;
                if (s_scan_done = '1') then
                    assert (s_line_ready = '1' and s_row_valid = '0' and s_pending = '0')
                        report "Sprite scan finished with pending work" severity failure;
                    assert (vint_requests = vint_address_end - vint_address_offset and
                        vint_rows = vint_row_end - vint_row_offset) report "Incomplete sprite scan" severity failure;
                    if (vint_cycles > vint_max_cycles) then
                        vint_max_cycles := vint_cycles;
                    end if;
                end if;
                if (G_DRAW and s_pixel_valid = '1') then
                    vint_draw_row := vint_row_offset + vint_draw_pixels / 16;
                    vint_pixel := vint_draw_pixels mod 16;
                    assert (vint_draw_row < vint_row_end) report "Extra scan/draw pixel" severity failure;
                    vu64_expected_row := C_EXPECTED(vint_draw_row);
                    assert (su10_pixel_index = C_PIXELS(vint_draw_row * 16 + vint_pixel))
                        report "Integrated scan/draw palette mismatch" severity failure;
                    assert (to_integer(su9_pixel_x) =
                        (to_integer(vu64_expected_row(30 downto 22)) + vint_pixel) mod 512 and
                        su9_pixel_y = vu64_expected_row(39 downto 31))
                        report "Integrated scan/draw coordinate mismatch" severity failure;
                    assert (s_pixel_behind = vu64_expected_row(46) and
                        ((s_pixel_opaque = '0') = (su10_pixel_index(3 downto 0) = 15)))
                        report "Integrated scan/draw opacity/priority mismatch" severity failure;
                    vint_draw_pixels := vint_draw_pixels + 1;
                end if;
            end if;
            sint_requests <= vint_requests;
            sint_rows <= vint_rows;
            sint_cycles <= vint_cycles;
            sint_max_cycles <= vint_max_cycles;
            sint_draw_pixels <= vint_draw_pixels;
        end if;
    end process;

    stimulus : process
        variable vint_trials : natural := 0;
        variable vint_max_completed_cycles : natural := 0;
        procedure begin_line(vint_case : natural) is
            variable vu64_line : unsigned(63 downto 0);
        begin
            wait until falling_edge(s_clk) and s_line_ready = '1';
            vu64_line := C_LINES(vint_case);
            sint_case <= vint_case;
            su9_line_y <= vu64_line(8 downto 0);
            su6_count <= vu64_line(14 downto 9);
            su6_priority <= vu64_line(20 downto 15);
            su16_flags <= vu64_line(36 downto 21);
            s_begin_line <= '1';
            s_checking <= '1';
            s_line_valid <= '1';
            wait until falling_edge(s_clk);
            s_begin_line <= '0';
            s_line_valid <= '0';
            su9_line_y <= not vu64_line(8 downto 0);
            su6_count <= not vu64_line(14 downto 9);
            su6_priority <= not vu64_line(20 downto 15);
            su16_flags <= not vu64_line(36 downto 21);
        end procedure;
        procedure trial(vint_case : natural) is
        begin
            begin_line(vint_case);
            if (s_scan_done /= '1') then
                wait until falling_edge(s_clk) and s_scan_done = '1';
            end if;
            wait until falling_edge(s_clk);
            if (G_DRAW) then
                wait until falling_edge(s_clk) and s_draw_ready = '1';
                assert (sint_draw_pixels = sint_rows * 16)
                    report "Incomplete integrated scan/draw line" severity failure;
                if (G_LINE) then
                    wait until falling_edge(s_clk) and s_line_candidate_ready = '1';
                    s_line_finish <= '1';
                    wait until falling_edge(s_clk);
                    s_line_finish <= '0';
                    wait until falling_edge(s_clk) and s_line_done = '1';
                    assert (s_line_store_ready = '1') report "Sprite line did not finish" severity failure;
                end if;
                if (sint_cycles > vint_max_completed_cycles) then
                    vint_max_completed_cycles := sint_cycles;
                end if;
                if (G_LINE) then
                    for vint_x in 0 to 511 loop
                        s_view_enable <= '1';
                        su9_view_x <= to_unsigned(vint_x, 9);
                        wait until falling_edge(s_clk);
                        assert (s_view_ready = '1') report "Committed sprite line not readable" severity failure;
                    end loop;
                    s_view_enable <= '0';
                    for vint_cycle in 1 to 2 loop
                        wait until falling_edge(s_clk);
                    end loop;
                end if;
            end if;
            s_checking <= '0';
            vint_trials := vint_trials + 1;
        end procedure;
        procedure reset_and_drain is
        begin
            s_reset <= '1';
            s_checking <= '0';
            for vint_cycle in 1 to 3 loop
                wait until falling_edge(s_clk);
            end loop;
            s_reset <= '0';
            s_force_stall <= '0';
            wait until falling_edge(s_clk) and s_line_ready = '1';
            assert (s_pending = '0' and s_row_valid = '0') report "Reset did not drain sprite scan" severity failure;
        end procedure;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        for vint_case in C_LINES'range loop
            trial(vint_case);
        end loop;
        if (not G_DRAW) then
            for vint_request in 1 to 3 loop
                begin_line(0);
                wait until falling_edge(s_clk) and sint_requests = vint_request and s_pending = '1';
                reset_and_drain;
                trial(0);
            end loop;
            s_force_stall <= '1';
            begin_line(0);
            wait until falling_edge(s_clk) and s_row_valid = '1';
            reset_and_drain;
            trial(0);
            begin_line(0);
            reset_and_drain;
            trial(0);
        end if;
        if (G_LINE) then
            report "SPRITE_SCAN_LINE_PASS: " & integer'image(vint_trials) &
                " scans; max_cycles=" & integer'image(vint_max_completed_cycles) & "; every native line entry identical";
        elsif (G_DRAW) then
            report "SPRITE_SCAN_DRAW_PASS: " & integer'image(vint_trials) &
                " scans; max_cycles=" & integer'image(vint_max_completed_cycles) & "; all selected row pixels identical";
        else
            report "SPRITE_SCAN_PASS: " & integer'image(vint_trials) &
                " scans; max_cycles=" & integer'image(sint_max_cycles) &
                "; descriptor order, wrapping, backpressure and reset";
        end if;
        std.env.finish;
        wait;
    end process;

    watchdog : process
    begin
        wait for 120 ms;
        assert false report "Sprite scan timeout" severity failure;
    end process;
end architecture;
