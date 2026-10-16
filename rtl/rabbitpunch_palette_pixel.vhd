library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One-clock native palette RAM followed by RGB555 expansion. No brightness,
-- gamma or CRT shader adjustment is applied to the board's logical colors.
entity rabbitpunch_palette_pixel is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_pixel_valid : in std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        iu10_palette_index : in unsigned(9 downto 0);
        o_ram_read_enable : out std_logic;
        ou10_ram_word_address : out unsigned(9 downto 0);
        iu16_ram_data : in unsigned(15 downto 0);
        o_pixel_valid : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_palette_pixel is
    signal s_valid : std_logic := '0';
    signal su9_pixel_x : unsigned(8 downto 0);
    signal su8_pixel_y : unsigned(7 downto 0);
begin
    ou10_ram_word_address <= iu10_palette_index;
    o_ram_read_enable <= i_pixel_valid and not i_reset;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_valid <= i_pixel_valid;
            o_pixel_valid <= s_valid;
            if (i_pixel_valid = '1') then
                su9_pixel_x <= iu9_pixel_x;
                su8_pixel_y <= iu8_pixel_y;
            end if;
            if (s_valid = '1') then
                ou9_pixel_x <= su9_pixel_x;
                ou8_pixel_y <= su8_pixel_y;
                ou8_red <= iu16_ram_data(14 downto 10) & iu16_ram_data(14 downto 12);
                ou8_green <= iu16_ram_data(9 downto 5) & iu16_ram_data(9 downto 7);
                ou8_blue <= iu16_ram_data(4 downto 0) & iu16_ram_data(4 downto 2);
            end if;
            if (i_reset = '1') then
                s_valid <= '0';
                o_pixel_valid <= '0';
            end if;
        end if;
    end process;
end architecture;
