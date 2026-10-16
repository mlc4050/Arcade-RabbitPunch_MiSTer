library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity tile_row_tb is
end entity;

architecture test of tile_row_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_row_valid, s_foreground : std_logic := '0';
    signal su14_code : unsigned(13 downto 0) := (others => '0');
    signal su3_row : unsigned(2 downto 0) := (others => '0');
    signal su9_origin, su9_destination_y : unsigned(8 downto 0) := (others => '0');
    signal su4_palette : unsigned(3 downto 0) := (others => '0');
    signal s_ready, s_request, s_pixel_valid, s_opaque, s_rom_foreground : std_logic;
    signal su17_address : unsigned(16 downto 0);
    signal su9_pixel_x, su9_pixel_y, su9_index : unsigned(8 downto 0);
    signal s_response_valid, s_pending, s_checking : std_logic := '0';
    signal su32_response_data : unsigned(31 downto 0) := (others => '0');
    signal sint_latency, sint_requests, sint_pixels, sint_total_pixels : natural := 0;
    signal s_begin_row : std_logic := '0';
    signal sint_expected_code, sint_expected_row, sint_expected_origin : natural := 0;
    signal sint_expected_palette, sint_expected_y, sint_expected_foreground : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_tile_row
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_row_valid => s_row_valid,
            o_row_ready => s_ready,
            iu14_tile_code => su14_code,
            iu3_tile_row => su3_row,
            iu9_pixel_x => su9_origin,
            iu9_pixel_y => su9_destination_y,
            iu4_palette => su4_palette,
            i_foreground => s_foreground,
            o_rom_request => s_request,
            ou17_rom_word_address => su17_address,
            o_rom_foreground => s_rom_foreground,
            i_rom_response_valid => s_response_valid,
            iu32_rom_response_data => su32_response_data,
            o_pixel_valid => s_pixel_valid,
            ou9_pixel_x => su9_pixel_x,
            ou9_pixel_y => su9_pixel_y,
            ou9_palette_index => su9_index,
            o_opaque => s_opaque
        );

    monitor : process(s_clk)
        variable vint_remaining, vint_pixels, vint_total : natural := 0;
        variable vu17_saved_address : unsigned(16 downto 0);
        variable vint_pen : natural;
    begin
        if (rising_edge(s_clk)) then
            s_response_valid <= '0';
            if (s_request = '1') then
                assert (s_pending = '0') report "Overlapping tile ROM requests" severity failure;
                assert (to_integer(su17_address) = sint_expected_code * 8 + sint_expected_row)
                    report "Tile ROM address mismatch" severity failure;
                assert (s_rom_foreground = bit_value(sint_expected_foreground))
                    report "Wrong graphics ROM bank" severity failure;
                vu17_saved_address := su17_address;
                vint_remaining := sint_latency;
                s_pending <= '1';
                sint_requests <= sint_requests + 1;
            elsif (s_pending = '1') then
                if (vint_remaining = 0) then
                    s_response_valid <= '1';
                    su32_response_data <= packed_row(vu17_saved_address);
                    s_pending <= '0';
                else
                    vint_remaining := vint_remaining - 1;
                end if;
            end if;
            if (s_begin_row = '1') then
                vint_pixels := 0;
            end if;
            if (s_pixel_valid = '1') then
                assert (s_checking = '1' and s_reset = '0')
                    report "Unexpected pixel after reset/abort" severity failure;
                vint_pen := pen(sint_expected_code, sint_expected_row, vint_pixels, 0);
                assert (vint_pixels < 8 and
                    to_integer(su9_pixel_x) = (sint_expected_origin + vint_pixels) mod 512 and
                    to_integer(su9_pixel_y) = sint_expected_y and
                    to_integer(su9_index) = sint_expected_foreground * 256 + sint_expected_palette * 16 + vint_pen)
                    report "Tile pixel coordinate/palette mismatch" severity failure;
                assert ((s_opaque = '0') = (sint_expected_foreground = 1 and vint_pen = 15))
                    report "Tile opacity mismatch" severity failure;
                vint_pixels := vint_pixels + 1;
                vint_total := vint_total + 1;
            end if;
            sint_pixels <= vint_pixels;
            sint_total_pixels <= vint_total;
        end if;
    end process;

    stimulus : process
        type t_codes is array (natural range <>) of natural;
        constant C_CODES : t_codes := (0, 1, 8191, 8192, 12287, 16383);
        variable vint_trials : natural := 0;
        procedure begin_row(vint_code, vint_row, vint_x, vint_palette,
                            vint_foreground, vint_delay : natural) is
        begin
            wait until falling_edge(s_clk) and s_ready = '1';
            sint_expected_code <= vint_code;
            sint_expected_row <= vint_row;
            sint_expected_origin <= vint_x;
            sint_expected_palette <= vint_palette;
            sint_expected_foreground <= vint_foreground;
            sint_expected_y <= (vint_code + vint_row + vint_palette) mod 512;
            su14_code <= to_unsigned(vint_code, 14);
            su3_row <= to_unsigned(vint_row, 3);
            su9_origin <= to_unsigned(vint_x, 9);
            su4_palette <= to_unsigned(vint_palette, 4);
            s_foreground <= bit_value(vint_foreground);
            su9_destination_y <= to_unsigned((vint_code + vint_row + vint_palette) mod 512, 9);
            sint_latency <= vint_delay;
            s_checking <= '1';
            s_begin_row <= '1';
            s_row_valid <= '1';
            wait until falling_edge(s_clk);
            s_begin_row <= '0';
            s_row_valid <= '0';
            su14_code <= not to_unsigned(vint_code, 14);
            su3_row <= not to_unsigned(vint_row, 3);
            su9_origin <= not to_unsigned(vint_x, 9);
            su4_palette <= not to_unsigned(vint_palette, 4);
            s_foreground <= not bit_value(vint_foreground);
            su9_destination_y <= not to_unsigned((vint_code + vint_row + vint_palette) mod 512, 9);
        end procedure;
        procedure trial(vint_code, vint_row, vint_x, vint_palette,
                        vint_foreground, vint_delay : natural) is
            variable vint_before_requests : natural;
        begin
            vint_before_requests := sint_requests;
            begin_row(vint_code, vint_row, vint_x, vint_palette, vint_foreground, vint_delay);
            s_row_valid <= '1';
            for vint_cycle in 1 to 2 loop
                wait until falling_edge(s_clk);
            end loop;
            s_row_valid <= '0';
            wait until falling_edge(s_clk) and s_ready = '1';
            assert (sint_pixels = 8 and sint_requests = vint_before_requests + 1)
                report "Wrong tile burst length or request count" severity failure;
            s_checking <= '0';
            vint_trials := vint_trials + 1;
        end procedure;
        variable vint_origin : natural;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        for vint_code_index in C_CODES'range loop
            for vint_row in 0 to 7 loop
                for vint_palette in 0 to 15 loop
                    vint_origin := 32;
                    if (vint_palette mod 2 = 1) then
                        vint_origin := 508;
                    end if;
                    for vint_foreground in 0 to 1 loop
                        for vint_delay_index in 0 to 2 loop
                            trial(C_CODES(vint_code_index), vint_row, vint_origin,
                                vint_palette, vint_foreground, delay_cycles(vint_delay_index));
                        end loop;
                    end loop;
                end loop;
            end loop;
        end loop;
        begin_row(123, 5, 40, 7, 1, 20);
        wait until falling_edge(s_clk) and s_pending = '1';
        s_reset <= '1';
        s_checking <= '0';
        for vint_cycle in 1 to 2 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        wait until falling_edge(s_clk) and s_ready = '1';
        assert (s_pending = '0') report "Ready before stale reply drained" severity failure;
        trial(456, 6, 508, 3, 0, 0);
        begin_row(123, 4, 20, 5, 1, 0);
        wait until falling_edge(s_clk) and sint_pixels = 2;
        s_reset <= '1';
        s_checking <= '0';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        trial(234, 2, 508, 15, 1, 3);
        begin_row(12, 1, 0, 0, 0, 0);
        s_reset <= '1';
        s_checking <= '0';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        trial(34, 7, 32, 1, 0, 11);
        assert (vint_trials = 4611 and sint_total_pixels = 36890)
            report "Tile-row coverage count changed" severity failure;
        report "TILE_ROW_PASS: 4611 rows, 36890 pixels; byte order, palettes, wrap, waits and reset";
        std.env.finish;
        wait;
    end process;

    watchdog : process
    begin
        wait for 20 ms;
        assert false report "Tile-row timeout" severity failure;
    end process;
end architecture;
