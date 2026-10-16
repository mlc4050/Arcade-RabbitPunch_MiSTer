library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical video plus native palette RAM decoding; all stages share i_clk.
entity rabbitpunch_rgb_video is
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
        o_sprite_ram_request : out std_logic;
        ou11_sprite_ram_word_address : out unsigned(10 downto 0);
        i_sprite_ram_response_valid : in std_logic;
        iu16_sprite_ram_response_data : in unsigned(15 downto 0);
        o_tile_ram_request : out std_logic;
        ou13_tile_ram_word_address : out unsigned(12 downto 0);
        i_tile_ram_response_valid : in std_logic;
        iu16_tile_ram_response_data : in unsigned(15 downto 0);
        o_sprite_rom_request : out std_logic;
        ou17_sprite_rom_word_address : out unsigned(16 downto 0);
        i_sprite_rom_response_valid : in std_logic;
        iu32_sprite_rom_response_data : in unsigned(31 downto 0);
        o_tile_rom_request : out std_logic;
        ou17_tile_rom_word_address : out unsigned(16 downto 0);
        o_tile_rom_foreground : out std_logic;
        i_tile_rom_response_valid : in std_logic;
        iu32_tile_rom_response_data : in unsigned(31 downto 0);
        o_bitmap_ram_read_enable : out std_logic;
        ou15_bitmap_ram_word_address : out unsigned(14 downto 0);
        iu16_bitmap_ram_data : in unsigned(15 downto 0);
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
        o_palette_ram_read_enable : out std_logic;
        ou10_palette_ram_word_address : out unsigned(9 downto 0);
        iu16_palette_ram_data : in unsigned(15 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_rgb_video is
    signal s_index_valid, s_index_error : std_logic;
    signal su9_index_x, su9_rgb_x : unsigned(8 downto 0);
    signal su8_index_y, su8_rgb_y : unsigned(7 downto 0);
    signal su10_index : unsigned(9 downto 0);
    signal su2_error : unsigned(1 downto 0) := "00";
    signal su9_error_x_first, su9_error_x_last : unsigned(8 downto 0);
    signal su8_error_y_first, su8_error_y_last : unsigned(7 downto 0);
begin
    o_pixel_error <= su2_error(1);
    ou9_pixel_x <= su9_error_x_last when su2_error(1) = '1' else su9_rgb_x;
    ou8_pixel_y <= su8_error_y_last when su2_error(1) = '1' else su8_rgb_y;
    video : entity work.rabbitpunch_video
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
            o_sprite_ram_request => o_sprite_ram_request,
            ou11_sprite_ram_word_address => ou11_sprite_ram_word_address,
            i_sprite_ram_response_valid => i_sprite_ram_response_valid,
            iu16_sprite_ram_response_data => iu16_sprite_ram_response_data,
            o_tile_ram_request => o_tile_ram_request,
            ou13_tile_ram_word_address => ou13_tile_ram_word_address,
            i_tile_ram_response_valid => i_tile_ram_response_valid,
            iu16_tile_ram_response_data => iu16_tile_ram_response_data,
            o_sprite_rom_request => o_sprite_rom_request,
            ou17_sprite_rom_word_address => ou17_sprite_rom_word_address,
            i_sprite_rom_response_valid => i_sprite_rom_response_valid,
            iu32_sprite_rom_response_data => iu32_sprite_rom_response_data,
            o_tile_rom_request => o_tile_rom_request,
            ou17_tile_rom_word_address => ou17_tile_rom_word_address,
            o_tile_rom_foreground => o_tile_rom_foreground,
            i_tile_rom_response_valid => i_tile_rom_response_valid,
            iu32_tile_rom_response_data => iu32_tile_rom_response_data,
            o_bitmap_ram_read_enable => o_bitmap_ram_read_enable,
            ou15_bitmap_ram_word_address => ou15_bitmap_ram_word_address,
            iu16_bitmap_ram_data => iu16_bitmap_ram_data,
            i_pixel_valid => i_pixel_valid,
            o_pixel_ready => o_pixel_ready,
            i_pixel_bank => i_pixel_bank,
            iu9_pixel_x => iu9_pixel_x,
            iu8_pixel_y => iu8_pixel_y,
            iu16_pixel_video_flags => iu16_pixel_video_flags,
            o_pixel_valid => s_index_valid,
            o_pixel_error => s_index_error,
            ou9_pixel_x => su9_index_x,
            ou8_pixel_y => su8_index_y,
            ou10_palette_index => su10_index
        );
    palette : entity work.rabbitpunch_palette_pixel
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_pixel_valid => s_index_valid,
            iu9_pixel_x => su9_index_x,
            iu8_pixel_y => su8_index_y,
            iu10_palette_index => su10_index,
            o_ram_read_enable => o_palette_ram_read_enable,
            ou10_ram_word_address => ou10_palette_ram_word_address,
            iu16_ram_data => iu16_palette_ram_data,
            o_pixel_valid => o_pixel_valid,
            ou9_pixel_x => su9_rgb_x,
            ou8_pixel_y => su8_rgb_y,
            ou8_red => ou8_red,
            ou8_green => ou8_green,
            ou8_blue => ou8_blue
        );
    -- Invalid line tags occupy the same pipeline slot as a valid RGB pixel.
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            su2_error <= su2_error(0) & s_index_error;
            su9_error_x_first <= su9_index_x;
            su9_error_x_last <= su9_error_x_first;
            su8_error_y_first <= su8_index_y;
            su8_error_y_last <= su8_error_y_first;
            if (i_reset = '1') then
                su2_error <= "00";
            end if;
        end if;
    end process;
end architecture;
