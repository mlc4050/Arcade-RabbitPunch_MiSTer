library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity board_check is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_reset : in std_logic;
        i_pause : in std_logic;
        o_paused : out std_logic;
        i_vblank_start : in std_logic;
        i_half_frame : in std_logic;
        i_line_valid : in std_logic;
        o_line_ready : out std_logic;
        i_render_bank : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
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
        o_pixel_valid : out std_logic;
        o_pixel_error : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou8_red : out unsigned(7 downto 0);
        ou8_green : out unsigned(7 downto 0);
        ou8_blue : out unsigned(7 downto 0);
        o_rom_request : out std_logic;
        ou18_rom_byte_address : out unsigned(17 downto 0);
        i_rom_response_valid : in std_logic;
        iu16_rom_response_data : in unsigned(15 downto 0);
        i_view_enable : in std_logic;
        iu5_view_target : in target_t;
        iu15_view_word_address : in unsigned(14 downto 0);
        o_view_valid : out std_logic;
        ou16_view_data : out unsigned(15 downto 0);
        iu8_player1 : in unsigned(7 downto 0);
        iu8_player2 : in unsigned(7 downto 0);
        iu8_service : in unsigned(7 downto 0);
        iu16_dips : in unsigned(15 downto 0);
        i_sound_command_read : in std_logic;
        o_sound_command_write : out std_logic;
        ou8_sound_command : out unsigned(7 downto 0);
        o_sound_pending : out std_logic;
        ou16_video_flags : out unsigned(15 downto 0);
        ou9_scroll0_y : out unsigned(8 downto 0);
        ou9_scroll0_x : out unsigned(8 downto 0);
        ou9_scroll1_y : out unsigned(8 downto 0);
        ou9_scroll1_x : out unsigned(8 downto 0);
        ou6_sprite_count : out unsigned(5 downto 0);
        ou6_sprite_priority : out unsigned(5 downto 0);
        ou4_gga_selected : out unsigned(3 downto 0);
        iu4_gga_view_address : in unsigned(3 downto 0);
        ou8_gga_view_data : out unsigned(7 downto 0);
        o_gga_write : out std_logic;
        ou4_gga_write_address : out unsigned(3 downto 0);
        ou8_gga_write_data : out unsigned(7 downto 0);
        o_cpu_request : out std_logic;
        o_cpu_request_write : out std_logic;
        ou24_cpu_request_address : out unsigned(23 downto 0);
        ou16_cpu_request_data : out unsigned(15 downto 0);
        ou2_cpu_request_bytes : out unsigned(1 downto 0)
    );
end entity;

