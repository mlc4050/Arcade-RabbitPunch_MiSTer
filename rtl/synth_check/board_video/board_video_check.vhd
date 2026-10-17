library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity board_video_check is
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

-- Evaluation-only launch/capture registers. No board RTL or game latency changes.
-- Each DUT input and output is connected to a same-clock boundary register.
architecture evaluation of board_video_check is
    signal s_boundary_i_reset : std_logic := '0';
    signal s_boundary_i_line_valid : std_logic := '0';
    signal s_boundary_o_line_ready : std_logic := '0';
    signal s_boundary_i_render_bank : std_logic := '0';
    signal su9_boundary_iu9_line_y : unsigned(8 downto 0) := (others => '0');
    signal su6_boundary_iu6_sprite_count : unsigned(5 downto 0) := (others => '0');
    signal su6_boundary_iu6_sprite_priority : unsigned(5 downto 0) := (others => '0');
    signal su9_boundary_iu9_background_scroll_x : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_iu9_background_scroll_y : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_iu9_foreground_scroll_x : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_iu9_foreground_scroll_y : unsigned(8 downto 0) := (others => '0');
    signal su16_boundary_iu16_video_flags : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_o_line_done : std_logic := '0';
    signal s_boundary_o_sprite_rom_request : std_logic := '0';
    signal su17_boundary_ou17_sprite_rom_word_address : unsigned(16 downto 0) := (others => '0');
    signal s_boundary_i_sprite_rom_response_valid : std_logic := '0';
    signal su32_boundary_iu32_sprite_rom_response_data : unsigned(31 downto 0) := (others => '0');
    signal s_boundary_o_tile_rom_request : std_logic := '0';
    signal su17_boundary_ou17_tile_rom_word_address : unsigned(16 downto 0) := (others => '0');
    signal s_boundary_o_tile_rom_foreground : std_logic := '0';
    signal s_boundary_i_tile_rom_response_valid : std_logic := '0';
    signal su32_boundary_iu32_tile_rom_response_data : unsigned(31 downto 0) := (others => '0');
    signal s_boundary_i_pixel_valid : std_logic := '0';
    signal s_boundary_o_pixel_ready : std_logic := '0';
    signal s_boundary_i_pixel_bank : std_logic := '0';
    signal su9_boundary_iu9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su8_boundary_iu8_pixel_y : unsigned(7 downto 0) := (others => '0');
    signal su16_boundary_iu16_pixel_video_flags : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_o_pixel_valid : std_logic := '0';
    signal s_boundary_o_pixel_error : std_logic := '0';
    signal su9_boundary_ou9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su8_boundary_ou8_pixel_y : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_red : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_green : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_blue : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_i_request : std_logic := '0';
    signal s_boundary_i_request_write : std_logic := '0';
    signal su24_boundary_iu24_request_address : unsigned(23 downto 0) := (others => '0');
    signal su16_boundary_iu16_request_data : unsigned(15 downto 0) := (others => '0');
    signal su2_boundary_iu2_request_bytes : unsigned(1 downto 0) := (others => '0');
    signal s_boundary_o_request_supported : std_logic := '0';
    signal s_boundary_o_response_valid : std_logic := '0';
    signal su16_boundary_ou16_response_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_o_rom_request : std_logic := '0';
    signal su18_boundary_ou18_rom_byte_address : unsigned(17 downto 0) := (others => '0');
    signal s_boundary_i_rom_response_valid : std_logic := '0';
    signal su16_boundary_iu16_rom_response_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_view_enable : std_logic := '0';
    signal su5_boundary_iu5_view_target : target_t := (others => '0');
    signal su15_boundary_iu15_view_word_address : unsigned(14 downto 0) := (others => '0');
    signal s_boundary_o_view_valid : std_logic := '0';
    signal su16_boundary_ou16_view_data : unsigned(15 downto 0) := (others => '0');
