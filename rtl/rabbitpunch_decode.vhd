library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity rabbitpunch_decode is
    port (
        address : in std_logic_vector(23 downto 0);
        active, rw, uds_n, lds_n : in std_logic;
        target : out target_t
    );
end entity;

architecture rtl of rabbitpunch_decode is
begin
    process(address, active, rw, uds_n, lds_n)
        variable masked : unsigned(19 downto 0);
        variable a : natural range 0 to 16#FFFFF#;
        variable selected : target_t;
    begin
        -- MAME's global_mask is 20 bits; the strobes select bytes within the word.
        selected := TARGET_NONE;
        if active = '1' and (uds_n = '0' or lds_n = '0') and not is_x(address) then
            masked := unsigned(address(19 downto 0));
            masked(0) := '0';
            a := to_integer(masked);
            if a <= 16#03FFFF# then
                if rw = '1' then selected := TARGET_ROM; end if;
            elsif a >= 16#040000# and a <= 16#04FFFF# then
                selected := TARGET_BITMAP;
            elsif a >= 16#060000# and a <= 16#060FFF# then
                selected := TARGET_SPRITES;
            elsif a >= 16#080000# and a <= 16#083FFF# then
                selected := TARGET_TILES;
            elsif a >= 16#0A0000# and a <= 16#0A07FF# then
                selected := TARGET_PALETTE;
            elsif a >= 16#0FC000# then
                selected := TARGET_WORKRAM;
            elsif rw = '0' then
                if a >= 16#0C0000# and a <= 16#0C0006# then
                    -- The reference driver changes scroll only for full-word writes.
                    if uds_n = '0' and lds_n = '0' then selected := TARGET_SCROLL; end if;
                elsif a = 16#0C000C# then
                    selected := TARGET_VIDEO_FLAGS;
                elsif lds_n = '0' then
                    case a is
                        when 16#0C0008# => selected := TARGET_GGA_DATA;
                        when 16#0C0028# => selected := TARGET_GGA_SELECT;
                        when 16#0C000E# => selected := TARGET_SOUND_COMMAND;
                        when 16#0C0010# => selected := TARGET_SPRITE_COUNT;
                        when 16#0C0012# => selected := TARGET_SPRITE_PRIORITY;
                        when others => null;
                    end case;
                end if;
            else
                case a is
                    when 16#0C0018# => selected := TARGET_P1;
                    when 16#0C001A# => selected := TARGET_P2;
                    when 16#0C001C# => selected := TARGET_DSW;
                    when 16#0C001E# => selected := TARGET_SOUND_PENDING;
                    when others => null;
                end case;
            end if;
        end if;
        target <= selected;
    end process;
end architecture;
