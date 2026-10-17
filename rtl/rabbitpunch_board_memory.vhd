library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- ROM transport and the five main-CPU RAM banks. Register targets belong to board I/O.
-- No CPU reset input: accepted accesses complete and RAM survives CPU reset.
entity rabbitpunch_board_memory is
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
        ou16_view_data : out unsigned(15 downto 0);
        i_bitmap_read_enable : in std_logic;
        iu15_bitmap_word_address : in unsigned(14 downto 0);
        ou16_bitmap_data : out unsigned(15 downto 0);
        i_palette_read_enable : in std_logic;
        iu10_palette_word_address : in unsigned(9 downto 0);
        ou16_palette_data : out unsigned(15 downto 0);
        i_sprite_request : in std_logic;
        iu11_sprite_word_address : in unsigned(10 downto 0);
        o_sprite_response_valid : out std_logic;
        ou16_sprite_data : out unsigned(15 downto 0);
        i_tile_request : in std_logic;
        iu13_tile_word_address : in unsigned(12 downto 0);
        o_tile_response_valid : out std_logic;
        ou16_tile_data : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_board_memory is
    type t_state is (STATE_IDLE, STATE_WAIT_WRITE_SLOT, STATE_RAM_REPLY, STATE_ROM_REPLY);
    signal styp_state : t_state := STATE_IDLE;
    signal su5_target, su5_reply_target, su5_view_target : target_t := TARGET_NONE;
    signal s_reply_write, s_access_write, s_cpu_issue, s_write_collision : std_logic;
    signal su24_access_address, su24_pending_address : unsigned(23 downto 0) := (others => '0');
    signal su16_access_data, su16_pending_data : unsigned(15 downto 0);
    signal su2_access_bytes, su2_pending_bytes : unsigned(1 downto 0);
    signal su5_access_target : target_t := TARGET_NONE;
    signal su15_bitmap_address : unsigned(14 downto 0) := (others => '0');
    signal su11_sprite_address : unsigned(10 downto 0) := (others => '0');
    signal su13_tile_address : unsigned(12 downto 0) := (others => '0');
    signal su10_palette_address : unsigned(9 downto 0) := (others => '0');
    signal s_inspect_bitmap, s_inspect_sprite, s_inspect_tile, s_inspect_palette : std_logic;
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
    o_request_supported <= '1' when i_request = '1' and (su5_target = TARGET_ROM or su5_target = TARGET_BITMAP or
        su5_target = TARGET_SPRITES or su5_target = TARGET_TILES or
        su5_target = TARGET_PALETTE or su5_target = TARGET_WORKRAM) else '0';
    -- Pending writes retain their request even when the CPU request pulse ends.
    su24_access_address <= su24_pending_address when styp_state = STATE_WAIT_WRITE_SLOT else iu24_request_address;
    su16_access_data <= su16_pending_data when styp_state = STATE_WAIT_WRITE_SLOT else iu16_request_data;
    su2_access_bytes <= su2_pending_bytes when styp_state = STATE_WAIT_WRITE_SLOT else iu2_request_bytes;
    su5_access_target <= su5_reply_target when styp_state = STATE_WAIT_WRITE_SLOT else su5_target;
    s_access_write <= '1' when styp_state = STATE_WAIT_WRITE_SLOT else i_request_write;
    s_cpu_issue <= '1' when s_write_collision = '0' and
        ((styp_state = STATE_IDLE and i_request = '1') or styp_state = STATE_WAIT_WRITE_SLOT) else '0';
    s_bitmap_enable <= '1' when s_cpu_issue = '1' and su5_access_target = TARGET_BITMAP else '0';
    s_sprite_enable <= '1' when s_cpu_issue = '1' and su5_access_target = TARGET_SPRITES else '0';
    s_tile_enable <= '1' when s_cpu_issue = '1' and su5_access_target = TARGET_TILES else '0';
    s_palette_enable <= '1' when s_cpu_issue = '1' and su5_access_target = TARGET_PALETTE else '0';
    s_work_enable <= '1' when s_cpu_issue = '1' and su5_access_target = TARGET_WORKRAM else '0';
    s_inspect_bitmap <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_BITMAP else '0';
    s_inspect_sprite <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_SPRITES else '0';
    s_inspect_tile <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_TILES else '0';
    s_inspect_palette <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_PALETTE else '0';
    s_bitmap_view <= s_inspect_bitmap or i_bitmap_read_enable;
    s_sprite_view <= s_inspect_sprite or i_sprite_request;
    s_tile_view <= s_inspect_tile or i_tile_request;
    s_palette_view <= s_inspect_palette or i_palette_read_enable;
    s_work_view <= '1' when i_view_enable = '1' and iu5_view_target = TARGET_WORKRAM else '0';
    su15_bitmap_address <= iu15_view_word_address when s_inspect_bitmap = '1' else iu15_bitmap_word_address;
    su11_sprite_address <= iu15_view_word_address(10 downto 0) when s_inspect_sprite = '1' else iu11_sprite_word_address;
    su13_tile_address <= iu15_view_word_address(12 downto 0) when s_inspect_tile = '1' else iu13_tile_word_address;
    su10_palette_address <= iu15_view_word_address(9 downto 0) when s_inspect_palette = '1' else iu10_palette_word_address;
    ou16_bitmap_data <= su16_bitmap_view;
    ou16_palette_data <= su16_palette_view;
    ou16_sprite_data <= su16_sprite_view;
    ou16_tile_data <= su16_tile_view;

    -- Mixed-port same-word read/write values are undefined in the RAM primitive.
    -- Video/inspection reads win; CPU acknowledgment waits for a safe write slot.
    s_write_collision <= '1' when s_access_write = '1' and
        ((su5_access_target = TARGET_BITMAP and s_bitmap_view = '1' and su24_access_address(15 downto 1) = su15_bitmap_address) or
         (su5_access_target = TARGET_SPRITES and s_sprite_view = '1' and su24_access_address(11 downto 1) = su11_sprite_address) or
         (su5_access_target = TARGET_TILES and s_tile_view = '1' and su24_access_address(13 downto 1) = su13_tile_address) or
         (su5_access_target = TARGET_PALETTE and s_palette_view = '1' and su24_access_address(10 downto 1) = su10_palette_address) or
         (su5_access_target = TARGET_WORKRAM and s_work_view = '1' and su24_access_address(13 downto 1) = iu15_view_word_address(12 downto 0))) else '0';

    bitmap : entity work.rabbitpunch_ram16
        generic map (
            sint_ADDRESS_BITS => 15,
            POWER_UP_WORD => x"FFFF"
        )
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_bitmap_enable,
            i_cpu_write => s_access_write,
            iux_cpu_address => su24_access_address(15 downto 1),
            iu2_cpu_bytes => su2_access_bytes,
            iu16_cpu_data => su16_access_data,
            ou16_cpu_data => su16_bitmap_data,
            i_view_enable => s_bitmap_view,
            iux_view_address => su15_bitmap_address,
            ou16_view_data => su16_bitmap_view
        );
    sprites : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 11)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_sprite_enable,
            i_cpu_write => s_access_write,
            iux_cpu_address => su24_access_address(11 downto 1),
            iu2_cpu_bytes => su2_access_bytes,
            iu16_cpu_data => su16_access_data,
            ou16_cpu_data => su16_sprite_data,
            i_view_enable => s_sprite_view,
            iux_view_address => su11_sprite_address,
            ou16_view_data => su16_sprite_view
        );
    tiles : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 13)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_tile_enable,
            i_cpu_write => s_access_write,
            iux_cpu_address => su24_access_address(13 downto 1),
            iu2_cpu_bytes => su2_access_bytes,
            iu16_cpu_data => su16_access_data,
            ou16_cpu_data => su16_tile_data,
            i_view_enable => s_tile_view,
            iux_view_address => su13_tile_address,
            ou16_view_data => su16_tile_view
        );
    palette : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 10)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_palette_enable,
            i_cpu_write => s_access_write,
            iux_cpu_address => su24_access_address(10 downto 1),
            iu2_cpu_bytes => su2_access_bytes,
            iu16_cpu_data => su16_access_data,
            ou16_cpu_data => su16_palette_data,
            i_view_enable => s_palette_view,
            iux_view_address => su10_palette_address,
            ou16_view_data => su16_palette_view
        );
    work_ram : entity work.rabbitpunch_ram16 generic map (sint_ADDRESS_BITS => 13)
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_work_enable,
            i_cpu_write => s_access_write,
            iux_cpu_address => su24_access_address(13 downto 1),
            iu2_cpu_bytes => su2_access_bytes,
            iu16_cpu_data => su16_access_data,
            ou16_cpu_data => su16_work_data,
            i_view_enable => s_work_view,
            iux_view_address => iu15_view_word_address(12 downto 0),
            ou16_view_data => su16_work_view
        );

    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            -- Inspection may borrow a bank only after its video consumer drains.
            assert (s_inspect_bitmap /= '1' or i_bitmap_read_enable /= '1') report "Bitmap inspection overlaps video" severity failure;
            assert (s_inspect_palette /= '1' or i_palette_read_enable /= '1') report "Palette inspection overlaps video" severity failure;
            assert (s_inspect_sprite /= '1' or i_sprite_request /= '1') report "Sprite inspection overlaps video" severity failure;
            assert (s_inspect_tile /= '1' or i_tile_request /= '1') report "Tile inspection overlaps video" severity failure;
            o_response_valid <= '0';
            o_sprite_response_valid <= i_sprite_request and not s_inspect_sprite;
            o_tile_response_valid <= i_tile_request and not s_inspect_tile;
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
                        elsif (su5_target = TARGET_BITMAP or su5_target = TARGET_SPRITES or su5_target = TARGET_TILES or
                                su5_target = TARGET_PALETTE or su5_target = TARGET_WORKRAM) then
                            su5_reply_target <= su5_target;
                            s_reply_write <= i_request_write;
                            if (s_write_collision = '1') then
                                su24_pending_address <= iu24_request_address;
                                su16_pending_data <= iu16_request_data;
                                su2_pending_bytes <= iu2_request_bytes;
                                styp_state <= STATE_WAIT_WRITE_SLOT;
                            else
                                styp_state <= STATE_RAM_REPLY;
                            end if;
                        end if;
                    end if;
                when STATE_WAIT_WRITE_SLOT =>
                    if (s_write_collision = '0') then
                        styp_state <= STATE_RAM_REPLY;
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