begin
    board : entity work.rabbitpunch_board_video
        port map (
            i_clk => i_clk,
            i_reset => s_boundary_i_reset,
            i_line_valid => s_boundary_i_line_valid,
            o_line_ready => s_boundary_o_line_ready,
            i_render_bank => s_boundary_i_render_bank,
            iu9_line_y => su9_boundary_iu9_line_y,
            iu6_sprite_count => su6_boundary_iu6_sprite_count,
            iu6_sprite_priority => su6_boundary_iu6_sprite_priority,
            iu9_background_scroll_x => su9_boundary_iu9_background_scroll_x,
            iu9_background_scroll_y => su9_boundary_iu9_background_scroll_y,
            iu9_foreground_scroll_x => su9_boundary_iu9_foreground_scroll_x,
            iu9_foreground_scroll_y => su9_boundary_iu9_foreground_scroll_y,
            iu16_video_flags => su16_boundary_iu16_video_flags,
            o_line_done => s_boundary_o_line_done,
            o_sprite_rom_request => s_boundary_o_sprite_rom_request,
            ou17_sprite_rom_word_address => su17_boundary_ou17_sprite_rom_word_address,
            i_sprite_rom_response_valid => s_boundary_i_sprite_rom_response_valid,
            iu32_sprite_rom_response_data => su32_boundary_iu32_sprite_rom_response_data,
            o_tile_rom_request => s_boundary_o_tile_rom_request,
            ou17_tile_rom_word_address => su17_boundary_ou17_tile_rom_word_address,
            o_tile_rom_foreground => s_boundary_o_tile_rom_foreground,
            i_tile_rom_response_valid => s_boundary_i_tile_rom_response_valid,
            iu32_tile_rom_response_data => su32_boundary_iu32_tile_rom_response_data,
            i_pixel_valid => s_boundary_i_pixel_valid,
            o_pixel_ready => s_boundary_o_pixel_ready,
            i_pixel_bank => s_boundary_i_pixel_bank,
            iu9_pixel_x => su9_boundary_iu9_pixel_x,
            iu8_pixel_y => su8_boundary_iu8_pixel_y,
            iu16_pixel_video_flags => su16_boundary_iu16_pixel_video_flags,
            o_pixel_valid => s_boundary_o_pixel_valid,
            o_pixel_error => s_boundary_o_pixel_error,
            ou9_pixel_x => su9_boundary_ou9_pixel_x,
            ou8_pixel_y => su8_boundary_ou8_pixel_y,
            ou8_red => su8_boundary_ou8_red,
            ou8_green => su8_boundary_ou8_green,
            ou8_blue => su8_boundary_ou8_blue,
            i_request => s_boundary_i_request,
            i_request_write => s_boundary_i_request_write,
            iu24_request_address => su24_boundary_iu24_request_address,
            iu16_request_data => su16_boundary_iu16_request_data,
            iu2_request_bytes => su2_boundary_iu2_request_bytes,
            o_request_supported => s_boundary_o_request_supported,
            o_response_valid => s_boundary_o_response_valid,
            ou16_response_data => su16_boundary_ou16_response_data,
            o_rom_request => s_boundary_o_rom_request,
            ou18_rom_byte_address => su18_boundary_ou18_rom_byte_address,
            i_rom_response_valid => s_boundary_i_rom_response_valid,
            iu16_rom_response_data => su16_boundary_iu16_rom_response_data,
            i_view_enable => s_boundary_i_view_enable,
            iu5_view_target => su5_boundary_iu5_view_target,
            iu15_view_word_address => su15_boundary_iu15_view_word_address,
            o_view_valid => s_boundary_o_view_valid,
            ou16_view_data => su16_boundary_ou16_view_data
        );

    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_reset <= i_reset;
            s_boundary_i_line_valid <= i_line_valid;
            o_line_ready <= s_boundary_o_line_ready;
            s_boundary_i_render_bank <= i_render_bank;
            su9_boundary_iu9_line_y <= iu9_line_y;
            su6_boundary_iu6_sprite_count <= iu6_sprite_count;
            su6_boundary_iu6_sprite_priority <= iu6_sprite_priority;
            su9_boundary_iu9_background_scroll_x <= iu9_background_scroll_x;
            su9_boundary_iu9_background_scroll_y <= iu9_background_scroll_y;
            su9_boundary_iu9_foreground_scroll_x <= iu9_foreground_scroll_x;
            su9_boundary_iu9_foreground_scroll_y <= iu9_foreground_scroll_y;
            su16_boundary_iu16_video_flags <= iu16_video_flags;
            o_line_done <= s_boundary_o_line_done;
            o_sprite_rom_request <= s_boundary_o_sprite_rom_request;
            ou17_sprite_rom_word_address <= su17_boundary_ou17_sprite_rom_word_address;
            s_boundary_i_sprite_rom_response_valid <= i_sprite_rom_response_valid;
            su32_boundary_iu32_sprite_rom_response_data <= iu32_sprite_rom_response_data;
            o_tile_rom_request <= s_boundary_o_tile_rom_request;
            ou17_tile_rom_word_address <= su17_boundary_ou17_tile_rom_word_address;
            o_tile_rom_foreground <= s_boundary_o_tile_rom_foreground;
            s_boundary_i_tile_rom_response_valid <= i_tile_rom_response_valid;
            su32_boundary_iu32_tile_rom_response_data <= iu32_tile_rom_response_data;
            s_boundary_i_pixel_valid <= i_pixel_valid;
            o_pixel_ready <= s_boundary_o_pixel_ready;
            s_boundary_i_pixel_bank <= i_pixel_bank;
            su9_boundary_iu9_pixel_x <= iu9_pixel_x;
            su8_boundary_iu8_pixel_y <= iu8_pixel_y;
            su16_boundary_iu16_pixel_video_flags <= iu16_pixel_video_flags;
            o_pixel_valid <= s_boundary_o_pixel_valid;
            o_pixel_error <= s_boundary_o_pixel_error;
            ou9_pixel_x <= su9_boundary_ou9_pixel_x;
            ou8_pixel_y <= su8_boundary_ou8_pixel_y;
            ou8_red <= su8_boundary_ou8_red;
            ou8_green <= su8_boundary_ou8_green;
            ou8_blue <= su8_boundary_ou8_blue;
            s_boundary_i_request <= i_request;
            s_boundary_i_request_write <= i_request_write;
            su24_boundary_iu24_request_address <= iu24_request_address;
            su16_boundary_iu16_request_data <= iu16_request_data;
            su2_boundary_iu2_request_bytes <= iu2_request_bytes;
            o_request_supported <= s_boundary_o_request_supported;
            o_response_valid <= s_boundary_o_response_valid;
            ou16_response_data <= su16_boundary_ou16_response_data;
            o_rom_request <= s_boundary_o_rom_request;
            ou18_rom_byte_address <= su18_boundary_ou18_rom_byte_address;
            s_boundary_i_rom_response_valid <= i_rom_response_valid;
            su16_boundary_iu16_rom_response_data <= iu16_rom_response_data;
            s_boundary_i_view_enable <= i_view_enable;
            su5_boundary_iu5_view_target <= iu5_view_target;
            su15_boundary_iu15_view_word_address <= iu15_view_word_address;
            o_view_valid <= s_boundary_o_view_valid;
            ou16_view_data <= su16_boundary_ou16_view_data;
        end if;
    end process;
end architecture;
