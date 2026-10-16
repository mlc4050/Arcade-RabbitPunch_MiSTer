library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity priority_tb is
end entity;

architecture test of priority_tb is
    signal s_occupied, s_valid, s_old_behind, s_new_behind : std_logic := '0';
    signal su6_old_index, su6_new_index, su6_winner_index : unsigned(5 downto 0) := (others => '0');
    signal su8_old_palette, su8_new_palette, su8_winner_palette : unsigned(7 downto 0) := (others => '0');
    signal s_write, s_winner_occupied, s_winner_behind : std_logic;
    signal su8_background, su8_foreground, su8_sprite, su8_bitmap : unsigned(7 downto 0) := (others => '0');
    signal s_sprite_occupied, s_sprite_behind : std_logic := '0';
    signal su10_palette_index : unsigned(9 downto 0);
begin
    arbitration : entity work.rabbitpunch_sprite_priority
        port map (
            i_occupied => s_occupied,
            iu6_stored_index => su6_old_index,
            iu8_stored_palette => su8_old_palette,
            i_stored_behind_foreground => s_old_behind,
            i_candidate_valid => s_valid,
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
            iu8_sprite => su8_sprite,
            i_sprite_occupied => s_sprite_occupied,
            i_sprite_behind_foreground => s_sprite_behind,
            iu8_bitmap => su8_bitmap,
            ou10_palette_index => su10_palette_index
        );

    stimulus : process
        variable v_accept : boolean;
        variable vint_checks, vint_expected : natural := 0;
        variable vu5_options : unsigned(4 downto 0);
        type t_layer_pixels is array (0 to 3) of unsigned(7 downto 0);
        variable v_layers : t_layer_pixels;
    begin
        for vint_old_index in 0 to 63 loop
            for vint_new_index in 0 to 63 loop
                for vint_pen in 0 to 15 loop
                    for vint_flags in 0 to 3 loop
                        s_occupied <= bit_value(vint_flags mod 2);
                        s_valid <= bit_value(vint_flags / 2);
                        su6_old_index <= to_unsigned(vint_old_index, 6);
                        su6_new_index <= to_unsigned(vint_new_index, 6);
                        su8_old_palette <= to_unsigned((vint_old_index * 3) mod 256, 8);
                        su8_new_palette <= to_unsigned((vint_new_index mod 16) * 16 + vint_pen, 8);
                        s_old_behind <= bit_value(vint_old_index mod 2);
                        s_new_behind <= bit_value(vint_new_index mod 2);
                        wait for 1 ns;
                        v_accept := vint_flags >= 2 and vint_pen /= 15 and
                            (vint_flags mod 2 = 0 or vint_new_index > vint_old_index);
                        assert ((s_write = '1') = v_accept) report "Sprite insertion priority mismatch" severity failure;
                        if (v_accept) then
                            assert (s_winner_occupied = '1' and su6_winner_index = su6_new_index and
                                su8_winner_palette = su8_new_palette and s_winner_behind = s_new_behind)
                                report "Sprite winner metadata mismatch" severity failure;
                        else
                            assert (s_winner_occupied = s_occupied and su6_winner_index = su6_old_index and
                                su8_winner_palette = su8_old_palette and s_winner_behind = s_old_behind)
                                report "Rejected sprite changed stored entry" severity failure;
                        end if;
                        vint_checks := vint_checks + 1;
                    end loop;
                end loop;
            end loop;
        end loop;
        for vint_layer in 0 to 3 loop
            for vint_value in 0 to 255 loop
                for vint_options in 0 to 31 loop
                    vu5_options := to_unsigned(vint_options, 5);
                    v_layers := (x"37", x"56", x"94", x"B2");
                    v_layers(vint_layer) := to_unsigned(vint_value, 8);
                    for vint_transparent in 1 to 3 loop
                        if (vu5_options(vint_transparent - 1) = '1') then
                            v_layers(vint_transparent)(3 downto 0) := x"F";
                        end if;
                    end loop;
                    su8_background <= v_layers(0);
                    su8_foreground <= v_layers(1);
                    su8_sprite <= v_layers(2);
                    su8_bitmap <= v_layers(3);
                    s_sprite_occupied <= vu5_options(3);
                    s_sprite_behind <= vu5_options(4);
                    wait for 1 ns;
                    -- Equivalent MAME layer/priority-mask evaluation.
                    vint_expected := to_integer(v_layers(0));
                    if (v_layers(1)(3 downto 0) /= 15) then
                        vint_expected := 256 + to_integer(v_layers(1));
                    end if;
                    if (vu5_options(3) = '1' and v_layers(2)(3 downto 0) /= 15 and
                        not (vu5_options(4) = '1' and vint_expected >= 256)) then
                        vint_expected := 768 + to_integer(v_layers(2));
                    end if;
                    if (v_layers(3)(3 downto 0) /= 15) then
                        vint_expected := 512 + to_integer(v_layers(3));
                    end if;
                    assert (to_integer(su10_palette_index) = vint_expected)
                        report "Layer mixer priority mismatch" severity failure;
                    vint_checks := vint_checks + 1;
                end loop;
            end loop;
        end loop;
        assert (vint_checks = 294912) report "Priority coverage count changed" severity failure;
        report "PRIORITY_PASS: 262144 sprite arbitration cases and 32768 layer-mixer cases";
        std.env.finish;
        wait;
    end process;
end architecture;
