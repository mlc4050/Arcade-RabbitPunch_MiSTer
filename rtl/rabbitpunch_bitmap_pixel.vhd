library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Native bitmap RAM read: address/read-enable are sampled on this edge, and
-- its synchronous read data must be stable before the following edge. Accepts
-- one coordinate every clock; no variable-latency transport or frame storage.
entity rabbitpunch_bitmap_pixel is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_pixel_valid : in std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        o_ram_read_enable : out std_logic;
        ou15_ram_word_address : out unsigned(14 downto 0);
        iu16_ram_data : in unsigned(15 downto 0);
        o_pixel_valid : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou10_palette_index : out unsigned(9 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_bitmap_pixel is
    signal su9_source_x, su9_pixel_x : unsigned(8 downto 0);
    signal su8_pixel_y : unsigned(7 downto 0);
    signal su2_nibble : unsigned(1 downto 0);
    signal su4_palette : unsigned(3 downto 0);
    signal s_valid : std_logic := '0';
begin
    su9_source_x <= iu9_pixel_x + 4;
    ou15_ram_word_address <= iu8_pixel_y & su9_source_x(8 downto 2);
    o_ram_read_enable <= i_pixel_valid and not i_reset;
    process(i_clk)
        variable vu4_pen : unsigned(3 downto 0);
    begin
        if (rising_edge(i_clk)) then
            s_valid <= i_pixel_valid;
            o_pixel_valid <= s_valid;
            if (i_pixel_valid = '1') then
                su9_pixel_x <= iu9_pixel_x;
                su8_pixel_y <= iu8_pixel_y;
                su2_nibble <= su9_source_x(1 downto 0);
                su4_palette <= iu16_video_flags(3 downto 0);
            end if;
            if (s_valid = '1') then
                case su2_nibble is
                    when "00" => vu4_pen := iu16_ram_data(15 downto 12);
                    when "01" => vu4_pen := iu16_ram_data(11 downto 8);
                    when "10" => vu4_pen := iu16_ram_data(7 downto 4);
                    when others => vu4_pen := iu16_ram_data(3 downto 0);
                end case;
                ou9_pixel_x <= su9_pixel_x;
                ou8_pixel_y <= su8_pixel_y;
                ou10_palette_index <= "10" & su4_palette & vu4_pen;
            end if;
            if (i_reset = '1') then
                s_valid <= '0';
                o_pixel_valid <= '0';
            end if;
        end if;
    end process;
end architecture;
