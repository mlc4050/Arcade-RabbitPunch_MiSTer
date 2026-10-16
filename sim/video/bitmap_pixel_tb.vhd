library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bitmap_pixel_tb is
end entity;

architecture test of bitmap_pixel_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_valid, s_load : std_logic := '0';
    signal su9_x, su9_output_x : unsigned(8 downto 0) := (others => '0');
    signal su8_y, su8_output_y : unsigned(7 downto 0) := (others => '0');
    signal su16_flags, su16_load_data, su16_ram_data : unsigned(15 downto 0) := (others => '0');
    signal su15_load_address, su15_ram_address : unsigned(14 downto 0) := (others => '0');
    signal s_read_enable, s_output_valid : std_logic;
    signal su10_output_index : unsigned(9 downto 0);
    signal sint_checked : natural := 0;
    function bitmap_pen(vint_x, vint_y : natural) return natural is
    begin
        return (vint_x + 3 * vint_y + vint_x / 16 + 5 * (vint_x / 64)) mod 16;
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_bitmap_pixel
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pixel_valid => s_valid,
            iu9_pixel_x => su9_x,
            iu8_pixel_y => su8_y,
            iu16_video_flags => su16_flags,
            o_ram_read_enable => s_read_enable,
            ou15_ram_word_address => su15_ram_address,
            iu16_ram_data => su16_ram_data,
            o_pixel_valid => s_output_valid,
            ou9_pixel_x => su9_output_x,
            ou8_pixel_y => su8_output_y,
            ou10_palette_index => su10_output_index
        );
    bitmap_ram : entity work.rabbitpunch_ram16
        generic map (sint_ADDRESS_BITS => 15)
        port map (
            i_clk => s_clk,
            i_cpu_enable => s_load,
            i_cpu_write => '1',
            iux_cpu_address => su15_load_address,
            iu2_cpu_bytes => "11",
            iu16_cpu_data => su16_load_data,
            ou16_cpu_data => open,
            i_view_enable => s_read_enable,
            iux_view_address => su15_ram_address,
            ou16_view_data => su16_ram_data
        );
    scoreboard : process(s_clk)
        type t_expected is record
            x, y, palette_index, accepted_clock : natural;
        end record;
        type t_pipeline is array (0 to 7) of t_expected;
        variable v_pipeline : t_pipeline;
        variable vint_accepted, vint_returned, vint_clock, vint_checked, vint_x, vint_y : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            if (s_reset = '1') then
                vint_accepted := 0;
                vint_returned := 0;
            else
                if (s_valid = '1') then
                    assert (vint_accepted - vint_returned < 8) report "Bitmap pixel pipeline overflow" severity failure;
                    vint_x := to_integer(su9_x);
                    vint_y := to_integer(su8_y);
                    v_pipeline(vint_accepted mod 8) := (
                        vint_x, vint_y,
                        512 + to_integer(su16_flags(3 downto 0)) * 16 + bitmap_pen((vint_x + 4) mod 512, vint_y),
                        vint_clock
                    );
                    vint_accepted := vint_accepted + 1;
                end if;
                if (s_output_valid = '1') then
                    assert (vint_returned < vint_accepted) report "Unrequested bitmap pixel" severity failure;
                    assert (to_integer(su9_output_x) = v_pipeline(vint_returned mod 8).x and
                        to_integer(su8_output_y) = v_pipeline(vint_returned mod 8).y and
                        to_integer(su10_output_index) = v_pipeline(vint_returned mod 8).palette_index and
                        vint_clock - v_pipeline(vint_returned mod 8).accepted_clock = 2)
                        report "Bitmap streaming coordinate/nibble/bank/latency mismatch" severity failure;
                    vint_returned := vint_returned + 1;
                    vint_checked := vint_checked + 1;
                end if;
            end if;
            sint_checked <= vint_checked;
        end if;
    end process;
    stimulus : process
        variable vu16_word : unsigned(15 downto 0);
        procedure pixel(vint_x, vint_y : natural) is
        begin
            s_valid <= '1';
            su9_x <= to_unsigned(vint_x, 9);
            su8_y <= to_unsigned(vint_y, 8);
            su16_flags <= to_unsigned(16#A5B0# + (vint_x + 3 * vint_y) mod 16, 16);
        end procedure;
    begin
        for vint_word in 0 to 32767 loop
            for vint_pixel in 0 to 3 loop
                vu16_word(15 - vint_pixel * 4 downto 12 - vint_pixel * 4) :=
                    to_unsigned(bitmap_pen((vint_word mod 128) * 4 + vint_pixel, vint_word / 128), 4);
            end loop;
            wait until falling_edge(s_clk);
            s_load <= '1';
            su15_load_address <= to_unsigned(vint_word, 15);
            su16_load_data <= vu16_word;
        end loop;
        wait until falling_edge(s_clk);
        s_load <= '0';
        s_reset <= '0';
        for vint_y in 0 to 255 loop
            for vint_x in 0 to 511 loop
                wait until falling_edge(s_clk);
                if (vint_x mod 17 = 0) then
                    s_valid <= '0';
                    su9_x <= not to_unsigned(vint_x, 9);
                    su8_y <= not to_unsigned(vint_y, 8);
                    su16_flags <= (others => '1');
                    wait until falling_edge(s_clk);
                end if;
                pixel(vint_x, vint_y);
            end loop;
        end loop;
        wait until falling_edge(s_clk);
        s_valid <= '0';
        for vint_cycle in 1 to 4 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_checked = 131072) report "Bitmap coordinate coverage changed" severity failure;
        pixel(511, 255);
        wait until falling_edge(s_clk);
        s_valid <= '0';
        s_reset <= '1';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        pixel(509, 17);
        wait until falling_edge(s_clk);
        pixel(510, 18);
        wait until falling_edge(s_clk);
        s_valid <= '0';
        for vint_cycle in 1 to 4 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_checked = 131074) report "Bitmap reset replay count mismatch" severity failure;
        report "BITMAP_PIXEL_PASS: all 131072 coordinates, all palette banks, native RAM, streaming gaps and reset";
        std.env.finish;
        wait;
    end process;
end architecture;
