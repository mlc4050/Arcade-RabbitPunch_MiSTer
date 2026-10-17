library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity palette_pixel_tb is
end entity;

architecture test of palette_pixel_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_load, s_valid : std_logic := '0';
    signal s_read, s_output_valid : std_logic;
    signal su10_load_address, su10_index, su10_read_address : unsigned(9 downto 0) := (others => '0');
    signal su16_load_data, su16_read_data : unsigned(15 downto 0) := (others => '0');
    signal su9_x, su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_y, su8_output_y, su8_red, su8_green, su8_blue : unsigned(7 downto 0) := (others => '0');
    signal sint_bank, sint_checked : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_palette_pixel
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pixel_valid => s_valid,
            iu9_pixel_x => su9_x,
            iu8_pixel_y => su8_y,
            iu10_palette_index => su10_index,
            o_ram_read_enable => s_read,
            ou10_ram_word_address => su10_read_address,
            iu16_ram_data => su16_read_data,
            o_pixel_valid => s_output_valid,
            ou9_pixel_x => su9_output_x,
            ou8_pixel_y => su8_output_y,
            ou8_red => su8_red,
            ou8_green => su8_green,
            ou8_blue => su8_blue
        );
    palette_ram : entity work.rabbitpunch_ram16
        generic map (GINT_ADDRESS_BITS => 10)
        port map (
            i_clk => s_clk,
            i_cpu_enable => s_load,
            i_cpu_write => '1',
            iux_cpu_address => su10_load_address,
            iu2_cpu_bytes => "11",
            iu16_cpu_data => su16_load_data,
            ou16_cpu_data => open,
            i_view_enable => s_read,
            iux_view_address => su10_read_address,
            ou16_view_data => su16_read_data
        );
    scoreboard : process(s_clk)
        type t_expected is record
            word_value, x, y, clock_number : natural;
        end record;
        type t_queue is array (0 to 3) of t_expected;
        variable v_queue : t_queue;
        variable vint_clock, vint_accepted, vint_returned, vint_checked : natural := 0;
        variable vu16_word : unsigned(15 downto 0);
        variable v_expected : t_expected;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            if (s_reset = '1') then
                vint_accepted := 0;
                vint_returned := 0;
            else
                if (s_valid = '1') then
                    assert (vint_accepted - vint_returned < 4) report "Palette queue overflow" severity failure;
                    v_queue(vint_accepted mod 4) := (sint_bank * 1024 + to_integer(su10_index),
                        to_integer(su9_x), to_integer(su8_y), vint_clock);
                    vint_accepted := vint_accepted + 1;
                end if;
                if (s_output_valid = '1') then
                    assert (vint_returned < vint_accepted) report "Unrequested palette output" severity failure;
                    v_expected := v_queue(vint_returned mod 4);
                    vu16_word := to_unsigned(v_expected.word_value, 16);
                    assert (vint_clock - v_expected.clock_number = 2 and
                        to_integer(su9_output_x) = v_expected.x and to_integer(su8_output_y) = v_expected.y)
                        report "Palette latency or coordinate mismatch" severity failure;
                    assert (su8_red = (vu16_word(14 downto 10) & vu16_word(14 downto 12)) and
                        su8_green = (vu16_word(9 downto 5) & vu16_word(9 downto 7)) and
                        su8_blue = (vu16_word(4 downto 0) & vu16_word(4 downto 2)))
                        report "Palette RGB555 expansion mismatch" severity failure;
                    vint_checked := vint_checked + 1;
                    vint_returned := vint_returned + 1;
                end if;
            end if;
            sint_checked <= vint_checked;
        end if;
    end process;
    stimulus : process
        procedure request_pixel(vint_address : natural) is
        begin
            su10_index <= to_unsigned(vint_address, 10);
            su9_x <= to_unsigned(vint_address mod 512, 9);
            su8_y <= to_unsigned((vint_address / 512) + sint_bank * 2, 8);
            s_valid <= '1';
        end procedure;
    begin
        -- Exercise every 16-bit RAM value, including both values of unused bit 15.
        for vint_bank in 0 to 63 loop
            sint_bank <= vint_bank;
            for vint_word in 0 to 1023 loop
                wait until falling_edge(s_clk);
                s_load <= '1';
                su10_load_address <= to_unsigned(vint_word, 10);
                su16_load_data <= to_unsigned(vint_bank * 1024 + vint_word, 16);
            end loop;
            wait until falling_edge(s_clk);
            s_load <= '0';
            s_reset <= '0';
            for vint_word in 0 to 1023 loop
                wait until falling_edge(s_clk);
                request_pixel(vint_word);
                if (vint_word mod 17 = 0) then
                    wait until falling_edge(s_clk);
                    s_valid <= '0';
                end if;
            end loop;
            wait until falling_edge(s_clk);
            s_valid <= '0';
            for vint_cycle in 1 to 3 loop
                wait until falling_edge(s_clk);
            end loop;
            assert (sint_checked = (vint_bank + 1) * 1024) report "Palette dropped or added pixels" severity failure;
        end loop;
        -- Reset after acceptance, before the native RAM response becomes RGB.
        request_pixel(1023);
        wait until falling_edge(s_clk);
        s_reset <= '1';
        s_valid <= '0';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
            assert (s_output_valid = '0') report "Palette reset leaked an in-flight pixel" severity failure;
        end loop;
        s_reset <= '0';
        request_pixel(0);
        wait until falling_edge(s_clk);
        request_pixel(1023);
        wait until falling_edge(s_clk);
        s_valid <= '0';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_checked = 65538) report "Palette reset recovery failed" severity failure;
        report "PALETTE_PIXEL_PASS: all 65536 RAM values, streaming, gaps, tags and reset; 65538 outputs";
        std.env.finish;
        wait;
    end process;
end architecture;