-- Evaluation-only launch/capture registers around the logical board interfaces.
architecture evaluation of board_check is
    signal s_boundary_i_initialize : std_logic := '0';
    signal s_boundary_i_reset : std_logic := '0';
    signal s_boundary_i_pause : std_logic := '0';
    signal s_boundary_o_paused : std_logic := '0';
    signal s_boundary_i_vblank_start : std_logic := '0';
    signal s_boundary_i_half_frame : std_logic := '0';
    signal s_boundary_i_line_valid : std_logic := '0';
    signal s_boundary_o_line_ready : std_logic := '0';
    signal s_boundary_i_render_bank : std_logic := '0';
    signal su9_boundary_iu9_line_y : unsigned(8 downto 0) := (others => '0');
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
    signal s_boundary_o_pixel_valid : std_logic := '0';
    signal s_boundary_o_pixel_error : std_logic := '0';
    signal su9_boundary_ou9_pixel_x : unsigned(8 downto 0) := (others => '0');
    signal su8_boundary_ou8_pixel_y : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_red : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_green : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_ou8_blue : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_rom_request : std_logic := '0';
    signal su18_boundary_ou18_rom_byte_address : unsigned(17 downto 0) := (others => '0');
    signal s_boundary_i_rom_response_valid : std_logic := '0';
    signal su16_boundary_iu16_rom_response_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_view_enable : std_logic := '0';
    signal su5_boundary_iu5_view_target : target_t := (others => '0');
    signal su15_boundary_iu15_view_word_address : unsigned(14 downto 0) := (others => '0');
    signal s_boundary_o_view_valid : std_logic := '0';
    signal su16_boundary_ou16_view_data : unsigned(15 downto 0) := (others => '0');
    signal su8_boundary_iu8_player1 : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_iu8_player2 : unsigned(7 downto 0) := (others => '0');
    signal su8_boundary_iu8_service : unsigned(7 downto 0) := (others => '0');
    signal su16_boundary_iu16_dips : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_sound_command_read : std_logic := '0';
    signal s_boundary_o_sound_command_write : std_logic := '0';
    signal su8_boundary_ou8_sound_command : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_sound_pending : std_logic := '0';
    signal su16_boundary_ou16_video_flags : unsigned(15 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll0_y : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll0_x : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll1_y : unsigned(8 downto 0) := (others => '0');
    signal su9_boundary_ou9_scroll1_x : unsigned(8 downto 0) := (others => '0');
    signal su6_boundary_ou6_sprite_count : unsigned(5 downto 0) := (others => '0');
    signal su6_boundary_ou6_sprite_priority : unsigned(5 downto 0) := (others => '0');
    signal su4_boundary_ou4_gga_selected : unsigned(3 downto 0) := (others => '0');
    signal su4_boundary_iu4_gga_view_address : unsigned(3 downto 0) := (others => '0');
    signal su8_boundary_ou8_gga_view_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_gga_write : std_logic := '0';
    signal su4_boundary_ou4_gga_write_address : unsigned(3 downto 0) := (others => '0');
    signal su8_boundary_ou8_gga_write_data : unsigned(7 downto 0) := (others => '0');
    signal s_boundary_o_cpu_request : std_logic := '0';
    signal s_boundary_o_cpu_request_write : std_logic := '0';
    signal su24_boundary_ou24_cpu_request_address : unsigned(23 downto 0) := (others => '0');
    signal su16_boundary_ou16_cpu_request_data : unsigned(15 downto 0) := (others => '0');
    signal su2_boundary_ou2_cpu_request_bytes : unsigned(1 downto 0) := (others => '0');
begin
    boundary : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_initialize <= i_initialize;
            s_boundary_i_reset <= i_reset;
            s_boundary_i_pause <= i_pause;
            o_paused <= s_boundary_o_paused;
            s_boundary_i_vblank_start <= i_vblank_start;
            s_boundary_i_half_frame <= i_half_frame;
            s_boundary_i_line_valid <= i_line_valid;
            o_line_ready <= s_boundary_o_line_ready;
            s_boundary_i_render_bank <= i_render_bank;
            su9_boundary_iu9_line_y <= iu9_line_y;
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
            o_pixel_valid <= s_boundary_o_pixel_valid;
            o_pixel_error <= s_boundary_o_pixel_error;
            ou9_pixel_x <= su9_boundary_ou9_pixel_x;
            ou8_pixel_y <= su8_boundary_ou8_pixel_y;
            ou8_red <= su8_boundary_ou8_red;
            ou8_green <= su8_boundary_ou8_green;
            ou8_blue <= su8_boundary_ou8_blue;
            o_rom_request <= s_boundary_o_rom_request;
            ou18_rom_byte_address <= su18_boundary_ou18_rom_byte_address;
            s_boundary_i_rom_response_valid <= i_rom_response_valid;
            su16_boundary_iu16_rom_response_data <= iu16_rom_response_data;
            s_boundary_i_view_enable <= i_view_enable;
            su5_boundary_iu5_view_target <= iu5_view_target;
            su15_boundary_iu15_view_word_address <= iu15_view_word_address;
            o_view_valid <= s_boundary_o_view_valid;
            ou16_view_data <= su16_boundary_ou16_view_data;
            su8_boundary_iu8_player1 <= iu8_player1;
            su8_boundary_iu8_player2 <= iu8_player2;
            su8_boundary_iu8_service <= iu8_service;
            su16_boundary_iu16_dips <= iu16_dips;
            s_boundary_i_sound_command_read <= i_sound_command_read;
            o_sound_command_write <= s_boundary_o_sound_command_write;
            ou8_sound_command <= su8_boundary_ou8_sound_command;
            o_sound_pending <= s_boundary_o_sound_pending;
            ou16_video_flags <= su16_boundary_ou16_video_flags;
            ou9_scroll0_y <= su9_boundary_ou9_scroll0_y;
            ou9_scroll0_x <= su9_boundary_ou9_scroll0_x;
            ou9_scroll1_y <= su9_boundary_ou9_scroll1_y;
            ou9_scroll1_x <= su9_boundary_ou9_scroll1_x;
            ou6_sprite_count <= su6_boundary_ou6_sprite_count;
            ou6_sprite_priority <= su6_boundary_ou6_sprite_priority;
            ou4_gga_selected <= su4_boundary_ou4_gga_selected;
            su4_boundary_iu4_gga_view_address <= iu4_gga_view_address;
            ou8_gga_view_data <= su8_boundary_ou8_gga_view_data;
            o_gga_write <= s_boundary_o_gga_write;
            ou4_gga_write_address <= su4_boundary_ou4_gga_write_address;
            ou8_gga_write_data <= su8_boundary_ou8_gga_write_data;
            o_cpu_request <= s_boundary_o_cpu_request;
            o_cpu_request_write <= s_boundary_o_cpu_request_write;
            ou24_cpu_request_address <= su24_boundary_ou24_cpu_request_address;
            ou16_cpu_request_data <= su16_boundary_ou16_cpu_request_data;
            ou2_cpu_request_bytes <= su2_boundary_ou2_cpu_request_bytes;
        end if;
    end process;
    board : entity work.rabbitpunch_board
        port map (
            i_clk => i_clk,
            i_initialize => s_boundary_i_initialize,
            i_reset => s_boundary_i_reset,
            i_pause => s_boundary_i_pause,
            o_paused => s_boundary_o_paused,
            i_vblank_start => s_boundary_i_vblank_start,
            i_half_frame => s_boundary_i_half_frame,
            i_line_valid => s_boundary_i_line_valid,
            o_line_ready => s_boundary_o_line_ready,
            i_render_bank => s_boundary_i_render_bank,
            iu9_line_y => su9_boundary_iu9_line_y,
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
            o_pixel_valid => s_boundary_o_pixel_valid,
            o_pixel_error => s_boundary_o_pixel_error,
            ou9_pixel_x => su9_boundary_ou9_pixel_x,
            ou8_pixel_y => su8_boundary_ou8_pixel_y,
            ou8_red => su8_boundary_ou8_red,
            ou8_green => su8_boundary_ou8_green,
            ou8_blue => su8_boundary_ou8_blue,
            o_rom_request => s_boundary_o_rom_request,
            ou18_rom_byte_address => su18_boundary_ou18_rom_byte_address,
            i_rom_response_valid => s_boundary_i_rom_response_valid,
            iu16_rom_response_data => su16_boundary_iu16_rom_response_data,
            i_view_enable => s_boundary_i_view_enable,
            iu5_view_target => su5_boundary_iu5_view_target,
            iu15_view_word_address => su15_boundary_iu15_view_word_address,
            o_view_valid => s_boundary_o_view_valid,
            ou16_view_data => su16_boundary_ou16_view_data,
            iu8_player1 => su8_boundary_iu8_player1,
            iu8_player2 => su8_boundary_iu8_player2,
            iu8_service => su8_boundary_iu8_service,
            iu16_dips => su16_boundary_iu16_dips,
            i_sound_command_read => s_boundary_i_sound_command_read,
            o_sound_command_write => s_boundary_o_sound_command_write,
            ou8_sound_command => su8_boundary_ou8_sound_command,
            o_sound_pending => s_boundary_o_sound_pending,
            ou16_video_flags => su16_boundary_ou16_video_flags,
            ou9_scroll0_y => su9_boundary_ou9_scroll0_y,
            ou9_scroll0_x => su9_boundary_ou9_scroll0_x,
            ou9_scroll1_y => su9_boundary_ou9_scroll1_y,
            ou9_scroll1_x => su9_boundary_ou9_scroll1_x,
            ou6_sprite_count => su6_boundary_ou6_sprite_count,
            ou6_sprite_priority => su6_boundary_ou6_sprite_priority,
            ou4_gga_selected => su4_boundary_ou4_gga_selected,
            iu4_gga_view_address => su4_boundary_iu4_gga_view_address,
            ou8_gga_view_data => su8_boundary_ou8_gga_view_data,
            o_gga_write => s_boundary_o_gga_write,
            ou4_gga_write_address => su4_boundary_ou4_gga_write_address,
            ou8_gga_write_data => su8_boundary_ou8_gga_write_data,
            o_cpu_request => s_boundary_o_cpu_request,
            o_cpu_request_write => s_boundary_o_cpu_request_write,
            ou24_cpu_request_address => su24_boundary_ou24_cpu_request_address,
            ou16_cpu_request_data => su16_boundary_ou16_cpu_request_data,
            ou2_cpu_request_bytes => su2_boundary_ou2_cpu_request_bytes
        );
end architecture;
