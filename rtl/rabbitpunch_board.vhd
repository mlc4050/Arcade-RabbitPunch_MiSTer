library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- Main CPU, board I/O and logical-line video share the native RAM banks.
-- The caller supplies raster events/line scheduling and an independently drained
-- ROM transport. Cold I/O initialization is separate from CPU/video reset.
entity rabbitpunch_board is
    generic (
        GINT_PHASE_DIVIDER : positive := 3;
        GBOOL_EXTERNAL_PHASE_ENABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_main_phase_enable : in std_logic := '0';
        i_initialize : in std_logic;
        i_reset : in std_logic;
        i_pause : in std_logic;
        o_paused : out std_logic;
        i_maintenance_initialize : in std_logic := '0';
        i_maintenance_access : in std_logic := '0';
        i_maintenance_valid : in std_logic := '0';
        i_maintenance_write : in std_logic := '0';
        iu14_maintenance_byte_address : in unsigned(13 downto 0) := (others => '0');
        iu8_maintenance_data : in unsigned(7 downto 0) := (others => '0');
        o_maintenance_ready : out std_logic;
        o_maintenance_response_valid : out std_logic;
        ou8_maintenance_response_data : out unsigned(7 downto 0);
        o_maintenance_pause : out std_logic;
        i_maintenance_permitted : in std_logic := '1';
        o_transport_idle : out std_logic;
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

architecture rtl of rabbitpunch_board is
    signal s_request, s_request_write, s_memory_supported : std_logic;
    signal s_memory_valid, s_io_valid : std_logic;
    signal s_irq_pending, s_irq_acknowledge, s_irq_configure, s_irq_twice_per_frame : std_logic;
    signal su24_request_address : unsigned(23 downto 0);
    signal su16_request_data, su16_response_data, su16_memory_data, su16_io_data : unsigned(15 downto 0);
    signal su2_request_bytes : unsigned(1 downto 0);
    signal su16_video_flags : unsigned(15 downto 0);
    signal su9_scroll0_y, su9_scroll0_x, su9_scroll1_y, su9_scroll1_x : unsigned(8 downto 0);
    signal su6_sprite_count, su6_sprite_priority : unsigned(5 downto 0);
    signal s_cpu_paused, s_maintenance_pause, s_cpu_response_valid, s_owner_cpu_idle : std_logic;
    signal s_maintenance_request, s_maintenance_write, s_maintenance_response_valid : std_logic;
    signal s_backend_request, s_backend_write : std_logic;
    signal su24_maintenance_address, su24_backend_address : unsigned(23 downto 0);
    signal su16_maintenance_data, su16_backend_data, su16_cpu_response_data, su16_maintenance_response_data : unsigned(15 downto 0);
    signal su2_maintenance_bytes, su2_backend_bytes : unsigned(1 downto 0);
begin
    su16_response_data <= su16_memory_data when s_memory_valid = '1' else su16_io_data;
    o_cpu_request <= s_request;
    o_cpu_request_write <= s_request_write;
    ou24_cpu_request_address <= su24_request_address;
    ou16_cpu_request_data <= su16_request_data;
    ou2_cpu_request_bytes <= su2_request_bytes;
    ou16_video_flags <= su16_video_flags;
    ou9_scroll0_y <= su9_scroll0_y;
    ou9_scroll0_x <= su9_scroll0_x;
    ou9_scroll1_y <= su9_scroll1_y;
    ou9_scroll1_x <= su9_scroll1_x;
    ou6_sprite_count <= su6_sprite_count;
    ou6_sprite_priority <= su6_sprite_priority;
    o_paused <= s_cpu_paused;
    o_maintenance_pause <= s_maintenance_pause;
    maintenance : entity work.rabbitpunch_maintenance
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize or i_reset or i_maintenance_initialize,
            i_access_requested => i_maintenance_access,
            o_pause => s_maintenance_pause,
            i_cpu_paused => s_cpu_paused and i_maintenance_permitted,
            i_bus_idle => s_owner_cpu_idle,
            i_byte_valid => i_maintenance_valid,
            o_byte_ready => o_maintenance_ready,
            i_byte_write => i_maintenance_write,
            iu14_byte_address => iu14_maintenance_byte_address,
            iu8_byte_data => iu8_maintenance_data,
            o_byte_response_valid => o_maintenance_response_valid,
            ou8_byte_response_data => ou8_maintenance_response_data,
            o_idle => open,
            o_bus_request => s_maintenance_request,
            o_bus_write => s_maintenance_write,
            ou24_bus_address => su24_maintenance_address,
            ou16_bus_data => su16_maintenance_data,
            ou2_bus_bytes => su2_maintenance_bytes,
            i_bus_response_valid => s_maintenance_response_valid,
            iu16_bus_response_data => su16_maintenance_response_data
        );
    bus_owner : entity work.rabbitpunch_bus_owner
        port map (
            i_clk => i_clk,
            i_cpu_request => s_request,
            i_cpu_write => s_request_write,
            iu24_cpu_address => su24_request_address,
            iu16_cpu_data => su16_request_data,
            iu2_cpu_bytes => su2_request_bytes,
            o_cpu_idle => s_owner_cpu_idle,
            o_idle => o_transport_idle,
            o_cpu_response_valid => s_cpu_response_valid,
            ou16_cpu_response_data => su16_cpu_response_data,
            i_maintenance_allowed => s_cpu_paused or i_reset,
            i_maintenance_request => s_maintenance_request,
            i_maintenance_write => s_maintenance_write,
            iu24_maintenance_address => su24_maintenance_address,
            iu16_maintenance_data => su16_maintenance_data,
            iu2_maintenance_bytes => su2_maintenance_bytes,
            o_maintenance_response_valid => s_maintenance_response_valid,
            ou16_maintenance_response_data => su16_maintenance_response_data,
            o_backend_request => s_backend_request,
            o_backend_write => s_backend_write,
            ou24_backend_address => su24_backend_address,
            ou16_backend_data => su16_backend_data,
            ou2_backend_bytes => su2_backend_bytes,
            i_backend_response_valid => s_memory_valid or s_io_valid,
            iu16_backend_response_data => su16_response_data
        );
    cpu : entity work.rabbitpunch_maincpu
        generic map (
            GINT_PHASE_DIVIDER => GINT_PHASE_DIVIDER,
            GBOOL_EXTERNAL_PHASE_ENABLE => GBOOL_EXTERNAL_PHASE_ENABLE
        )
        port map (
            i_clk => i_clk,
            i_phase_enable => i_main_phase_enable,
            i_reset => i_reset,
            i_pause => i_pause or s_maintenance_pause,
            i_interrupt_level1 => s_irq_pending,
            o_interrupt_acknowledge => s_irq_acknowledge,
            o_request => s_request,
            o_request_write => s_request_write,
            ou24_request_address => su24_request_address,
            ou16_request_data => su16_request_data,
            ou2_request_bytes => su2_request_bytes,
            i_response_valid => s_cpu_response_valid,
            iu16_response_data => su16_cpu_response_data,
            o_paused => s_cpu_paused
        );
    board_video : entity work.rabbitpunch_board_video
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_line_valid => i_line_valid,
            o_line_ready => o_line_ready,
            i_render_bank => i_render_bank,
            iu9_line_y => iu9_line_y,
            iu6_sprite_count => su6_sprite_count,
            iu6_sprite_priority => su6_sprite_priority,
            iu9_background_scroll_x => su9_scroll0_x,
            iu9_background_scroll_y => su9_scroll0_y,
            iu9_foreground_scroll_x => su9_scroll1_x,
            iu9_foreground_scroll_y => su9_scroll1_y,
            iu16_video_flags => su16_video_flags,
            o_line_done => o_line_done,
            o_sprite_rom_request => o_sprite_rom_request,
            ou17_sprite_rom_word_address => ou17_sprite_rom_word_address,
            i_sprite_rom_response_valid => i_sprite_rom_response_valid,
            iu32_sprite_rom_response_data => iu32_sprite_rom_response_data,
            o_tile_rom_request => o_tile_rom_request,
            ou17_tile_rom_word_address => ou17_tile_rom_word_address,
            o_tile_rom_foreground => o_tile_rom_foreground,
            i_tile_rom_response_valid => i_tile_rom_response_valid,
            iu32_tile_rom_response_data => iu32_tile_rom_response_data,
            i_pixel_valid => i_pixel_valid,
            o_pixel_ready => o_pixel_ready,
            i_pixel_bank => i_pixel_bank,
            iu9_pixel_x => iu9_pixel_x,
            iu8_pixel_y => iu8_pixel_y,
            iu16_pixel_video_flags => su16_video_flags,
            o_pixel_valid => o_pixel_valid,
            o_pixel_error => o_pixel_error,
            ou9_pixel_x => ou9_pixel_x,
            ou8_pixel_y => ou8_pixel_y,
            ou8_red => ou8_red,
            ou8_green => ou8_green,
            ou8_blue => ou8_blue,
            i_request => s_backend_request,
            i_request_write => s_backend_write,
            iu24_request_address => su24_backend_address,
            iu16_request_data => su16_backend_data,
            iu2_request_bytes => su2_backend_bytes,
            o_request_supported => s_memory_supported,
            o_response_valid => s_memory_valid,
            ou16_response_data => su16_memory_data,
            o_rom_request => o_rom_request,
            ou18_rom_byte_address => ou18_rom_byte_address,
            i_rom_response_valid => i_rom_response_valid,
            iu16_rom_response_data => iu16_rom_response_data,
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data
        );
    io_registers : entity work.rabbitpunch_io
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_request => s_backend_request and not s_memory_supported,
            i_request_write => s_backend_write,
            iu24_request_address => su24_backend_address,
            iu16_request_data => su16_backend_data,
            iu2_request_bytes => su2_backend_bytes,
            o_response_valid => s_io_valid,
            ou16_response_data => su16_io_data,
            iu8_player1 => iu8_player1,
            iu8_player2 => iu8_player2,
            iu8_service => iu8_service,
            iu16_dips => iu16_dips,
            i_sound_command_read => i_sound_command_read,
            o_sound_command_write => o_sound_command_write,
            ou8_sound_command => ou8_sound_command,
            o_sound_pending => o_sound_pending,
            ou16_video_flags => su16_video_flags,
            ou9_scroll0_y => su9_scroll0_y,
            ou9_scroll0_x => su9_scroll0_x,
            ou9_scroll1_y => su9_scroll1_y,
            ou9_scroll1_x => su9_scroll1_x,
            ou6_sprite_count => su6_sprite_count,
            ou6_sprite_priority => su6_sprite_priority,
            ou4_gga_selected => ou4_gga_selected,
            iu4_gga_view_address => iu4_gga_view_address,
            ou8_gga_view_data => ou8_gga_view_data,
            o_gga_write => o_gga_write,
            ou4_gga_write_address => ou4_gga_write_address,
            ou8_gga_write_data => ou8_gga_write_data,
            o_irq_configure => s_irq_configure,
            o_irq_twice_per_frame => s_irq_twice_per_frame
        );
    interrupts : entity work.rabbitpunch_irq
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_configure => s_irq_configure,
            i_twice_per_frame => s_irq_twice_per_frame,
            i_vblank_start => i_vblank_start,
            i_half_frame => i_half_frame,
            i_acknowledge => s_irq_acknowledge,
            o_level1_pending => s_irq_pending
        );
end architecture;
