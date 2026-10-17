library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical-line video pipeline. External arbiters provide descriptor/bitmap RAM
-- and graphics ROM responses. No physical raster, PLL or frame buffer is here.
entity rabbitpunch_video is
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
        ou10_palette_index : out unsigned(9 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_video is
    type t_line_state is (STATE_LINE_IDLE, STATE_LINE_DRAW);
    signal styp_line : t_line_state := STATE_LINE_IDLE;
    signal s_line_ready, s_start_line : std_logic := '0';
    signal s_sprite_ready, s_tile_ready, s_sprite_done, s_tile_done : std_logic;
    signal su2_line_finished : unsigned(1 downto 0) := "00";
    signal s_render_bank : std_logic;
    signal su9_line_y : unsigned(8 downto 0);
    signal su6_sprite_count, su6_sprite_priority : unsigned(5 downto 0);
    signal su9_background_x, su9_background_y, su9_foreground_x, su9_foreground_y : unsigned(8 downto 0);
    signal su16_flags : unsigned(15 downto 0);
    signal s_sprite_view_ready, s_sprite_view_valid, s_tile_view_ready, s_tile_view_valid : std_logic;
    signal su9_sprite_view_y, su9_tile_view_y : unsigned(8 downto 0);
    signal su16_sprite_view_entry, su16_tile_view_pixels : unsigned(15 downto 0);
    signal s_pixel_ready, s_pixel_accept, s_bitmap_valid : std_logic;
    signal su9_bitmap_x, su9_sprite_pixel_y, su9_tile_pixel_y : unsigned(8 downto 0);
    signal su8_bitmap_y : unsigned(7 downto 0);
    signal su10_bitmap_index, su10_mixed_index : unsigned(9 downto 0);
    signal su16_sprite_pixel, su16_tile_pixels : unsigned(15 downto 0) := (others => '0');
    signal su8_bitmap_pixel : unsigned(7 downto 0) := x"0F";
    signal s_sprite_pixel_valid, s_tile_pixel_valid : std_logic := '0';
begin
    s_line_ready <= '1' when styp_line = STATE_LINE_IDLE and s_sprite_ready = '1' and
        s_tile_ready = '1' and i_reset = '0' else '0';
    o_line_ready <= s_line_ready;
    s_pixel_ready <= s_sprite_view_ready and s_tile_view_ready and not i_reset;
    o_pixel_ready <= s_pixel_ready;
    s_pixel_accept <= i_pixel_valid and s_pixel_ready;
    su8_bitmap_pixel <= su10_bitmap_index(7 downto 0) when s_bitmap_valid = '1' else x"0F";

    sprites : entity work.rabbitpunch_sprites
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_line_valid => s_start_line,
            o_line_ready => s_sprite_ready,
            i_render_bank => s_render_bank,
            iu9_line_y => su9_line_y,
            iu6_sprite_count => su6_sprite_count,
            iu6_sprite_priority => su6_sprite_priority,
            iu16_video_flags => su16_flags,
            o_line_done => s_sprite_done,
            o_ram_request => o_sprite_ram_request,
            ou11_ram_word_address => ou11_sprite_ram_word_address,
            i_ram_response_valid => i_sprite_ram_response_valid,
            iu16_ram_response_data => iu16_sprite_ram_response_data,
            o_rom_request => o_sprite_rom_request,
            ou17_rom_word_address => ou17_sprite_rom_word_address,
            i_rom_response_valid => i_sprite_rom_response_valid,
            iu32_rom_response_data => iu32_sprite_rom_response_data,
            i_view_enable => s_pixel_accept,
            o_view_ready => s_sprite_view_ready,
            i_view_bank => i_pixel_bank,
            iu9_view_x => iu9_pixel_x,
            o_view_valid => s_sprite_view_valid,
            ou9_view_line_y => su9_sprite_view_y,
            ou16_view_entry => su16_sprite_view_entry
        );
    tiles : entity work.rabbitpunch_tiles
        generic map (
            GINT_FIRST_PIXEL => 8,
            GINT_LAST_PIXEL => 295
        )
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_line_valid => s_start_line,
            o_line_ready => s_tile_ready,
            i_render_bank => s_render_bank,
            iu9_line_y => su9_line_y,
            iu9_background_scroll_x => su9_background_x,
            iu9_background_scroll_y => su9_background_y,
            iu9_foreground_scroll_x => su9_foreground_x,
            iu9_foreground_scroll_y => su9_foreground_y,
            iu16_video_flags => su16_flags,
            o_line_done => s_tile_done,
            o_ram_request => o_tile_ram_request,
            ou13_ram_word_address => ou13_tile_ram_word_address,
            i_ram_response_valid => i_tile_ram_response_valid,
            iu16_ram_response_data => iu16_tile_ram_response_data,
            o_rom_request => o_tile_rom_request,
            ou17_rom_word_address => ou17_tile_rom_word_address,
            o_rom_foreground => o_tile_rom_foreground,
            i_rom_response_valid => i_tile_rom_response_valid,
            iu32_rom_response_data => iu32_tile_rom_response_data,
            i_view_enable => s_pixel_accept,
            o_view_ready => s_tile_view_ready,
            i_view_bank => i_pixel_bank,
            iu9_view_x => iu9_pixel_x,
            o_view_valid => s_tile_view_valid,
            ou9_view_line_y => su9_tile_view_y,
            ou16_view_pixels => su16_tile_view_pixels
        );
    bitmap : entity work.rabbitpunch_bitmap_pixel
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_pixel_valid => s_pixel_accept,
            iu9_pixel_x => iu9_pixel_x,
            iu8_pixel_y => iu8_pixel_y,
            iu16_video_flags => iu16_pixel_video_flags,
            o_ram_read_enable => o_bitmap_ram_read_enable,
            ou15_ram_word_address => ou15_bitmap_ram_word_address,
            iu16_ram_data => iu16_bitmap_ram_data,
            o_pixel_valid => s_bitmap_valid,
            ou9_pixel_x => su9_bitmap_x,
            ou8_pixel_y => su8_bitmap_y,
            ou10_palette_index => su10_bitmap_index
        );
    mixer : entity work.rabbitpunch_pixel_mixer
        port map (
            iu8_background => su16_tile_pixels(7 downto 0),
            iu8_foreground => su16_tile_pixels(15 downto 8),
            iu8_sprite => su16_sprite_pixel(7 downto 0),
            i_sprite_occupied => su16_sprite_pixel(15),
            i_sprite_behind_foreground => su16_sprite_pixel(14),
            iu8_bitmap => su8_bitmap_pixel,
            ou10_palette_index => su10_mixed_index
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_start_line <= '0';
            o_line_done <= '0';
            o_pixel_valid <= '0';
            o_pixel_error <= '0';
            s_sprite_pixel_valid <= s_sprite_view_valid;
            s_tile_pixel_valid <= s_tile_view_valid;
            if (s_sprite_view_valid = '1') then
                su16_sprite_pixel <= su16_sprite_view_entry;
                su9_sprite_pixel_y <= su9_sprite_view_y;
            end if;
            if (s_tile_view_valid = '1') then
                su16_tile_pixels <= su16_tile_view_pixels;
                su9_tile_pixel_y <= su9_tile_view_y;
            end if;
            if (i_reset = '1') then
                styp_line <= STATE_LINE_IDLE;
                su2_line_finished <= "00";
                s_sprite_pixel_valid <= '0';
                s_tile_pixel_valid <= '0';
            else
                case styp_line is
                    when STATE_LINE_IDLE =>
                        if (i_line_valid = '1' and s_line_ready = '1') then
                            s_render_bank <= i_render_bank;
                            su9_line_y <= iu9_line_y;
                            su6_sprite_count <= iu6_sprite_count;
                            su6_sprite_priority <= iu6_sprite_priority;
                            su9_background_x <= iu9_background_scroll_x;
                            su9_background_y <= iu9_background_scroll_y;
                            su9_foreground_x <= iu9_foreground_scroll_x;
                            su9_foreground_y <= iu9_foreground_scroll_y;
                            su16_flags <= iu16_video_flags;
                            su2_line_finished <= "00";
                            s_start_line <= '1';
                            styp_line <= STATE_LINE_DRAW;
                        end if;
                    when STATE_LINE_DRAW =>
                        if (s_sprite_done = '1') then
                            su2_line_finished(0) <= '1';
                        end if;
                        if (s_tile_done = '1') then
                            su2_line_finished(1) <= '1';
                        end if;
                        if (su2_line_finished = "11") then
                            o_line_done <= '1';
                            styp_line <= STATE_LINE_IDLE;
                        end if;
                end case;
                if (s_bitmap_valid = '1') then
                    ou9_pixel_x <= su9_bitmap_x;
                    ou8_pixel_y <= su8_bitmap_y;
                    ou10_palette_index <= su10_mixed_index;
                    if (s_sprite_pixel_valid = '1' and s_tile_pixel_valid = '1' and
                        su9_sprite_pixel_y = ('0' & su8_bitmap_y) and su9_tile_pixel_y = ('0' & su8_bitmap_y)) then
                        o_pixel_valid <= '1';
                    else
                        o_pixel_error <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
