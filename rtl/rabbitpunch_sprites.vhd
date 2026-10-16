library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Clock-independent logical-line renderer. Descriptor stability and physical
-- line deadlines belong to the caller; this block does not latch a frame list.
entity rabbitpunch_sprites is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_line_valid : in std_logic;
        o_line_ready : out std_logic;
        i_render_bank : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        iu6_sprite_count : in unsigned(5 downto 0);
        iu6_sprite_priority : in unsigned(5 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        o_line_done : out std_logic;
        o_ram_request : out std_logic;
        ou11_ram_word_address : out unsigned(10 downto 0);
        i_ram_response_valid : in std_logic;
        iu16_ram_response_data : in unsigned(15 downto 0);
        o_rom_request : out std_logic;
        ou17_rom_word_address : out unsigned(16 downto 0);
        i_rom_response_valid : in std_logic;
        iu32_rom_response_data : in unsigned(31 downto 0);
        i_view_enable : in std_logic;
        o_view_ready : out std_logic;
        i_view_bank : in std_logic;
        iu9_view_x : in unsigned(8 downto 0);
        o_view_valid : out std_logic;
        ou9_view_line_y : out unsigned(8 downto 0);
        ou16_view_entry : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_sprites is
    type t_state is (STATE_IDLE, STATE_DRAW, STATE_FINISH);
    signal styp_state : t_state := STATE_IDLE;
    signal s_line_ready, s_start_line, s_finish_line, s_scan_finished : std_logic := '0';
    signal s_scan_ready, s_scan_done, s_draw_ready, s_store_ready, s_store_done : std_logic;
    signal s_row_valid, s_row_ready, s_store_candidate_ready : std_logic;
    signal s_render_bank, s_horizontal_flip, s_vertical_flip, s_behind : std_logic;
    signal su9_line_y, su9_row_x, su9_row_y : unsigned(8 downto 0);
    signal su6_count, su6_priority, su6_scan_index, su6_draw_index : unsigned(5 downto 0);
    signal su16_flags : unsigned(15 downto 0);
    signal su11_code : unsigned(10 downto 0);
    signal su5_row : unsigned(4 downto 0);
    signal su4_palette : unsigned(3 downto 0);
    signal s_pixel_valid, s_pixel_behind : std_logic;
    signal su9_pixel_x, su9_pixel_y : unsigned(8 downto 0);
    signal su10_pixel_index : unsigned(9 downto 0);
begin
    s_line_ready <= '1' when styp_state = STATE_IDLE and s_scan_ready = '1' and
        s_draw_ready = '1' and s_store_ready = '1' and i_reset = '0' else '0';
    o_line_ready <= s_line_ready;
    s_row_ready <= s_draw_ready and s_store_candidate_ready;

    selector : entity work.rabbitpunch_sprite_scan
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_line_valid => s_start_line,
            o_line_ready => s_scan_ready,
            iu9_line_y => su9_line_y,
            iu6_sprite_count => su6_count,
            iu6_sprite_priority => su6_priority,
            iu16_video_flags => su16_flags,
            o_scan_done => s_scan_done,
            o_ram_request => o_ram_request,
            ou11_ram_word_address => ou11_ram_word_address,
            i_ram_response_valid => i_ram_response_valid,
            iu16_ram_response_data => iu16_ram_response_data,
            o_row_valid => s_row_valid,
            i_row_ready => s_row_ready,
            ou6_sprite_index => su6_scan_index,
            ou11_sprite_code => su11_code,
            ou5_sprite_row => su5_row,
            ou9_pixel_x => su9_row_x,
            ou9_pixel_y => su9_row_y,
            ou4_palette => su4_palette,
            o_horizontal_flip => s_horizontal_flip,
            o_vertical_flip => s_vertical_flip,
            o_behind_foreground => s_behind
        );
    drawer : entity work.rabbitpunch_sprite_row
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_row_valid => s_row_valid and s_store_candidate_ready,
            o_row_ready => s_draw_ready,
            iu11_sprite_code => su11_code,
            iu5_sprite_row => su5_row,
            iu9_pixel_x => su9_row_x,
            iu9_pixel_y => su9_row_y,
            iu4_palette => su4_palette,
            i_horizontal_flip => s_horizontal_flip,
            i_vertical_flip => s_vertical_flip,
            i_behind_foreground => s_behind,
            o_rom_request => o_rom_request,
            ou17_rom_word_address => ou17_rom_word_address,
            i_rom_response_valid => i_rom_response_valid,
            iu32_rom_response_data => iu32_rom_response_data,
            o_pixel_valid => s_pixel_valid,
            ou9_pixel_x => su9_pixel_x,
            ou9_pixel_y => su9_pixel_y,
            ou10_palette_index => su10_pixel_index,
            o_opaque => open,
            o_behind_foreground => s_pixel_behind
        );
    storage : entity work.rabbitpunch_sprite_line
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_line_start => s_start_line,
            o_line_ready => s_store_ready,
            i_render_bank => s_render_bank,
            iu9_line_y => su9_line_y,
            i_line_finish => s_finish_line,
            o_line_done => s_store_done,
            i_candidate_valid => s_pixel_valid,
            o_candidate_ready => s_store_candidate_ready,
            iu9_candidate_x => su9_pixel_x,
            iu6_candidate_index => su6_draw_index,
            iu8_candidate_palette => su10_pixel_index(7 downto 0),
            i_candidate_behind_foreground => s_pixel_behind,
            i_view_enable => i_view_enable,
            o_view_ready => o_view_ready,
            i_view_bank => i_view_bank,
            iu9_view_x => iu9_view_x,
            o_view_valid => o_view_valid,
            ou9_view_line_y => ou9_view_line_y,
            ou16_view_entry => ou16_view_entry
        );

    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_start_line <= '0';
            s_finish_line <= '0';
            o_line_done <= '0';
            if (s_row_valid = '1' and s_row_ready = '1') then
                su6_draw_index <= su6_scan_index;
            end if;
            if (i_reset = '1') then
                styp_state <= STATE_IDLE;
                s_scan_finished <= '0';
            else
                if (s_scan_done = '1') then
                    s_scan_finished <= '1';
                end if;
                case styp_state is
                    when STATE_IDLE =>
                        if (i_line_valid = '1' and s_line_ready = '1') then
                            s_render_bank <= i_render_bank;
                            su9_line_y <= iu9_line_y;
                            su6_count <= iu6_sprite_count;
                            su6_priority <= iu6_sprite_priority;
                            su16_flags <= iu16_video_flags;
                            s_scan_finished <= '0';
                            s_start_line <= '1';
                            styp_state <= STATE_DRAW;
                        end if;
                    when STATE_DRAW =>
                        if (s_scan_finished = '1' and s_draw_ready = '1' and
                            s_row_valid = '0' and s_store_candidate_ready = '1') then
                            s_finish_line <= '1';
                            styp_state <= STATE_FINISH;
                        end if;
                    when STATE_FINISH =>
                        if (s_store_done = '1') then
                            o_line_done <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
