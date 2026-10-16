library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tile_test_support.all;

entity mixer_capture_tb is
end entity;

architecture test of mixer_capture_tb is
    constant C_COUNTS : t_unsigned_words := read_hex("counts.hex", 1, 32);
    constant C_BASE : t_unsigned_words := read_hex("base.hex", 62208, 32);
    constant C_CANDIDATES : t_unsigned_words := read_hex("candidates.hex", to_integer(C_COUNTS(0)), 16);
    signal s_occupied, s_old_behind, s_new_behind : std_logic := '0';
    signal su6_old_index, su6_new_index, su6_winner_index : unsigned(5 downto 0) := (others => '0');
    signal su8_old_palette, su8_new_palette, su8_winner_palette : unsigned(7 downto 0) := (others => '0');
    signal s_write, s_winner_occupied, s_winner_behind : std_logic;
    signal su8_background, su8_foreground, su8_bitmap : unsigned(7 downto 0) := (others => '0');
    signal su10_palette_index : unsigned(9 downto 0);
begin
    arbitration : entity work.rabbitpunch_sprite_priority
        port map (
            i_occupied => s_occupied,
            iu6_stored_index => su6_old_index,
            iu8_stored_palette => su8_old_palette,
            i_stored_behind_foreground => s_old_behind,
            i_candidate_valid => '1',
            iu6_candidate_index => su6_new_index,
            iu8_candidate_palette => su8_new_palette,
            i_candidate_behind_foreground => s_new_behind,
            o_write => s_write,
            o_occupied => s_winner_occupied,
            ou6_winner_index => su6_winner_index,
            ou8_winner_palette => su8_winner_palette,
            o_winner_behind_foreground => s_winner_behind
        );
    mixer : entity work.rabbitpunch_pixel_mixer
        port map (
            iu8_background => su8_background,
            iu8_foreground => su8_foreground,
            iu8_sprite => su8_old_palette,
            i_sprite_occupied => s_occupied,
            i_sprite_behind_foreground => s_old_behind,
            iu8_bitmap => su8_bitmap,
            ou10_palette_index => su10_palette_index
        );

    stimulus : process
        file v_output : text open write_mode is "pixels.hex";
        variable v_line : line;
        variable vint_candidate : natural := 0;
    begin
        for vint_pixel in C_BASE'range loop
            su8_background <= C_BASE(vint_pixel)(7 downto 0);
            su8_foreground <= C_BASE(vint_pixel)(15 downto 8);
            su8_bitmap <= C_BASE(vint_pixel)(23 downto 16);
            s_occupied <= '0';
            su6_old_index <= (others => '0');
            su8_old_palette <= x"0F";
            s_old_behind <= '0';
            wait for 1 ns;
            for vint_entry in 1 to to_integer(C_BASE(vint_pixel)(29 downto 24)) loop
                assert (vint_candidate < C_CANDIDATES'length) report "Missing sprite candidate" severity failure;
                su6_new_index <= C_CANDIDATES(vint_candidate)(5 downto 0);
                su8_new_palette <= C_CANDIDATES(vint_candidate)(13 downto 6);
                s_new_behind <= C_CANDIDATES(vint_candidate)(14);
                wait for 1 ns;
                -- Test-only feedback emulates one line-entry update. This array
                -- of vectors is not a framebuffer in the synthesizable design.
                s_occupied <= s_winner_occupied;
                su6_old_index <= su6_winner_index;
                su8_old_palette <= su8_winner_palette;
                s_old_behind <= s_winner_behind;
                wait for 1 ns;
                vint_candidate := vint_candidate + 1;
            end loop;
            write(v_line, to_hstring(su10_palette_index));
            writeline(v_output, v_line);
        end loop;
        assert (vint_candidate = C_CANDIDATES'length) report "Unused sprite candidates" severity failure;
        file_close(v_output);
        report "MIXER_CAPTURE_PASS: 62208 palette indices emitted through VHDL priority and mixing";
        std.env.finish;
        wait;
    end process;
end architecture;
