library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity tile_line_tb is
end entity;

architecture test of tile_line_tb is
    constant C_SETTINGS : t_unsigned_words := read_hex("settings.hex", 5, 16);
    constant C_RAM : t_unsigned_words := read_hex("vram.hex", 8192, 16);
    constant C_ROM0 : t_unsigned_words := read_hex("tiles0.hex", 131072, 32);
    constant C_ROM1 : t_unsigned_words := read_hex("tiles1.hex", 131072, 32);
    constant C_EXPECTED : t_unsigned_words := read_hex("line_entries.hex", 216 * 512, 16);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_valid, s_bank : std_logic := '0';
    signal s_ready, s_done, s_ram_request, s_rom_request, s_rom_foreground : std_logic;
    signal su9_y, su9_background_x, su9_background_y, su9_foreground_x, su9_foreground_y : unsigned(8 downto 0) := (others => '0');
    signal su16_flags, su16_ram_data : unsigned(15 downto 0) := (others => '0');
    signal su13_ram_address : unsigned(12 downto 0);
    signal su17_rom_address : unsigned(16 downto 0);
    signal su32_rom_data : unsigned(31 downto 0) := (others => '0');
    signal s_ram_valid, s_rom_valid, s_ram_pending, s_rom_pending : std_logic := '0';
    signal s_view_enable, s_view_ready, s_view_valid : std_logic := '0';
    signal su9_view_x : unsigned(8 downto 0) := (others => '0');
    signal su9_view_y : unsigned(8 downto 0);
    signal su16_view_pixels : unsigned(15 downto 0);
    signal sint_view_y, sint_view_checks : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_tiles
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_line_valid => s_valid,
            o_line_ready => s_ready,
            i_render_bank => s_bank,
            iu9_line_y => su9_y,
            iu9_background_scroll_x => su9_background_x,
            iu9_background_scroll_y => su9_background_y,
            iu9_foreground_scroll_x => su9_foreground_x,
            iu9_foreground_scroll_y => su9_foreground_y,
            iu16_video_flags => su16_flags,
            o_line_done => s_done,
            o_ram_request => s_ram_request,
            ou13_ram_word_address => su13_ram_address,
            i_ram_response_valid => s_ram_valid,
            iu16_ram_response_data => su16_ram_data,
            o_rom_request => s_rom_request,
            ou17_rom_word_address => su17_rom_address,
            o_rom_foreground => s_rom_foreground,
            i_rom_response_valid => s_rom_valid,
            iu32_rom_response_data => su32_rom_data,
            i_view_enable => s_view_enable,
            o_view_ready => s_view_ready,
            i_view_bank => bit_value(sint_view_y mod 2),
            iu9_view_x => su9_view_x,
            o_view_valid => s_view_valid,
            ou9_view_line_y => su9_view_y,
            ou16_view_pixels => su16_view_pixels
        );
    display_address : process(s_clk)
    begin
        if (falling_edge(s_clk)) then
            su9_view_x <= su9_view_x + 1;
        end if;
    end process;
    responder : process(s_clk)
        variable vint_ram_delay, vint_rom_delay, vint_view_x, vint_view_y : natural := 0;
        variable vu13_saved_ram : unsigned(12 downto 0);
        variable vu17_saved_rom : unsigned(16 downto 0);
        variable v_foreground : boolean;
    begin
        if (rising_edge(s_clk)) then
            s_ram_valid <= '0';
            if (s_ram_request = '1') then
                assert (s_ram_pending = '0') report "Overlapping tile-line descriptor requests" severity failure;
                vu13_saved_ram := su13_ram_address;
                vint_ram_delay := delay_cycles(to_integer(su13_ram_address));
                s_ram_pending <= '1';
            elsif (s_ram_pending = '1') then
                if (vint_ram_delay = 0) then
                    s_ram_pending <= '0';
                    s_ram_valid <= '1';
                    su16_ram_data <= C_RAM(to_integer(vu13_saved_ram));
                else
                    vint_ram_delay := vint_ram_delay - 1;
                end if;
            end if;
            s_rom_valid <= '0';
            if (s_rom_request = '1') then
                assert (s_rom_pending = '0') report "Overlapping tile-line graphics requests" severity failure;
                vu17_saved_rom := su17_rom_address;
                v_foreground := s_rom_foreground = '1';
                vint_rom_delay := delay_cycles(to_integer(su17_rom_address));
                s_rom_pending <= '1';
            elsif (s_rom_pending = '1') then
                if (vint_rom_delay = 0) then
                    s_rom_pending <= '0';
                    s_rom_valid <= '1';
                    if (v_foreground) then
                        su32_rom_data <= C_ROM1(to_integer(vu17_saved_rom));
                    else
                        su32_rom_data <= C_ROM0(to_integer(vu17_saved_rom));
                    end if;
                else
                    vint_rom_delay := vint_rom_delay - 1;
                end if;
            end if;
            if (s_view_valid = '1' and s_reset = '0') then
                assert (su16_view_pixels = C_EXPECTED(vint_view_y * 512 + vint_view_x))
                    report "Packed tile line mismatch y=" & integer'image(vint_view_y) &
                        " x=" & integer'image(vint_view_x) severity failure;
                assert (su9_view_y = vint_view_y) report "Packed tile line Y mismatch" severity failure;
                sint_view_checks <= sint_view_checks + 1;
            end if;
            if (s_view_enable = '1' and s_view_ready = '1') then
                vint_view_x := to_integer(su9_view_x);
                vint_view_y := sint_view_y;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_trials, vint_max_cycles : natural := 0;
        procedure begin_line(vint_y : natural) is
        begin
            wait until falling_edge(s_clk) and s_ready = '1';
            su9_y <= to_unsigned(vint_y, 9);
            s_bank <= bit_value(vint_y mod 2);
            su16_flags <= C_SETTINGS(0);
            su9_background_y <= C_SETTINGS(1)(8 downto 0);
            su9_background_x <= C_SETTINGS(2)(8 downto 0);
            su9_foreground_y <= C_SETTINGS(3)(8 downto 0);
            su9_foreground_x <= C_SETTINGS(4)(8 downto 0);
            s_valid <= '1';
            wait until falling_edge(s_clk);
            s_valid <= '0';
            su9_y <= not to_unsigned(vint_y, 9);
            s_bank <= not bit_value(vint_y mod 2);
            su16_flags <= not C_SETTINGS(0);
            su9_background_y <= not C_SETTINGS(1)(8 downto 0);
            su9_background_x <= not C_SETTINGS(2)(8 downto 0);
            su9_foreground_y <= not C_SETTINGS(3)(8 downto 0);
            su9_foreground_x <= not C_SETTINGS(4)(8 downto 0);
        end procedure;
        procedure trial(vint_y : natural) is
            variable vint_cycles, vint_before_checks : natural := 0;
        begin
            begin_line(vint_y);
            while (s_done /= '1') loop
                wait until falling_edge(s_clk);
                vint_cycles := vint_cycles + 1;
            end loop;
            assert (s_ready = '1' and s_ram_pending = '0' and s_rom_pending = '0')
                report "Packed tile line completed with pending fetch" severity failure;
            if (vint_cycles > vint_max_cycles) then
                vint_max_cycles := vint_cycles;
            end if;
            sint_view_y <= vint_y;
            s_view_enable <= '1';
            vint_before_checks := sint_view_checks;
            wait until falling_edge(s_clk) and sint_view_checks >= vint_before_checks + 1024;
            vint_trials := vint_trials + 1;
        end procedure;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        for vint_y in 0 to 215 loop
            trial(vint_y);
        end loop;
        for vint_abort in 0 to 1 loop
            s_view_enable <= '0';
            for vint_cycle in 1 to 2 loop
                wait until falling_edge(s_clk);
            end loop;
            begin_line(0);
            if (vint_abort = 0) then
                wait until falling_edge(s_clk) and s_ram_pending = '1';
            else
                wait until falling_edge(s_clk) and s_rom_pending = '1';
            end if;
            s_reset <= '1';
            for vint_cycle in 1 to 3 loop
                wait until falling_edge(s_clk);
            end loop;
            s_reset <= '0';
            wait until falling_edge(s_clk) and s_ready = '1';
            assert (s_ram_pending = '0' and s_rom_pending = '0' and s_view_ready = '0')
                report "Packed tile line reset did not drain/invalidate" severity failure;
            trial(0);
        end loop;
        report "TILE_LINE_PASS: " & integer'image(vint_trials) &
            " lines; max_cycles=" & integer'image(vint_max_cycles) &
            "; every packed pixel, concurrent readout and reset";
        std.env.finish;
        wait;
    end process;
end architecture;
