library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One outstanding bitmap fetch; no composed-frame storage or scanout timing.
-- Coordinates use MAME's logical 512 x 256 bitmap space, before visible cropping.
entity rabbitpunch_bitmap is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_pixel_valid : in std_logic;
        o_pixel_ready : out std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu8_pixel_y : in unsigned(7 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        o_ram_request : out std_logic;
        ou15_ram_word_address : out unsigned(14 downto 0);
        i_ram_response_valid : in std_logic;
        iu16_ram_response_data : in unsigned(15 downto 0);
        o_pixel_valid : out std_logic;
        ou9_pixel_x : out unsigned(8 downto 0);
        ou8_pixel_y : out unsigned(7 downto 0);
        ou10_palette_index : out unsigned(9 downto 0);
        o_opaque : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_bitmap is
    type styp_state is (STATE_IDLE, STATE_WAITING, STATE_DRAINING);
    signal s_state : styp_state := STATE_IDLE;
    signal su9_pixel_x : unsigned(8 downto 0);
    signal su8_pixel_y : unsigned(7 downto 0);
    signal su2_nibble : unsigned(1 downto 0);
    signal su4_palette_bank : unsigned(3 downto 0);
begin
    o_pixel_ready <= '1' when s_state = STATE_IDLE and i_reset = '0' else '0';
    process(i_clk)
        variable vu9_source_x : unsigned(8 downto 0);
        variable vu4_pen : unsigned(3 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_pixel_valid <= '0';
            o_ram_request <= '0';
            if (i_reset = '1') then
                -- An accepted RAM request must still reply after pixel-pipeline reset.
                if ((s_state = STATE_WAITING or s_state = STATE_DRAINING) and i_ram_response_valid = '0') then
                    s_state <= STATE_DRAINING;
                else
                    s_state <= STATE_IDLE;
                end if;
            else
                case s_state is
                    when STATE_IDLE =>
                        if (i_pixel_valid = '1') then
                            vu9_source_x := iu9_pixel_x + 4;
                            ou15_ram_word_address <= iu8_pixel_y & vu9_source_x(8 downto 2);
                            su2_nibble <= vu9_source_x(1 downto 0);
                            su4_palette_bank <= iu16_video_flags(3 downto 0);
                            su9_pixel_x <= iu9_pixel_x;
                            su8_pixel_y <= iu8_pixel_y;
                            o_ram_request <= '1';
                            s_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_ram_response_valid = '1') then
                            case su2_nibble is
                                when "00" => vu4_pen := iu16_ram_response_data(15 downto 12);
                                when "01" => vu4_pen := iu16_ram_response_data(11 downto 8);
                                when "10" => vu4_pen := iu16_ram_response_data(7 downto 4);
                                when "11" => vu4_pen := iu16_ram_response_data(3 downto 0);
                                when others => vu4_pen := (others => 'X');
                            end case;
                            ou10_palette_index <= "10" & su4_palette_bank & vu4_pen;
                            if (vu4_pen = 15) then
                                o_opaque <= '0';
                            else
                                o_opaque <= '1';
                            end if;
                            ou9_pixel_x <= su9_pixel_x;
                            ou8_pixel_y <= su8_pixel_y;
                            o_pixel_valid <= '1';
                            s_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAINING =>
                        if (i_ram_response_valid = '1') then
                            s_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
