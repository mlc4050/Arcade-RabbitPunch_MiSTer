library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Build both tile layers into one packed 512-pixel line, alternating banks.
-- BG0 occupies the low byte and FG the high byte. Both bytes are filled before
-- the line becomes readable, so no startup contents or bulk clear are needed.
entity rabbitpunch_tiles is
    generic (
        GINT_FIRST_PIXEL : natural := 0;
        GINT_LAST_PIXEL : natural := 511
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_line_valid : in std_logic;
        o_line_ready : out std_logic;
        i_render_bank : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        iu9_background_scroll_x : in unsigned(8 downto 0);
        iu9_background_scroll_y : in unsigned(8 downto 0);
        iu9_foreground_scroll_x : in unsigned(8 downto 0);
        iu9_foreground_scroll_y : in unsigned(8 downto 0);
        iu16_video_flags : in unsigned(15 downto 0);
        o_line_done : out std_logic;
        o_ram_request : out std_logic;
        ou13_ram_word_address : out unsigned(12 downto 0);
        i_ram_response_valid : in std_logic;
        iu16_ram_response_data : in unsigned(15 downto 0);
        o_rom_request : out std_logic;
        ou17_rom_word_address : out unsigned(16 downto 0);
        o_rom_foreground : out std_logic;
        i_rom_response_valid : in std_logic;
        iu32_rom_response_data : in unsigned(31 downto 0);
        i_view_enable : in std_logic;
        o_view_ready : out std_logic;
        i_view_bank : in std_logic;
        iu9_view_x : in unsigned(8 downto 0);
        o_view_valid : out std_logic;
        ou9_view_line_y : out unsigned(8 downto 0);
        ou16_view_pixels : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_tiles is
    type t_state is (STATE_IDLE, STATE_DRAW);
    signal styp_state : t_state := STATE_IDLE;
    type t_addresses is array (0 to 1) of unsigned(8 downto 0);
    type t_words is array (0 to 1) of unsigned(15 downto 0);
    signal su9_scroll_x, su9_scroll_y, su9_bank_y : t_addresses;
    signal su16_read_data : t_words;
    signal su9_line_y, su9_next_x, su9_pixel_x, su9_pixel_y : unsigned(8 downto 0);
    signal su9_palette_index : unsigned(8 downto 0);
    signal su16_flags, su16_write_data : unsigned(15 downto 0);
    signal s_render_bank, s_foreground, s_requests_done : std_logic := '0';
    signal s_request_valid, s_request_ready, s_pixel_valid : std_logic;
    signal su7_rows_issued : unsigned(6 downto 0) := (others => '0');
    signal su10_pixels_written : unsigned(9 downto 0) := (others => '0');
    signal su2_write_enable, su2_read_enable, su2_byte_enable : unsigned(1 downto 0);
    signal su2_bank_valid : unsigned(1 downto 0) := "00";
    signal s_view_ready, s_view_accept, s_view_valid, s_view_bank : std_logic := '0';
    signal s_ram_request, s_rom_request : std_logic;
    signal s_ram_pending, s_rom_pending : std_logic := '0';
    function bank_number(i_bank : std_logic) return natural is
    begin
        if (i_bank = '1') then
            return 1;
        end if;
        return 0;
    end function;
begin
    assert (GINT_FIRST_PIXEL <= GINT_LAST_PIXEL and GINT_LAST_PIXEL < 512)
        report "Tile line window must be within logical X 0..511" severity failure;
    o_line_ready <= '1' when styp_state = STATE_IDLE and s_request_ready = '1' and
        s_ram_pending = '0' and s_rom_pending = '0' and i_reset = '0' else '0';
    o_ram_request <= s_ram_request;
    o_rom_request <= s_rom_request;
    s_request_valid <= '1' when styp_state = STATE_DRAW and s_requests_done = '0' and i_reset = '0' else '0';
    s_view_ready <= '1' when i_reset = '0' and su2_bank_valid(bank_number(i_view_bank)) = '1' and
        iu9_view_x >= GINT_FIRST_PIXEL and iu9_view_x <= GINT_LAST_PIXEL and
        (styp_state = STATE_IDLE or i_view_bank /= s_render_bank) else '0';
    o_view_ready <= s_view_ready;
    s_view_accept <= i_view_enable and s_view_ready;
    o_view_valid <= s_view_valid and not i_reset;
    ou16_view_pixels <= su16_read_data(bank_number(s_view_bank)) when s_view_valid = '1' else (others => '0');
    su16_write_data <= su9_palette_index(7 downto 0) & su9_palette_index(7 downto 0);
    su2_byte_enable <= "10" when su9_palette_index(8) = '1' else "01";

    layer : entity work.rabbitpunch_tile_layer
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_request_valid => s_request_valid,
            o_request_ready => s_request_ready,
            iu9_pixel_x => su9_next_x,
            iu9_pixel_y => su9_line_y,
            iu9_scroll_x => su9_scroll_x(bank_number(s_foreground)),
            iu9_scroll_y => su9_scroll_y(bank_number(s_foreground)),
            iu16_video_flags => su16_flags,
            i_foreground => s_foreground,
            o_ram_request => s_ram_request,
            ou13_ram_word_address => ou13_ram_word_address,
            i_ram_response_valid => i_ram_response_valid,
            iu16_ram_response_data => iu16_ram_response_data,
            o_rom_request => s_rom_request,
            ou17_rom_word_address => ou17_rom_word_address,
            o_rom_foreground => o_rom_foreground,
            i_rom_response_valid => i_rom_response_valid,
            iu32_rom_response_data => iu32_rom_response_data,
            o_pixel_valid => s_pixel_valid,
            ou9_pixel_x => su9_pixel_x,
            ou9_pixel_y => su9_pixel_y,
            ou9_palette_index => su9_palette_index,
            o_opaque => open
        );
    routing : process(all)
    begin
        su2_write_enable <= "00";
        su2_read_enable <= "00";
        if (i_reset = '0') then
            if (styp_state = STATE_DRAW and s_pixel_valid = '1') then
                su2_write_enable(bank_number(s_render_bank)) <= '1';
            end if;
            if (s_view_accept = '1') then
                su2_read_enable(bank_number(i_view_bank)) <= '1';
            end if;
        end if;
    end process;
    banks : for vint_bank in 0 to 1 generate
        line_ram : entity work.rabbitpunch_ram16
            generic map (GINT_ADDRESS_BITS => 9)
            port map (
                i_clk => i_clk,
                i_cpu_enable => su2_write_enable(vint_bank),
                i_cpu_write => '1',
                iux_cpu_address => su9_pixel_x,
                iu2_cpu_bytes => su2_byte_enable,
                iu16_cpu_data => su16_write_data,
                ou16_cpu_data => open,
                i_view_enable => su2_read_enable(vint_bank),
                iux_view_address => iu9_view_x,
                ou16_view_data => su16_read_data(vint_bank)
            );
    end generate;

    process(i_clk)
        variable vu9_source_x : unsigned(8 downto 0);
        variable vu10_next_x : unsigned(9 downto 0);
    begin
        if (rising_edge(i_clk)) then
            -- Reset does not cancel an accepted external transaction.
            if (s_ram_request = '1') then
                s_ram_pending <= '1';
            elsif (i_ram_response_valid = '1') then
                s_ram_pending <= '0';
            end if;
            if (s_rom_request = '1') then
                s_rom_pending <= '1';
            elsif (i_rom_response_valid = '1') then
                s_rom_pending <= '0';
            end if;
            o_line_done <= '0';
            s_view_valid <= s_view_accept;
            if (s_view_accept = '1') then
                s_view_bank <= i_view_bank;
                ou9_view_line_y <= su9_bank_y(bank_number(i_view_bank));
            end if;
            if (i_reset = '1') then
                styp_state <= STATE_IDLE;
                su2_bank_valid <= "00";
                s_view_valid <= '0';
                s_requests_done <= '0';
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_line_valid = '1' and s_request_ready = '1' and
                            s_ram_pending = '0' and s_rom_pending = '0') then
                            s_render_bank <= i_render_bank;
                            su9_line_y <= iu9_line_y;
                            su9_bank_y(bank_number(i_render_bank)) <= iu9_line_y;
                            su2_bank_valid(bank_number(i_render_bank)) <= '0';
                            su9_scroll_x(0) <= iu9_background_scroll_x;
                            su9_scroll_y(0) <= iu9_background_scroll_y;
                            su9_scroll_x(1) <= iu9_foreground_scroll_x;
                            su9_scroll_y(1) <= iu9_foreground_scroll_y;
                            su16_flags <= iu16_video_flags;
                            s_foreground <= '0';
                            s_requests_done <= '0';
                            su9_next_x <= to_unsigned(GINT_FIRST_PIXEL, 9);
                            su7_rows_issued <= (others => '0');
                            su10_pixels_written <= (others => '0');
                            styp_state <= STATE_DRAW;
                        end if;
                    when STATE_DRAW =>
                        if (s_request_valid = '1' and s_request_ready = '1') then
                            vu9_source_x := su9_next_x + su9_scroll_x(bank_number(s_foreground));
                            vu10_next_x := ('0' & su9_next_x) + 8 - resize(vu9_source_x(2 downto 0), 10);
                            su9_next_x <= vu10_next_x(8 downto 0);
                            su7_rows_issued <= su7_rows_issued + 1;
                            if (vu10_next_x > GINT_LAST_PIXEL) then
                                s_requests_done <= '1';
                            end if;
                        end if;
                        if (s_pixel_valid = '1') then
                            su10_pixels_written <= su10_pixels_written + 1;
                        end if;
                        if (s_requests_done = '1' and su10_pixels_written = (su7_rows_issued & "000")) then
                            if (s_foreground = '0') then
                                s_foreground <= '1';
                                s_requests_done <= '0';
                                su9_next_x <= to_unsigned(GINT_FIRST_PIXEL, 9);
                                su7_rows_issued <= (others => '0');
                                su10_pixels_written <= (others => '0');
                            else
                                su2_bank_valid(bank_number(s_render_bank)) <= '1';
                                o_line_done <= '1';
                                styp_state <= STATE_IDLE;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
