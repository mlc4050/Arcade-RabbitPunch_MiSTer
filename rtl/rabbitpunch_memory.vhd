library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- ROM transport and the five main-CPU RAM banks. Register targets belong to board I/O.
-- No CPU reset input: accepted accesses complete and RAM survives CPU reset.
entity rabbitpunch_memory is
    port (
        i_clk : in std_logic;
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

architecture rtl of rabbitpunch_memory is
    type t_state is (STATE_IDLE, STATE_RAM_REPLY, STATE_ROM_REPLY);
    signal styp_state : t_state := STATE_IDLE;
    signal su5_target, su5_reply_target, su5_view_target : target_t;
    signal s_reply_write : std_logic;
    signal s_bitmap_enable, s_sprite_enable, s_tile_enable, s_palette_enable, s_work_enable : std_logic;
    signal s_bitmap_view, s_sprite_view, s_tile_view, s_palette_view, s_work_view : std_logic;
    signal su16_bitmap_data, su16_sprite_data, su16_tile_data, su16_palette_data, su16_work_data : unsigned(15 downto 0);
    signal su16_bitmap_view, su16_sprite_view, su16_tile_view, su16_palette_view, su16_work_view : unsigned(15 downto 0);
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
    o_request_supported <= '1' when su5_target = TARGET_ROM or su5_target = TARGET_BITMAP or
        su5_target = TARGET_SPRITES or su5_target = TARGET_TILES or
        su5_target = TARGET_PALETTE or su5_target = TARGET_WORKRAM else '0';
    s_bitmap_enable <= '1' when i_request = '1' and styp_state = STATE_IDLE and su5_target = TARGET_BITMAP else '0';
    s_sprite_enable <= '1' when i_request = '1' and styp_state = STATE_IDLE and su5_target = TARGET_SPRITES else '0';
    s_tile_enable <= '1' when i_request = '1' and styp_state = STATE_IDLE and su5_target = TARGET_TILES else '0';
    s_palette_enable <= '1' when i_request = '1' and styp_state = STATE_IDLE and su5_target = TARGET_PALETTE else '0';
    s_work_enable <= '1' when i_request = '1' and styp_state = STATE_IDLE and su5_target = TARGET_WORKRAM else '0';
    s_bitmap_view <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_BITMAP else '0';
    s_sprite_view <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_SPRITES else '0';
    s_tile_view <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_TILES else '0';
    s_palette_view <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_PALETTE else '0';
    s_work_view <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_WORKRAM else '0';

    bitmap : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 15)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_bitmap_enable,
            i_cpu_write => i_request_write,
            iux_cpu_address => iu24_request_address(15 downto 1),
            iu2_cpu_bytes => iu2_request_bytes,
            iu16_cpu_data => iu16_request_data,
            ou16_cpu_data => su16_bitmap_data,
            i_view_enable => s_bitmap_view,
            iux_view_address => iu15_view_word_address,
            ou16_view_data => su16_bitmap_view
        );
    sprites : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 11)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_sprite_enable,
            i_cpu_write => i_request_write,
            iux_cpu_address => iu24_request_address(11 downto 1),
            iu2_cpu_bytes => iu2_request_bytes,
            iu16_cpu_data => iu16_request_data,
            ou16_cpu_data => su16_sprite_data,
            i_view_enable => s_sprite_view,
            iux_view_address => iu15_view_word_address(10 downto 0),
            ou16_view_data => su16_sprite_view
        );
    tiles : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 13)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_tile_enable,
            i_cpu_write => i_request_write,
            iux_cpu_address => iu24_request_address(13 downto 1),
            iu2_cpu_bytes => iu2_request_bytes,
            iu16_cpu_data => iu16_request_data,
            ou16_cpu_data => su16_tile_data,
            i_view_enable => s_tile_view,
            iux_view_address => iu15_view_word_address(12 downto 0),
            ou16_view_data => su16_tile_view
        );
    palette : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 10)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_palette_enable,
            i_cpu_write => i_request_write,
            iux_cpu_address => iu24_request_address(10 downto 1),
            iu2_cpu_bytes => iu2_request_bytes,
            iu16_cpu_data => iu16_request_data,
            ou16_cpu_data => su16_palette_data,
            i_view_enable => s_palette_view,
            iux_view_address => iu15_view_word_address(9 downto 0),
            ou16_view_data => su16_palette_view
        );
    work_ram : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 13)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_work_enable,
            i_cpu_write => i_request_write,
            iux_cpu_address => iu24_request_address(13 downto 1),
            iu2_cpu_bytes => iu2_request_bytes,
            iu16_cpu_data => iu16_request_data,
            ou16_cpu_data => su16_work_data,
            i_view_enable => s_work_view,
            iux_view_address => iu15_view_word_address(12 downto 0),
            ou16_view_data => su16_work_view
        );

    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_response_valid <= '0';
            o_rom_request <= '0';
            o_view_valid <= i_view_enable;
            su5_view_target <= iu5_view_target;
            case styp_state is
                when STATE_IDLE =>
                    if (i_request = '1') then
                        if (su5_target = TARGET_ROM) then
                            o_rom_request <= '1';
                            ou18_rom_byte_address <= iu24_request_address(17 downto 1) & '0';
                            styp_state <= STATE_ROM_REPLY;
                        elsif (s_bitmap_enable = '1' or s_sprite_enable = '1' or s_tile_enable = '1' or
                                s_palette_enable = '1' or s_work_enable = '1') then
                            su5_reply_target <= su5_target;
                            s_reply_write <= i_request_write;
                            styp_state <= STATE_RAM_REPLY;
                        end if;
                    end if;
                when STATE_RAM_REPLY =>
                    o_response_valid <= '1';
                    styp_state <= STATE_IDLE;
                    if (s_reply_write = '1') then
                        ou16_response_data <= (others => '0');
                    else
                        case su5_reply_target is
                            when TARGET_BITMAP => ou16_response_data <= su16_bitmap_data;
                            when TARGET_SPRITES => ou16_response_data <= su16_sprite_data;
                            when TARGET_TILES => ou16_response_data <= su16_tile_data;
                            when TARGET_PALETTE => ou16_response_data <= su16_palette_data;
                            when TARGET_WORKRAM => ou16_response_data <= su16_work_data;
                            when others => ou16_response_data <= (others => '1');
                        end case;
                    end if;
                when STATE_ROM_REPLY =>
                    if (i_rom_response_valid = '1') then
                        o_response_valid <= '1';
                        ou16_response_data <= iu16_rom_response_data;
                        styp_state <= STATE_IDLE;
                    end if;
            end case;
        end if;
    end process;
    with su5_view_target select ou16_view_data <=
        su16_bitmap_view when TARGET_BITMAP, su16_sprite_view when TARGET_SPRITES,
        su16_tile_view when TARGET_TILES, su16_palette_view when TARGET_PALETTE,
        su16_work_view when TARGET_WORKRAM, (others => '1') when others;
end architecture;
