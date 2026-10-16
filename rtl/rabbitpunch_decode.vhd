library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity rabbitpunch_decode is
    port (
        iu24_address : in unsigned(23 downto 0);
        i_active, i_read, i_upper_byte_strobe_n, i_lower_byte_strobe_n : in std_logic;
        ou5_target : out target_t
    );
end entity;

architecture rtl of rabbitpunch_decode is
begin
    process(iu24_address, i_active, i_read, i_upper_byte_strobe_n, i_lower_byte_strobe_n)
        variable vu20_masked : unsigned(19 downto 0);
        variable vint_address : natural range 0 to 16#FFFFF#;
        variable vu5_selected : target_t;
    begin
        -- MAME's global_mask is 20 bits; the strobes select bytes within the word.
        vu5_selected := TARGET_NONE;
        if i_active = '1' and (i_upper_byte_strobe_n = '0' or i_lower_byte_strobe_n = '0') and not is_x(iu24_address) then
            vu20_masked := unsigned(iu24_address(19 downto 0));
            vu20_masked(0) := '0';
            vint_address := to_integer(vu20_masked);
            if vint_address <= 16#03FFFF# then
                if i_read = '1' then vu5_selected := TARGET_ROM; end if;
            elsif vint_address >= 16#040000# and vint_address <= 16#04FFFF# then
                vu5_selected := TARGET_BITMAP;
            elsif vint_address >= 16#060000# and vint_address <= 16#060FFF# then
                vu5_selected := TARGET_SPRITES;
            elsif vint_address >= 16#080000# and vint_address <= 16#083FFF# then
                vu5_selected := TARGET_TILES;
            elsif vint_address >= 16#0A0000# and vint_address <= 16#0A07FF# then
                vu5_selected := TARGET_PALETTE;
            elsif vint_address >= 16#0FC000# then
                vu5_selected := TARGET_WORKRAM;
            elsif i_read = '0' then
                if vint_address >= 16#0C0000# and vint_address <= 16#0C0006# then
                    -- The reference driver changes scroll only for full-word writes.
                    if i_upper_byte_strobe_n = '0' and i_lower_byte_strobe_n = '0' then vu5_selected := TARGET_SCROLL; end if;
                elsif vint_address = 16#0C000C# then
                    vu5_selected := TARGET_VIDEO_FLAGS;
                elsif i_lower_byte_strobe_n = '0' then
                    case vint_address is
                        when 16#0C0008# => vu5_selected := TARGET_GGA_DATA;
                        when 16#0C0028# => vu5_selected := TARGET_GGA_SELECT;
                        when 16#0C000E# => vu5_selected := TARGET_SOUND_COMMAND;
                        when 16#0C0010# => vu5_selected := TARGET_SPRITE_COUNT;
                        when 16#0C0012# => vu5_selected := TARGET_SPRITE_PRIORITY;
                        when others => null;
                    end case;
                end if;
            else
                case vint_address is
                    when 16#0C0018# => vu5_selected := TARGET_P1;
                    when 16#0C001A# => vu5_selected := TARGET_P2;
                    when 16#0C001C# => vu5_selected := TARGET_DSW;
                    when 16#0C001E# => vu5_selected := TARGET_SOUND_PENDING;
                    when others => null;
                end case;
            end if;
        end if;
        ou5_target <= vu5_selected;
    end process;
end architecture;
