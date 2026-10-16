library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Select rows intersecting one logical scanline from a caller-stable sprite
-- list. This does not choose a PCB latch point or create a frame snapshot.
entity rabbitpunch_sprite_scan is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_line_valid : in std_logic;
        o_line_ready : out std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        iu6_sprite_count : in unsigned(5 downto 0);
        iu6_sprite_priority : in unsigned(5 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        o_scan_done : out std_logic;
        o_ram_request : out std_logic;
        ou11_ram_word_address : out unsigned(10 downto 0);
        i_ram_response_valid : in std_logic;
        iu16_ram_response_data : in unsigned(15 downto 0);
        o_row_valid : out std_logic;
        i_row_ready : in std_logic;
        ou6_sprite_index : out unsigned(5 downto 0);
        ou11_sprite_code : out unsigned(10 downto 0);
        ou5_sprite_row : out unsigned(4 downto 0);
        ou9_pixel_x : out unsigned(8 downto 0);
        ou9_pixel_y : out unsigned(8 downto 0);
        ou4_palette : out unsigned(3 downto 0);
        o_horizontal_flip : out std_logic;
        o_vertical_flip : out std_logic;
        o_behind_foreground : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_sprite_scan is
    type t_state is (
        STATE_IDLE, STATE_FETCH_Y, STATE_WAIT_Y, STATE_FETCH_ATTRIBUTES,
        STATE_WAIT_ATTRIBUTES, STATE_FETCH_X, STATE_WAIT_X, STATE_OUTPUT, STATE_DRAINING
    );
    signal styp_state : t_state := STATE_IDLE;
    signal su9_line_y : unsigned(8 downto 0);
    signal su6_sprite_index, su6_priority : unsigned(5 downto 0);
    signal s_palette_bank : std_logic;
begin
    o_line_ready <= '1' when styp_state = STATE_IDLE and i_reset = '0' else '0';
    o_row_valid <= '1' when styp_state = STATE_OUTPUT and i_reset = '0' else '0';
    ou6_sprite_index <= su6_sprite_index;
    ou9_pixel_y <= su9_line_y;

    process(i_clk)
        variable vu9_local_row : unsigned(8 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_ram_request <= '0';
            o_scan_done <= '0';
            if (i_reset = '1') then
                if ((styp_state = STATE_WAIT_Y or styp_state = STATE_WAIT_ATTRIBUTES or
                    styp_state = STATE_WAIT_X or styp_state = STATE_DRAINING) and i_ram_response_valid = '0') then
                    styp_state <= STATE_DRAINING;
                else
                    styp_state <= STATE_IDLE;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_line_valid = '1') then
                            su9_line_y <= iu9_line_y;
                            su6_priority <= iu6_sprite_priority;
                            s_palette_bank <= iu16_video_flags(6);
                            if (iu6_sprite_count = 0) then
                                o_scan_done <= '1';
                            else
                                su6_sprite_index <= iu6_sprite_count - 1;
                                styp_state <= STATE_FETCH_Y;
                            end if;
                        end if;
                    when STATE_FETCH_Y =>
                        ou11_ram_word_address <= "000" & su6_sprite_index & "00";
                        o_ram_request <= '1';
                        styp_state <= STATE_WAIT_Y;
                    when STATE_WAIT_Y =>
                        if (i_ram_response_valid = '1') then
                            -- MAME origin is 513 - Y; subtract modulo 512.
                            vu9_local_row := su9_line_y + iu16_ram_response_data(8 downto 0) - 1;
                            if (vu9_local_row < 32) then
                                ou5_sprite_row <= vu9_local_row(4 downto 0);
                                styp_state <= STATE_FETCH_ATTRIBUTES;
                            elsif (su6_sprite_index = 0) then
                                o_scan_done <= '1';
                                styp_state <= STATE_IDLE;
                            else
                                su6_sprite_index <= su6_sprite_index - 1;
                                styp_state <= STATE_FETCH_Y;
                            end if;
                        end if;
                    when STATE_FETCH_ATTRIBUTES =>
                        ou11_ram_word_address <= "000" & su6_sprite_index & "01";
                        o_ram_request <= '1';
                        styp_state <= STATE_WAIT_ATTRIBUTES;
                    when STATE_WAIT_ATTRIBUTES =>
                        if (i_ram_response_valid = '1') then
                            ou11_sprite_code <= iu16_ram_response_data(10 downto 0);
                            ou4_palette <= s_palette_bank & iu16_ram_response_data(15 downto 13);
                            o_horizontal_flip <= iu16_ram_response_data(12);
                            o_vertical_flip <= iu16_ram_response_data(11);
                            o_behind_foreground <= '0';
                            if (su6_sprite_index < su6_priority) then
                                o_behind_foreground <= '1';
                            end if;
                            styp_state <= STATE_FETCH_X;
                        end if;
                    when STATE_FETCH_X =>
                        ou11_ram_word_address <= "000" & su6_sprite_index & "10";
                        o_ram_request <= '1';
                        styp_state <= STATE_WAIT_X;
                    when STATE_WAIT_X =>
                        if (i_ram_response_valid = '1') then
                            ou9_pixel_x <= iu16_ram_response_data(8 downto 0) + 8;
                            styp_state <= STATE_OUTPUT;
                        end if;
                    when STATE_OUTPUT =>
                        if (i_row_ready = '1') then
                            if (su6_sprite_index = 0) then
                                o_scan_done <= '1';
                                styp_state <= STATE_IDLE;
                            else
                                su6_sprite_index <= su6_sprite_index - 1;
                                styp_state <= STATE_FETCH_Y;
                            end if;
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
