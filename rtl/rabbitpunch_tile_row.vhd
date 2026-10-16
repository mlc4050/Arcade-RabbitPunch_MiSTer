library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One unflipped 8-pixel tile row through the unchanged JTFRAME drawer.
-- A row emits eight consecutive pixels; its consumer must accept the burst.
entity rabbitpunch_tile_row is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_row_valid : in std_logic;
        o_row_ready : out std_logic;
        iu14_tile_code : in unsigned(13 downto 0);
        iu3_tile_row : in unsigned(2 downto 0);
        iu9_pixel_x : in unsigned(8 downto 0);
        iu9_pixel_y : in unsigned(8 downto 0);
        iu4_palette : in unsigned(3 downto 0);
        i_foreground : in std_logic;
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

architecture rtl of rabbitpunch_tile_row is
    component jtframe_draw is
        generic (
            AW : integer := 9;
            CW : integer := 14;
            PW : integer := 9;
            ZW : integer := 6;
            ZI : integer := 5;
            ZENLARGE : integer := 0;
            SWAPH : integer := 0;
            KEEP_OLD : integer := 0
        );
        port (
            rst, clk, draw : in std_logic;
            busy : out std_logic;
            code : in unsigned(CW-1 downto 0);
            xpos : in unsigned(AW-1 downto 0);
            ysub : in unsigned(3 downto 0);
            trunc : in unsigned(1 downto 0);
            hzoom : in unsigned(ZW-1 downto 0);
            hz_keep, hflip, vflip : in std_logic;
            pal : in unsigned(PW-5 downto 0);
            -- Match the foreign Verilog port indices as well as its width.
            rom_addr : out unsigned(CW+6 downto 2);
            rom_cs : out std_logic;
            rom_ok : in std_logic;
            rom_data : in unsigned(31 downto 0);
            buf_addr : out unsigned(AW-1 downto 0);
            buf_we : out std_logic;
            buf_din : out unsigned(PW-1 downto 0)
        );
    end component;
    type t_state is (STATE_IDLE, STATE_FETCH, STATE_WAITING, STATE_DRAWING, STATE_DRAINING);
    signal styp_state : t_state := STATE_IDLE;
    signal s_start_draw, s_draw_busy, s_rom_selected, s_rom_ready : std_logic;
    signal s_buffer_write, s_foreground : std_logic;
    signal su14_tile_code : unsigned(13 downto 0);
    signal su4_tile_row : unsigned(3 downto 0);
    signal su9_pixel_x, su9_buffer_address, su9_buffer_data : unsigned(8 downto 0);
    signal su9_pixel_y : unsigned(8 downto 0);
    signal su5_palette : unsigned(4 downto 0);
    signal su19_draw_address : unsigned(20 downto 2);
    signal su32_planar_data : unsigned(31 downto 0);
begin
    o_row_ready <= '1' when styp_state = STATE_IDLE and i_reset = '0' else '0';
    o_pixel_valid <= s_buffer_write when styp_state = STATE_DRAWING and i_reset = '0' else '0';
    ou9_pixel_x <= su9_buffer_address;
    ou9_pixel_y <= su9_pixel_y;
    o_rom_foreground <= s_foreground;
    ou9_palette_index <= su9_buffer_data;
    o_opaque <= '0' when s_foreground = '1' and su9_buffer_data(3 downto 0) = 15 else '1';

    drawer : jtframe_draw
        generic map (AW => 9, CW => 14, PW => 9)
        port map (
            rst => i_reset,
            clk => i_clk,
            draw => s_start_draw,
            busy => s_draw_busy,
            code => su14_tile_code,
            xpos => su9_pixel_x,
            ysub => su4_tile_row,
            trunc => "10", -- Eight pixels instead of the drawer's default sixteen.
            hzoom => "000000", -- Native size, no zoom.
            hz_keep => '0',
            hflip => '0',
            vflip => '0',
            pal => su5_palette,
            rom_addr => su19_draw_address,
            rom_cs => s_rom_selected,
            rom_ok => s_rom_ready,
            rom_data => su32_planar_data,
            buf_addr => su9_buffer_address,
            buf_we => s_buffer_write,
            buf_din => su9_buffer_data
        );

    process(i_clk)
        variable vu32_planar_data : unsigned(31 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_rom_request <= '0';
            s_start_draw <= '0';
            if (i_reset = '1') then
                s_rom_ready <= '0';
                if ((styp_state = STATE_WAITING or styp_state = STATE_DRAINING) and i_rom_response_valid = '0') then
                    styp_state <= STATE_DRAINING;
                else
                    styp_state <= STATE_IDLE;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_row_valid = '1') then
                            su14_tile_code <= iu14_tile_code;
                            su4_tile_row <= '0' & iu3_tile_row;
                            su9_pixel_x <= iu9_pixel_x;
                            su9_pixel_y <= iu9_pixel_y;
                            su5_palette <= i_foreground & iu4_palette;
                            s_foreground <= i_foreground;
                            s_rom_ready <= '0';
                            s_start_draw <= '1';
                            styp_state <= STATE_FETCH;
                        end if;
                    when STATE_FETCH =>
                        if (s_rom_selected = '1') then
                            -- JTFRAME uses {code, half, row[3:0]}; an 8x8 tile
                            -- uses {code, row[2:0]} as its 32-bit word address.
                            ou17_rom_word_address <= su19_draw_address(20 downto 7) & su19_draw_address(4 downto 2);
                            o_rom_request <= '1';
                            styp_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_rom_response_valid = '1') then
                            -- MAME's tile ROM is packed, low nibble first.
                            -- JTFRAME consumes four bitplanes, left pixel at bit 0.
                            for vint_pixel in 0 to 7 loop
                                for vint_plane in 0 to 3 loop
                                    vu32_planar_data(vint_plane*8+vint_pixel) := iu32_rom_response_data(vint_pixel*4+vint_plane);
                                end loop;
                            end loop;
                            su32_planar_data <= vu32_planar_data;
                            s_rom_ready <= '1';
                            styp_state <= STATE_DRAWING;
                        end if;
                    when STATE_DRAWING =>
                        if (s_draw_busy = '0') then
                            s_rom_ready <= '0';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAINING =>
                        if (i_rom_response_valid = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
