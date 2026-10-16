library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity sprite_row_tb is
end entity;

architecture test of sprite_row_tb is
    constant C_COUNT : t_unsigned_words := read_hex("count.hex", 1, 32);
    constant C_ROWS : t_unsigned_words := read_hex("rows.hex", to_integer(C_COUNT(0)), 64);
    constant C_EXPECTED : t_unsigned_words := read_hex("expected.hex", C_ROWS'length * 16, 10);
    constant C_ROM : t_unsigned_words := read_hex("sprites.hex", 131072, 32);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_valid, s_horizontal_flip, s_vertical_flip, s_behind : std_logic := '0';
    signal su11_code : unsigned(10 downto 0) := (others => '0');
    signal su5_row : unsigned(4 downto 0) := (others => '0');
    signal su9_x, su9_y : unsigned(8 downto 0) := (others => '0');
    signal su4_palette : unsigned(3 downto 0) := (others => '0');
    signal s_ready, s_request, s_pixel_valid, s_opaque, s_output_behind : std_logic;
    signal su17_address : unsigned(16 downto 0);
    signal su9_pixel_x, su9_pixel_y : unsigned(8 downto 0);
    signal su10_palette_index : unsigned(9 downto 0);
    signal s_response_valid, s_pending, s_begin_row, s_checking : std_logic := '0';
    signal su32_response_data : unsigned(31 downto 0) := (others => '0');
    signal sint_case, sint_pixels, sint_requests, sint_total_pixels : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_sprite_row
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_row_valid => s_valid,
            o_row_ready => s_ready,
            iu11_sprite_code => su11_code,
            iu5_sprite_row => su5_row,
            iu9_pixel_x => su9_x,
            iu9_pixel_y => su9_y,
            iu4_palette => su4_palette,
            i_horizontal_flip => s_horizontal_flip,
            i_vertical_flip => s_vertical_flip,
            i_behind_foreground => s_behind,
            o_rom_request => s_request,
            ou17_rom_word_address => su17_address,
            i_rom_response_valid => s_response_valid,
            iu32_rom_response_data => su32_response_data,
            o_pixel_valid => s_pixel_valid,
            ou9_pixel_x => su9_pixel_x,
            ou9_pixel_y => su9_pixel_y,
            ou10_palette_index => su10_palette_index,
            o_opaque => s_opaque,
            o_behind_foreground => s_output_behind
        );

    monitor : process(s_clk)
        variable vint_remaining, vint_pixels, vint_requests, vint_total : natural := 0;
        variable vint_row, vint_half, vint_expected_address : natural;
        variable vu17_saved_address : unsigned(16 downto 0);
        variable vu64_case : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            if (s_begin_row = '1') then
                vint_pixels := 0;
                vint_requests := 0;
            end if;
            vu64_case := C_ROWS(sint_case);
            s_response_valid <= '0';
            if (s_request = '1') then
                assert (s_pending = '0') report "Overlapping sprite ROM requests" severity failure;
                assert (vint_requests < 2) report "Extra sprite ROM request" severity failure;
                vint_row := to_integer(vu64_case(15 downto 11));
                if (vu64_case(39) = '1') then
                    vint_row := 31 - vint_row;
                end if;
                vint_half := vint_requests;
                if (vu64_case(38) = '1') then
                    vint_half := 1 - vint_half;
                end if;
                vint_expected_address := to_integer(vu64_case(10 downto 0)) * 64 + vint_row * 2 + vint_half;
                assert (to_integer(su17_address) = vint_expected_address)
                    report "Sprite ROM address mismatch" severity failure;
                if (vint_requests = 1) then
                    assert (vint_pixels > 0 and vint_pixels < 8)
                        report "Second sprite fetch did not overlap first-half drawing" severity failure;
                end if;
                vu17_saved_address := su17_address;
                vint_remaining := to_integer(vu64_case(48 downto 41));
                s_pending <= '1';
                vint_requests := vint_requests + 1;
            elsif (s_pending = '1') then
                if (vint_remaining = 0) then
                    s_response_valid <= '1';
                    su32_response_data <= C_ROM(to_integer(vu17_saved_address));
                    s_pending <= '0';
                else
                    vint_remaining := vint_remaining - 1;
                end if;
            end if;
            if (s_pixel_valid = '1') then
                assert (s_checking = '1' and s_reset = '0') report "Stale sprite pixel" severity failure;
                assert (vint_pixels < 16) report "Extra sprite pixel" severity failure;
                assert (to_integer(su9_pixel_x) = (to_integer(vu64_case(24 downto 16)) + vint_pixels) mod 512 and
                    su9_pixel_y = vu64_case(33 downto 25)) report "Sprite coordinate mismatch" severity failure;
                assert (su10_palette_index = C_EXPECTED(sint_case * 16 + vint_pixels))
                    report "Sprite pen/palette mismatch at case " & integer'image(sint_case) &
                        " pixel " & integer'image(vint_pixels) severity failure;
                assert ((s_opaque = '0') = (su10_palette_index(3 downto 0) = 15))
                    report "Sprite opacity mismatch" severity failure;
                assert (s_output_behind = vu64_case(40)) report "Sprite priority tag mismatch" severity failure;
                vint_pixels := vint_pixels + 1;
                vint_total := vint_total + 1;
            end if;
            sint_pixels <= vint_pixels;
            sint_requests <= vint_requests;
            sint_total_pixels <= vint_total;
        end if;
    end process;

    stimulus : process
        variable vint_trials : natural := 0;
        procedure begin_row(vint_case : natural) is
            variable vu64_case : unsigned(63 downto 0);
        begin
            wait until falling_edge(s_clk) and s_ready = '1';
            vu64_case := C_ROWS(vint_case);
            sint_case <= vint_case;
            su11_code <= vu64_case(10 downto 0);
            su5_row <= vu64_case(15 downto 11);
            su9_x <= vu64_case(24 downto 16);
            su9_y <= vu64_case(33 downto 25);
            su4_palette <= vu64_case(37 downto 34);
            s_horizontal_flip <= vu64_case(38);
            s_vertical_flip <= vu64_case(39);
            s_behind <= vu64_case(40);
            s_begin_row <= '1';
            s_checking <= '1';
            s_valid <= '1';
            wait until falling_edge(s_clk);
            s_begin_row <= '0';
            s_valid <= '0';
            su11_code <= not vu64_case(10 downto 0);
            su5_row <= not vu64_case(15 downto 11);
            su9_x <= not vu64_case(24 downto 16);
            su9_y <= not vu64_case(33 downto 25);
            su4_palette <= not vu64_case(37 downto 34);
            s_horizontal_flip <= not vu64_case(38);
            s_vertical_flip <= not vu64_case(39);
            s_behind <= not vu64_case(40);
        end procedure;
        procedure trial(vint_case : natural) is
        begin
            begin_row(vint_case);
            s_valid <= '1';
            for vint_cycle in 1 to 2 loop
                wait until falling_edge(s_clk);
            end loop;
            s_valid <= '0';
            wait until falling_edge(s_clk) and s_ready = '1';
            assert (sint_pixels = 16 and sint_requests = 2)
                report "Wrong sprite burst length or request count" severity failure;
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
            wait until falling_edge(s_clk) and s_ready = '1';
            assert (s_pending = '0') report "Sprite ready before stale reply drained" severity failure;
        end procedure;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        for vint_case in C_ROWS'range loop
            trial(vint_case);
        end loop;
        -- Case two has an eleven-cycle reply delay in every generated fixture.
        begin_row(2);
        wait until falling_edge(s_clk) and s_pending = '1';
        reset_and_drain;
        trial(0);
        begin_row(2);
        wait until falling_edge(s_clk) and sint_pixels = 2;
        reset_and_drain;
        trial(1);
        begin_row(2);
        wait until falling_edge(s_clk) and sint_requests = 2 and s_pending = '1';
        reset_and_drain;
        trial(2);
        begin_row(0);
        reset_and_drain;
        trial(0);
        report "SPRITE_ROW_PASS: " & integer'image(vint_trials) & " complete rows, " &
            integer'image(sint_total_pixels) & " pixels; flips, palettes, prefetch, waits and reset";
        std.env.finish;
        wait;
    end process;

    watchdog : process
    begin
        wait for 60 ms;
        assert false report "Sprite-row timeout" severity failure;
    end process;
end architecture;
