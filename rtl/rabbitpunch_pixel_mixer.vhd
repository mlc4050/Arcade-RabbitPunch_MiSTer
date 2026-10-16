library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Inputs refer to the same output coordinate. Layer-local indices are eight
-- bits; the selected layer supplies the top two palette-address bits.
entity rabbitpunch_pixel_mixer is
    port (
        iu8_background : in unsigned(7 downto 0);
        iu8_foreground : in unsigned(7 downto 0);
        iu8_sprite : in unsigned(7 downto 0);
        i_sprite_occupied : in std_logic;
        i_sprite_behind_foreground : in std_logic;
        iu8_bitmap : in unsigned(7 downto 0);
        ou10_palette_index : out unsigned(9 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_pixel_mixer is
begin
    process(all)
    begin
        ou10_palette_index <= "00" & iu8_background;
        if (iu8_foreground(3 downto 0) /= 15) then
            ou10_palette_index <= "01" & iu8_foreground;
        end if;
        if (i_sprite_occupied = '1' and iu8_sprite(3 downto 0) /= 15) then
            if (i_sprite_behind_foreground = '0' or iu8_foreground(3 downto 0) = 15) then
                ou10_palette_index <= "11" & iu8_sprite;
            end if;
        end if;
        if (iu8_bitmap(3 downto 0) /= 15) then
            ou10_palette_index <= "10" & iu8_bitmap;
        end if;
    end process;
end architecture;
