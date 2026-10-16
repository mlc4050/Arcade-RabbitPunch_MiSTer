library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One native 16x32 sprite row through the unchanged JTFRAME drawer. Pixels
-- arrive in two eight-pixel bursts, with a possible ROM wait between halves.
entity rabbitpunch_sprite_row is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_row_valid : in std_logic;
        o_row_ready : out std_logic;
        iu11_sprite_code : in unsigned(10 downto 0);
        iu5_sprite_row : in unsigned(4 downto 0);
        iu9_pixel_x : in unsigned(8 downto 0);
        iu9_pixel_y : in unsigned(8 downto 0);
        iu4_palette : in unsigned(3 downto 0);
        i_horizontal_flip : in std_logic;
        i_vertical_flip : in std_logic;
        i_behind_foreground : in std_logic;
        o_rom_request : out std_logic;
        ou17_rom_word_address : out unsigned(16 downto 0);
        i_rom_response_valid : in std_logic;
        iu32_rom_response_data : in unsigned(31 downto 0);
        o_pixel_valid : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou9_pixel_y : out unsigned(8 downto 0);
        ou10_palette_index : out unsigned(9 downto 0);
        o_opaque : out std_logic;
        o_behind_foreground : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_sprite_row is
    component jtframe_draw is
        generic (
            AW : integer := 9;
            CW : integer := 12;
            PW : integer := 8;
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
            rom_addr : out unsigned(CW+4 downto 0);
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
    signal s_start_draw, s_draw_busy, s_rom_selected, s_rom_ready, s_buffer_write : std_logic;
    signal s_horizontal_flip, s_vertical_flip, s_behind_foreground : std_logic;
    signal su12_draw_code : unsigned(11 downto 0);
    signal su4_sprite_row, su4_palette : unsigned(3 downto 0);
    signal su9_pixel_x, su9_pixel_y, su9_buffer_address : unsigned(8 downto 0);
    signal su8_buffer_data : unsigned(7 downto 0);
    signal su17_draw_address, su17_last_address : unsigned(16 downto 0);
    signal su32_planar_data : unsigned(31 downto 0);
begin
    o_row_ready <= '1' when styp_state = STATE_IDLE and i_reset = '0' else '0';
    o_pixel_valid <= s_buffer_write when
        (styp_state = STATE_WAITING or styp_state = STATE_DRAWING) and i_reset = '0' else '0';
    ou9_pixel_x <= su9_buffer_address;
    ou9_pixel_y <= su9_pixel_y;
    ou10_palette_index <= "11" & su8_buffer_data;
    o_opaque <= '0' when styp_state = STATE_IDLE else
        '0' when su8_buffer_data(3 downto 0) = 15 else '1';
    o_behind_foreground <= s_behind_foreground;

    drawer : jtframe_draw
        port map (
            rst => i_reset,
            clk => i_clk,
            draw => s_start_draw,
            busy => s_draw_busy,
            code => su12_draw_code,
            xpos => su9_pixel_x,
            ysub => su4_sprite_row,
            trunc => "00", -- Both eight-pixel halves of the native sprite row.
            hzoom => "000000",
            hz_keep => '0',
            hflip => s_horizontal_flip,
            vflip => s_vertical_flip,
            pal => su4_palette,
            rom_addr => su17_draw_address,
            rom_cs => s_rom_selected,
            rom_ok => s_rom_ready,
            rom_data => su32_planar_data,
            buf_addr => su9_buffer_address,
            buf_we => s_buffer_write,
            buf_din => su8_buffer_data
        );

    process(i_clk)
        variable vu32_planar_data : unsigned(31 downto 0);
        variable vint_packed_pixel : natural range 0 to 7;
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
                            -- The donor draws 16-high cells: its code bit zero
                            -- supplies the fifth row bit of our 32-high sprite.
                            su12_draw_code <= iu11_sprite_code & (iu5_sprite_row(4) xor i_vertical_flip);
                            su4_sprite_row <= iu5_sprite_row(3 downto 0);
                            su9_pixel_x <= iu9_pixel_x;
                            su9_pixel_y <= iu9_pixel_y;
                            su4_palette <= iu4_palette;
                            s_horizontal_flip <= i_horizontal_flip;
                            s_vertical_flip <= i_vertical_flip;
                            s_behind_foreground <= i_behind_foreground;
                            s_rom_ready <= '0';
                            s_start_draw <= '1';
                            styp_state <= STATE_FETCH;
                        end if;
                    when STATE_FETCH =>
                        if (s_rom_selected = '1') then
                            -- Donor {code12,half,row4} -> ROM {code11,row5,half}.
                            ou17_rom_word_address <= su17_draw_address(16 downto 5) &
                                su17_draw_address(3 downto 0) & su17_draw_address(4);
                            su17_last_address <= su17_draw_address;
                            o_rom_request <= '1';
                            styp_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_rom_response_valid = '1') then
                            -- MAME splayout reverses byte pairs within each group
                            -- of four pixels. Convert packed nibbles to planes.
                            for vint_pixel in 0 to 7 loop
                                vint_packed_pixel := to_integer(to_unsigned(vint_pixel, 3) xor "010");
                                for vint_plane in 0 to 3 loop
                                    vu32_planar_data(vint_plane * 8 + vint_pixel) :=
                                        iu32_rom_response_data(vint_packed_pixel * 4 + vint_plane);
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
                        elsif (s_rom_selected = '1' and su17_draw_address /= su17_last_address) then
                            -- The donor changes to the next half while emitting
                            -- the first: overlap its ROM wait with those pixels.
                            ou17_rom_word_address <= su17_draw_address(16 downto 5) &
                                su17_draw_address(3 downto 0) & su17_draw_address(4);
                            su17_last_address <= su17_draw_address;
                            s_rom_ready <= '0';
                            o_rom_request <= '1';
                            styp_state <= STATE_WAITING;
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
