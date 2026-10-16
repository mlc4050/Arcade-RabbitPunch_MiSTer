library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package tile_test_support is
    type t_unsigned_words is array (natural range <>) of unsigned;
    function bit_value(vint_value : integer) return std_logic;
    function delay_cycles(vint_address : natural) return natural;
    function descriptor(vint_address : natural) return unsigned;
    function pen(vint_code, vint_row, vint_pixel, vint_foreground : natural) return natural;
    function packed_row(iu17_address : unsigned(16 downto 0);
                        vint_foreground : natural := 0) return unsigned;
    impure function read_hex(v_filename : string; vint_count, vint_width : positive)
        return t_unsigned_words;
end package;

package body tile_test_support is
    function bit_value(vint_value : integer) return std_logic is
    begin
        if (vint_value = 0) then
            return '0';
        end if;
        return '1';
    end function;

    function delay_cycles(vint_address : natural) return natural is
    begin
        case vint_address mod 3 is
            when 0 => return 0;
            when 1 => return 3;
            when others => return 11;
        end case;
    end function;

    function descriptor(vint_address : natural) return unsigned is
    begin
        return to_unsigned((vint_address * 16#9E37#) mod 65536, 16) xor x"B123";
    end function;

    function pen(vint_code, vint_row, vint_pixel, vint_foreground : natural) return natural is
    begin
        return (vint_code + 3 * vint_row + vint_pixel + 5 * vint_foreground) mod 16;
    end function;

    function packed_row(iu17_address : unsigned(16 downto 0);
                        vint_foreground : natural := 0) return unsigned is
        variable vu32_result : unsigned(31 downto 0) := (others => '0');
    begin
        for vint_pixel in 0 to 7 loop
            vu32_result(vint_pixel * 4 + 3 downto vint_pixel * 4) := to_unsigned(
                pen(to_integer(iu17_address) / 8, to_integer(iu17_address) mod 8,
                    vint_pixel, vint_foreground), 4);
        end loop;
        return vu32_result;
    end function;

    impure function read_hex(v_filename : string; vint_count, vint_width : positive)
        return t_unsigned_words is
        file v_file : text open read_mode is v_filename;
        variable v_line : line;
        variable v_character : character;
        variable vint_nibble : natural;
        variable v_result : t_unsigned_words(0 to vint_count - 1)(vint_width - 1 downto 0);
    begin
        for vint_word in v_result'range loop
            assert (not endfile(v_file)) report "Short hex input: " & v_filename severity failure;
            readline(v_file, v_line);
            v_result(vint_word) := (others => '0');
            while (v_line'length > 0) loop
                read(v_line, v_character);
                case v_character is
                    when '0' to '9' => vint_nibble := character'pos(v_character) - character'pos('0');
                    when 'a' to 'f' => vint_nibble := character'pos(v_character) - character'pos('a') + 10;
                    when 'A' to 'F' => vint_nibble := character'pos(v_character) - character'pos('A') + 10;
                    when others =>
                        assert false report "Invalid hex input: " & v_filename severity failure;
                        vint_nibble := 0;
                end case;
                v_result(vint_word) := shift_left(v_result(vint_word), 4)
                    or to_unsigned(vint_nibble, vint_width);
            end loop;
        end loop;
        assert (endfile(v_file)) report "Extra hex input: " & v_filename severity failure;
        return v_result;
    end function;
end package body;
