library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Column-major 64x64 tilemap lookup with a single queued row descriptor.
-- Scroll and flags are sampled per accepted request, not latched per frame.
entity rabbitpunch_tile_lookup is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_request_valid : in std_logic;
        o_request_ready : out std_logic;
        iu9_pixel_x : in unsigned(8 downto 0);
        iu9_pixel_y : in unsigned(8 downto 0);
        iu9_scroll_x : in unsigned(8 downto 0);
        iu9_scroll_y : in unsigned(8 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        i_foreground : in std_logic;
        o_ram_request : out std_logic;
        ou13_ram_word_address : out unsigned(12 downto 0);
        i_ram_response_valid : in std_logic;
        iu16_ram_response_data : in unsigned(15 downto 0);
        o_row_valid : out std_logic;
        i_row_ready : in std_logic;
        ou14_tile_code : out unsigned(13 downto 0);
        ou3_tile_row : out unsigned(2 downto 0);
        ou9_pixel_x : out unsigned(8 downto 0);
        ou9_pixel_y : out unsigned(8 downto 0);
        ou4_palette : out unsigned(3 downto 0);
        o_foreground : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_tile_lookup is
    type t_state is (STATE_IDLE, STATE_WAITING, STATE_OUTPUT, STATE_DRAINING);
    signal styp_state : t_state := STATE_IDLE;
    signal s_code_bank, s_palette_bank : std_logic;
begin
    o_request_ready <= '1' when styp_state = STATE_IDLE and i_reset = '0' else '0';
    o_row_valid <= '1' when styp_state = STATE_OUTPUT and i_reset = '0' else '0';
    process(i_clk)
        variable vu9_source_x, vu9_source_y : unsigned(8 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_ram_request <= '0';
            if (i_reset = '1') then
                if ((styp_state = STATE_WAITING or styp_state = STATE_DRAINING) and i_ram_response_valid = '0') then
                    styp_state <= STATE_DRAINING;
                else
                    styp_state <= STATE_IDLE;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_request_valid = '1') then
                            vu9_source_x := iu9_pixel_x + iu9_scroll_x;
                            vu9_source_y := iu9_pixel_y + iu9_scroll_y;
                            ou13_ram_word_address <= i_foreground & vu9_source_x(8 downto 3) & vu9_source_y(8 downto 3);
                            ou3_tile_row <= vu9_source_y(2 downto 0);
                            ou9_pixel_x <= iu9_pixel_x - resize(vu9_source_x(2 downto 0), 9);
                            ou9_pixel_y <= iu9_pixel_y;
                            o_foreground <= i_foreground;
                            if (i_foreground = '1') then
                                s_code_bank <= iu16_video_flags(11);
                                s_palette_bank <= iu16_video_flags(5);
                            else
                                s_code_bank <= iu16_video_flags(10);
                                s_palette_bank <= iu16_video_flags(4);
                            end if;
                            o_ram_request <= '1';
                            styp_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_ram_response_valid = '1') then
                            if (s_code_bank = '1') then
                                ou14_tile_code <= "10" & iu16_ram_response_data(11 downto 0);
                            else
                                ou14_tile_code <= '0' & iu16_ram_response_data(12 downto 0);
                            end if;
                            ou4_palette <= s_palette_bank & iu16_ram_response_data(15 downto 13);
                            styp_state <= STATE_OUTPUT;
                        end if;
                    when STATE_OUTPUT =>
                        if (i_row_ready = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAINING =>
                        if (i_ram_response_valid = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
