library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Synthesis evaluation only. Output registers bound the timing paths of the
-- combinational priority blocks; this is not the final video pipeline.
entity priority_check is
    port (
        i_clk : in std_logic;
        i_occupied : in std_logic;
        iu6_stored_index : in unsigned(5 downto 0);
        iu8_stored_palette : in unsigned(7 downto 0);
        i_stored_behind_foreground : in std_logic;
        i_candidate_valid : in std_logic;
        iu6_candidate_index : in unsigned(5 downto 0);
        iu8_candidate_palette : in unsigned(7 downto 0);
        i_candidate_behind_foreground : in std_logic;
        iu8_background : in unsigned(7 downto 0);
        iu8_foreground : in unsigned(7 downto 0);
        iu8_bitmap : in unsigned(7 downto 0);
        o_write : out std_logic;
        o_occupied : out std_logic;
        ou6_winner_index : out unsigned(5 downto 0);
        ou8_winner_palette : out unsigned(7 downto 0);
        o_winner_behind_foreground : out std_logic;
        ou10_palette_index : out unsigned(9 downto 0)
    );
end entity;

architecture evaluation of priority_check is
    signal s_write, s_occupied, s_behind : std_logic;
    signal su6_index : unsigned(5 downto 0);
    signal su8_palette : unsigned(7 downto 0);
    signal su10_palette_index : unsigned(9 downto 0);
begin
    arbitration : entity work.rabbitpunch_sprite_priority
        port map (
            i_occupied => i_occupied,
            iu6_stored_index => iu6_stored_index,
            iu8_stored_palette => iu8_stored_palette,
            i_stored_behind_foreground => i_stored_behind_foreground,
            i_candidate_valid => i_candidate_valid,
            iu6_candidate_index => iu6_candidate_index,
            iu8_candidate_palette => iu8_candidate_palette,
            i_candidate_behind_foreground => i_candidate_behind_foreground,
            o_write => s_write,
            o_occupied => s_occupied,
            ou6_winner_index => su6_index,
            ou8_winner_palette => su8_palette,
            o_winner_behind_foreground => s_behind
        );
    mixer : entity work.rabbitpunch_pixel_mixer
        port map (
            iu8_background => iu8_background,
            iu8_foreground => iu8_foreground,
            iu8_sprite => su8_palette,
            i_sprite_occupied => s_occupied,
            i_sprite_behind_foreground => s_behind,
            iu8_bitmap => iu8_bitmap,
            ou10_palette_index => su10_palette_index
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_write <= s_write;
            o_occupied <= s_occupied;
            ou6_winner_index <= su6_index;
            ou8_winner_palette <= su8_palette;
            o_winner_behind_foreground <= s_behind;
            ou10_palette_index <= su10_palette_index;
        end if;
    end process;
end architecture;
