library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- CPU transaction interface and logical RGB renderer share the physical board
-- RAM banks. Graphics/program ROM transports and the physical raster are external.
entity rabbitpunch_board_video is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_line_valid : in std_logic;
        o_line_ready : out std_logic;
        i_render_bank : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        iu6_sprite_count : in unsigned(5 downto 0);
        iu6_sprite_priority : in unsigned(5 downto 0);
        iu9_background_scroll_x : in unsigned(8 downto 0);
        iu9_background_scroll_y : in unsigned(8 downto 0);
        iu9_foreground_scroll_x : in unsigned(8 downto 0);
        iu9_foreground_scroll_y : in unsigned(8 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        o_line_done : out std_logic;
        o_sprite_rom_request : out std_logic;
        ou17_sprite_rom_word_address : out unsigned(16 downto 0);
        i_sprite_rom_response_valid : in std_logic;
        iu32_sprite_rom_response_data : in unsigned(31 downto 0);
        o_tile_rom_request : out std_logic;
        ou17_tile_rom_word_address : out unsigned(16 downto 0);
        o_tile_rom_foreground : out std_logic;
        i_tile_rom_response_valid : in std_logic;
        iu32_tile_rom_response_data : in unsigned(31 downto 0);
        i_pixel_valid : in std_logic;
        o_pixel_ready : out std_logic;
        i_pixel_bank : in std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        iu16_pixel_video_flags : in unsigned(15 downto 0);
        o_pixel_valid : out std_logic;
        o_pixel_error : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        i_request : in std_logic;
        i_request_write : in std_logic;
        iu24_request_address : in unsigned(23 downto 0);
        iu16_request_data : in unsigned(15 downto 0);
        iu2_request_bytes : in unsigned(1 downto 0);
        o_request_supported : out std_logic;
        o_response_valid : out std_logic;
        ou16_response_data : out unsigned(15 downto 0);
        o_rom_request : out std_logic;
        ou18_rom_byte_address : out unsigned(17 downto 0);
        i_rom_response_valid : in std_logic;
        iu16_rom_response_data : in unsigned(15 downto 0);
        i_view_enable : in std_logic;
        iu5_view_target : in target_t;
        iu15_view_word_address : in unsigned(14 downto 0);
        o_view_valid : out std_logic;
        ou16_view_data : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_board_video is
    signal s_sprite_request, s_sprite_valid, s_tile_request, s_tile_valid : std_logic;
    signal s_bitmap_read, s_palette_read : std_logic;
    signal su11_sprite_address : unsigned(10 downto 0);
    signal su13_tile_address : unsigned(12 downto 0);
    signal su15_bitmap_address : unsigned(14 downto 0);
    signal su10_palette_address : unsigned(9 downto 0);
    signal su16_sprite_data, su16_tile_data, su16_bitmap_data, su16_palette_data : unsigned(15 downto 0);
begin
    video : entity work.rabbitpunch_rgb_video
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_line_valid => i_line_valid,
            o_line_ready => o_line_ready,
            i_render_bank => i_render_bank,
            iu9_line_y => iu9_line_y,
            iu6_sprite_count => iu6_sprite_count,
            iu6_sprite_priority => iu6_sprite_priority,
            iu9_background_scroll_x => iu9_background_scroll_x,
            iu9_background_scroll_y => iu9_background_scroll_y,
            iu9_foreground_scroll_x => iu9_foreground_scroll_x,
            iu9_foreground_scroll_y => iu9_foreground_scroll_y,
            iu16_video_flags => iu16_video_flags,
            o_line_done => o_line_done,
            o_sprite_ram_request => s_sprite_request,
            ou11_sprite_ram_word_address => su11_sprite_address,
            i_sprite_ram_response_valid => s_sprite_valid,
            iu16_sprite_ram_response_data => su16_sprite_data,
            o_tile_ram_request => s_tile_request,
            ou13_tile_ram_word_address => su13_tile_address,
            i_tile_ram_response_valid => s_tile_valid,
            iu16_tile_ram_response_data => su16_tile_data,
            o_sprite_rom_request => o_sprite_rom_request,
            ou17_sprite_rom_word_address => ou17_sprite_rom_word_address,
            i_sprite_rom_response_valid => i_sprite_rom_response_valid,
            iu32_sprite_rom_response_data => iu32_sprite_rom_response_data,
            o_tile_rom_request => o_tile_rom_request,
            ou17_tile_rom_word_address => ou17_tile_rom_word_address,
            o_tile_rom_foreground => o_tile_rom_foreground,
            i_tile_rom_response_valid => i_tile_rom_response_valid,
            iu32_tile_rom_response_data => iu32_tile_rom_response_data,
            o_bitmap_ram_read_enable => s_bitmap_read,
            ou15_bitmap_ram_word_address => su15_bitmap_address,
            iu16_bitmap_ram_data => su16_bitmap_data,
            i_pixel_valid => i_pixel_valid,
            o_pixel_ready => o_pixel_ready,
            i_pixel_bank => i_pixel_bank,
            iu9_pixel_x => iu9_pixel_x,
            iu8_pixel_y => iu8_pixel_y,
            iu16_pixel_video_flags => iu16_pixel_video_flags,
            o_pixel_valid => o_pixel_valid,
            o_pixel_error => o_pixel_error,
            ou9_pixel_x => ou9_pixel_x,
            ou8_pixel_y => ou8_pixel_y,
            o_palette_ram_read_enable => s_palette_read,
            ou10_palette_ram_word_address => su10_palette_address,
            iu16_palette_ram_data => su16_palette_data,
            ou8_red => ou8_red,
            ou8_green => ou8_green,
            ou8_blue => ou8_blue
        );
    memory : entity work.rabbitpunch_board_memory
        port map (
            i_clk => i_clk,
            i_request => i_request,
            i_request_write => i_request_write,
            iu24_request_address => iu24_request_address,
            iu16_request_data => iu16_request_data,
            iu2_request_bytes => iu2_request_bytes,
            o_request_supported => o_request_supported,
            o_response_valid => o_response_valid,
            ou16_response_data => ou16_response_data,
            o_rom_request => o_rom_request,
            ou18_rom_byte_address => ou18_rom_byte_address,
            i_rom_response_valid => i_rom_response_valid,
            iu16_rom_response_data => iu16_rom_response_data,
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data,
            i_bitmap_read_enable => s_bitmap_read,
            iu15_bitmap_word_address => su15_bitmap_address,
            ou16_bitmap_data => su16_bitmap_data,
            i_palette_read_enable => s_palette_read,
            iu10_palette_word_address => su10_palette_address,
            ou16_palette_data => su16_palette_data,
            i_sprite_request => s_sprite_request,
            iu11_sprite_word_address => su11_sprite_address,
            o_sprite_response_valid => s_sprite_valid,
            ou16_sprite_data => su16_sprite_data,
            i_tile_request => s_tile_request,
            iu13_tile_word_address => su13_tile_address,
            o_tile_response_valid => s_tile_valid,
            ou16_tile_data => su16_tile_data
        );
end architecture;
