library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Tilemap lookup and JTFRAME row drawing, without raster or line storage.
entity rabbitpunch_tile_layer is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_request_valid : in std_logic;
        o_request_ready : out std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu9_pixel_y : in unsigned(8 downto 0);
        iu9_scroll_x : in unsigned(8 downto 0);
        iu9_scroll_y : in unsigned(8 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        i_foreground : in std_logic;
        o_ram_request : out std_logic;
        ou13_ram_word_address : out unsigned(12 downto 0);
        i_ram_response_valid : in std_logic;
        iu16_ram_response_data : in unsigned(15 downto 0);
        o_rom_request : out std_logic;
        ou17_rom_word_address : out unsigned(16 downto 0);
        o_rom_foreground : out std_logic;
        i_rom_response_valid : in std_logic;
        iu32_rom_response_data : in unsigned(31 downto 0);
        o_pixel_valid : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou9_pixel_y : out unsigned(8 downto 0);
        ou9_palette_index : out unsigned(8 downto 0);
        o_opaque : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_tile_layer is
    signal s_row_valid, s_row_ready, s_foreground : std_logic;
    signal su14_tile_code : unsigned(13 downto 0);
    signal su3_tile_row : unsigned(2 downto 0);
    signal su9_pixel_x, su9_pixel_y : unsigned(8 downto 0);
    signal su4_palette : unsigned(3 downto 0);
begin
    lookup : entity work.rabbitpunch_tile_lookup
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_request_valid => i_request_valid,
            o_request_ready => o_request_ready,
            iu9_pixel_x => iu9_pixel_x,
            iu9_pixel_y => iu9_pixel_y,
            iu9_scroll_x => iu9_scroll_x,
            iu9_scroll_y => iu9_scroll_y,
            iu16_video_flags => iu16_video_flags,
            i_foreground => i_foreground,
            o_ram_request => o_ram_request,
            ou13_ram_word_address => ou13_ram_word_address,
            i_ram_response_valid => i_ram_response_valid,
            iu16_ram_response_data => iu16_ram_response_data,
            o_row_valid => s_row_valid,
            i_row_ready => s_row_ready,
            ou14_tile_code => su14_tile_code,
            ou3_tile_row => su3_tile_row,
            ou9_pixel_x => su9_pixel_x,
            ou9_pixel_y => su9_pixel_y,
            ou4_palette => su4_palette,
            o_foreground => s_foreground
        );
    row : entity work.rabbitpunch_tile_row
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_row_valid => s_row_valid,
            o_row_ready => s_row_ready,
            iu14_tile_code => su14_tile_code,
            iu3_tile_row => su3_tile_row,
            iu9_pixel_x => su9_pixel_x,
            iu9_pixel_y => su9_pixel_y,
            iu4_palette => su4_palette,
            i_foreground => s_foreground,
            o_rom_request => o_rom_request,
            ou17_rom_word_address => ou17_rom_word_address,
            o_rom_foreground => o_rom_foreground,
            i_rom_response_valid => i_rom_response_valid,
            iu32_rom_response_data => iu32_rom_response_data,
            o_pixel_valid => o_pixel_valid,
            ou9_pixel_x => ou9_pixel_x,
            ou9_pixel_y => ou9_pixel_y,
            ou9_palette_index => ou9_palette_index,
            o_opaque => o_opaque
        );
end architecture;
