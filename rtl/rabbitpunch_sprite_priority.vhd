library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Combinational update for one sprite-line entry. A hidden opaque winner still
-- occupies the entry, reproducing MAME's priority=31 marking. No RAM is here.
entity rabbitpunch_sprite_priority is
    port (
        i_occupied : in std_logic;
        iu6_stored_index : in unsigned(5 downto 0);
        iu8_stored_palette : in unsigned(7 downto 0);
        i_stored_behind_foreground : in std_logic;
        i_candidate_valid : in std_logic;
        iu6_candidate_index : in unsigned(5 downto 0);
        iu8_candidate_palette : in unsigned(7 downto 0);
        i_candidate_behind_foreground : in std_logic;
        o_write : out std_logic;
        o_occupied : out std_logic;
        ou6_winner_index : out unsigned(5 downto 0);
        ou8_winner_palette : out unsigned(7 downto 0);
        o_winner_behind_foreground : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_sprite_priority is
begin
    process(all)
    begin
        o_write <= '0';
        o_occupied <= i_occupied;
        ou6_winner_index <= iu6_stored_index;
        ou8_winner_palette <= iu8_stored_palette;
        o_winner_behind_foreground <= i_stored_behind_foreground;
        if (i_candidate_valid = '1' and iu8_candidate_palette(3 downto 0) /= 15) then
            if (i_occupied = '0' or iu6_candidate_index > iu6_stored_index) then
                o_write <= '1';
                o_occupied <= '1';
                ou6_winner_index <= iu6_candidate_index;
                ou8_winner_palette <= iu8_candidate_palette;
                o_winner_behind_foreground <= i_candidate_behind_foreground;
            end if;
        end if;
    end process;
end architecture;
