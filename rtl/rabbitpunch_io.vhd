library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- Board register and input responder. Route only requests not claimed by memory.
-- Initialization is a cold-start operation, independent of the main CPU reset.
entity rabbitpunch_io is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_request : in std_logic;
        i_request_write : in std_logic;
        iu24_request_address : in unsigned(23 downto 0);
        iu16_request_data : in unsigned(15 downto 0);
        iu2_request_bytes : in unsigned(1 downto 0);
        o_response_valid : out std_logic;
        ou16_response_data : out unsigned(15 downto 0);
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
        o_irq_configure : out std_logic;
        o_irq_twice_per_frame : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_io is
    type gga_t is array (0 to 15) of unsigned(7 downto 0);
    signal su8_gga : gga_t;
    signal su4_gga_selected : unsigned(3 downto 0) := (others => '0');
    signal su5_target : target_t;
    signal s_sound_pending : std_logic := '0';
begin
    decoder : entity work.rabbitpunch_decode
        port map (
            iu24_address => iu24_request_address,
            i_active => i_request,
            i_read => not i_request_write,
            i_upper_byte_strobe_n => not iu2_request_bytes(1),
            i_lower_byte_strobe_n => not iu2_request_bytes(0),
            ou5_target => su5_target
        );
    ou4_gga_selected <= su4_gga_selected;
    ou8_gga_view_data <= su8_gga(to_integer(iu4_gga_view_address));
    o_sound_pending <= s_sound_pending;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_response_valid <= '0';
            o_sound_command_write <= '0';
            o_gga_write <= '0';
            o_irq_configure <= '0';
            if (i_initialize = '1') then
                su8_gga <= (others => (others => '0'));
                su4_gga_selected <= (others => '0');
                s_sound_pending <= '0';
                ou8_sound_command <= (others => '0');
                ou16_video_flags <= (others => '0');
                ou9_scroll0_y <= (others => '0');
                ou9_scroll0_x <= (others => '0');
                ou9_scroll1_y <= (others => '0');
                ou9_scroll1_x <= (others => '0');
                ou6_sprite_count <= (others => '0');
                ou6_sprite_priority <= (others => '0');
                o_irq_twice_per_frame <= '0';
                ou4_gga_write_address <= (others => '0');
                ou8_gga_write_data <= (others => '0');
                ou16_response_data <= (others => '1');
            else
                if (i_sound_command_read = '1') then
                    s_sound_pending <= '0';
                end if;
                if (i_request = '1') then
                    o_response_valid <= '1';
                    ou16_response_data <= (others => '1');
                    case su5_target is
                        when TARGET_P1 => ou16_response_data <= iu8_service & iu8_player1;
                        when TARGET_P2 => ou16_response_data <= iu8_service & iu8_player2;
                        when TARGET_DSW => ou16_response_data <= iu16_dips;
                        when TARGET_SOUND_PENDING =>
                            ou16_response_data <= (others => '0');
                            ou16_response_data(0) <= s_sound_pending;
                        when TARGET_VIDEO_FLAGS =>
                            if (iu2_request_bytes(1) = '1') then
                                ou16_video_flags(15 downto 8) <= iu16_request_data(15 downto 8);
                            end if;
                            if (iu2_request_bytes(0) = '1') then
                                ou16_video_flags(7 downto 0) <= iu16_request_data(7 downto 0);
                            end if;
                        when TARGET_SCROLL =>
                            case iu24_request_address(2 downto 1) is
                                when "00" => ou9_scroll0_y <= iu16_request_data(8 downto 0);
                                when "01" => ou9_scroll0_x <= iu16_request_data(8 downto 0);
                                when "10" => ou9_scroll1_y <= iu16_request_data(8 downto 0);
                                when "11" => ou9_scroll1_x <= iu16_request_data(8 downto 0);
                                when others => null;
                            end case;
                        when TARGET_SPRITE_COUNT => ou6_sprite_count <= iu16_request_data(5 downto 0);
                        when TARGET_SPRITE_PRIORITY => ou6_sprite_priority <= iu16_request_data(5 downto 0);
                        when TARGET_GGA_SELECT => su4_gga_selected <= iu16_request_data(3 downto 0);
                        when TARGET_GGA_DATA =>
                            su8_gga(to_integer(su4_gga_selected)) <= iu16_request_data(7 downto 0);
                            o_gga_write <= '1';
                            ou4_gga_write_address <= su4_gga_selected;
                            ou8_gga_write_data <= iu16_request_data(7 downto 0);
                            if (su4_gga_selected = 11) then
                                o_irq_configure <= '1';
                                if (iu16_request_data(7 downto 0) = x"C0") then
                                    o_irq_twice_per_frame <= '1';
                                else
                                    o_irq_twice_per_frame <= '0';
                                end if;
                            end if;
                        when TARGET_SOUND_COMMAND =>
                            ou8_sound_command <= iu16_request_data(7 downto 0);
                            s_sound_pending <= '1';
                            o_sound_command_write <= '1';
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture;
