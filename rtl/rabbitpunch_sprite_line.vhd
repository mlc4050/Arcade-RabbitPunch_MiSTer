library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Two 512-entry sprite lines, never a frame. Render into one bank while the
-- other is read. Entry: occupied, behind FG, descriptor index[5:0], palette[7:0].
entity rabbitpunch_sprite_line is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_line_start : in std_logic;
        o_line_ready : out std_logic;
        i_render_bank : in std_logic;
        iu9_line_y : in unsigned(8 downto 0);
        i_line_finish : in std_logic;
        o_line_done : out std_logic;
        i_candidate_valid : in std_logic;
        o_candidate_ready : out std_logic;
        iu9_candidate_x : in unsigned(8 downto 0);
        iu6_candidate_index : in unsigned(5 downto 0);
        iu8_candidate_palette : in unsigned(7 downto 0);
        i_candidate_behind_foreground : in std_logic;
        i_view_enable : in std_logic;
        o_view_ready : out std_logic;
        i_view_bank : in std_logic;
        iu9_view_x : in unsigned(8 downto 0);
        o_view_valid : out std_logic;
        ou9_view_line_y : out unsigned(8 downto 0);
        ou16_view_entry : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_sprite_line is
    type t_state is (STATE_IDLE, STATE_CLEAR, STATE_DRAW, STATE_FINISH);
    signal styp_state : t_state := STATE_IDLE;
    type t_words is array (0 to 1) of unsigned(15 downto 0);
    type t_addresses is array (0 to 1) of unsigned(8 downto 0);
    signal su16_ram_data : t_words;
    signal su9_cpu_address, su9_read_address, su9_bank_line_y : t_addresses;
    signal su2_write_enable, su2_read_enable : unsigned(1 downto 0);
    signal su2_bank_valid : unsigned(1 downto 0) := "00";
    signal su16_write_data, su16_stored_entry, su16_commit_entry : unsigned(15 downto 0);
    signal s_render_bank, s_view_bank : std_logic := '0';
    signal s_view_ready, s_view_accept, s_view_valid : std_logic := '0';
    signal s_candidate_ready, s_candidate_accept : std_logic;
    signal su9_clear_x : unsigned(8 downto 0) := (others => '0');
    signal s_stage_valid, s_stage_behind : std_logic := '0';
    signal su9_stage_x : unsigned(8 downto 0) := (others => '0');
    signal su6_stage_index : unsigned(5 downto 0) := (others => '0');
    signal su8_stage_palette : unsigned(7 downto 0) := (others => '0');
    signal s_priority_write, s_write, s_forward_valid : std_logic := '0';
    signal su9_forward_x : unsigned(8 downto 0);
    signal su16_forward_entry : unsigned(15 downto 0);
    signal s_winner_occupied, s_winner_behind : std_logic;
    signal su6_winner_index : unsigned(5 downto 0);
    signal su8_winner_palette : unsigned(7 downto 0);

    function bank_number(i_bank : std_logic) return natural is
    begin
        if (i_bank = '1') then
            return 1;
        end if;
        return 0;
    end function;
begin
    o_line_ready <= '1' when styp_state = STATE_IDLE and i_reset = '0' else '0';
    s_candidate_ready <= '1' when styp_state = STATE_DRAW and i_line_finish = '0' and i_reset = '0' else '0';
    o_candidate_ready <= s_candidate_ready;
    s_candidate_accept <= i_candidate_valid and s_candidate_ready;
    s_view_ready <= '1' when i_reset = '0' and su2_bank_valid(bank_number(i_view_bank)) = '1' and
        (styp_state = STATE_IDLE or i_view_bank /= s_render_bank) else '0';
    o_view_ready <= s_view_ready;
    s_view_accept <= i_view_enable and s_view_ready;
    o_view_valid <= s_view_valid and not i_reset;
    ou16_view_entry <= su16_ram_data(bank_number(s_view_bank)) when s_view_valid = '1' else (others => '0');

    -- A RAM read may collide with the preceding pixel's write. Always bypass
    -- the complete just-committed entry, even if the next candidate loses.
    su16_stored_entry <= su16_forward_entry when s_forward_valid = '1' and
        su9_forward_x = su9_stage_x else su16_ram_data(bank_number(s_render_bank));
    su16_commit_entry <= s_winner_occupied & s_winner_behind & su6_winner_index & su8_winner_palette;
    s_write <= s_priority_write and s_stage_valid when
        (styp_state = STATE_DRAW or styp_state = STATE_FINISH) and i_reset = '0' else '0';

    arbitration : entity work.rabbitpunch_sprite_priority
        port map (
            i_occupied => su16_stored_entry(15),
            iu6_stored_index => su16_stored_entry(13 downto 8),
            iu8_stored_palette => su16_stored_entry(7 downto 0),
            i_stored_behind_foreground => su16_stored_entry(14),
            i_candidate_valid => s_stage_valid,
            iu6_candidate_index => su6_stage_index,
            iu8_candidate_palette => su8_stage_palette,
            i_candidate_behind_foreground => s_stage_behind,
            o_write => s_priority_write,
            o_occupied => s_winner_occupied,
            ou6_winner_index => su6_winner_index,
            ou8_winner_palette => su8_winner_palette,
            o_winner_behind_foreground => s_winner_behind
        );

    routing : process(all)
    begin
        su2_write_enable <= "00";
        su2_read_enable <= "00";
        su9_cpu_address <= (others => su9_stage_x);
        su9_read_address <= (others => iu9_view_x);
        su16_write_data <= su16_commit_entry;
        if (i_reset = '0') then
            if (styp_state = STATE_CLEAR) then
                su2_write_enable(bank_number(s_render_bank)) <= '1';
                su9_cpu_address(bank_number(s_render_bank)) <= su9_clear_x;
                su16_write_data <= (others => '0');
            elsif (s_write = '1') then
                su2_write_enable(bank_number(s_render_bank)) <= '1';
            end if;
            if (s_view_accept = '1') then
                su2_read_enable(bank_number(i_view_bank)) <= '1';
            end if;
            if (s_candidate_accept = '1') then
                -- The bypass supplies this entry; suppress the conflicting
                -- physical read instead of depending on mixed-port RAM data.
                if (not (s_write = '1' and su9_stage_x = iu9_candidate_x)) then
                    su2_read_enable(bank_number(s_render_bank)) <= '1';
                end if;
                su9_read_address(bank_number(s_render_bank)) <= iu9_candidate_x;
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
                iux_cpu_address => su9_cpu_address(vint_bank),
                iu2_cpu_bytes => "11",
                iu16_cpu_data => su16_write_data,
                ou16_cpu_data => open,
                i_view_enable => su2_read_enable(vint_bank),
                iux_view_address => su9_read_address(vint_bank),
                ou16_view_data => su16_ram_data(vint_bank)
            );
    end generate;

    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_line_done <= '0';
            s_view_valid <= s_view_accept;
            if (s_view_accept = '1') then
                s_view_bank <= i_view_bank;
                ou9_view_line_y <= su9_bank_line_y(bank_number(i_view_bank));
            end if;
            s_stage_valid <= s_candidate_accept;
            if (s_candidate_accept = '1') then
                su9_stage_x <= iu9_candidate_x;
                su6_stage_index <= iu6_candidate_index;
                su8_stage_palette <= iu8_candidate_palette;
                s_stage_behind <= i_candidate_behind_foreground;
            end if;
            s_forward_valid <= s_write;
            if (s_write = '1') then
                su9_forward_x <= su9_stage_x;
                su16_forward_entry <= su16_commit_entry;
            end if;
            if (i_reset = '1') then
                styp_state <= STATE_IDLE;
                su2_bank_valid <= "00";
                s_stage_valid <= '0';
                s_forward_valid <= '0';
                s_view_valid <= '0';
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_line_start = '1') then
                            s_render_bank <= i_render_bank;
                            su2_bank_valid(bank_number(i_render_bank)) <= '0';
                            su9_bank_line_y(bank_number(i_render_bank)) <= iu9_line_y;
                            su9_clear_x <= (others => '0');
                            styp_state <= STATE_CLEAR;
                        end if;
                    when STATE_CLEAR =>
                        if (su9_clear_x = 511) then
                            styp_state <= STATE_DRAW;
                        else
                            su9_clear_x <= su9_clear_x + 1;
                        end if;
                    when STATE_DRAW =>
                        if (i_line_finish = '1') then
                            styp_state <= STATE_FINISH;
                        end if;
                    when STATE_FINISH =>
                        if (s_stage_valid = '0') then
                            su2_bank_valid(bank_number(s_render_bank)) <= '1';
                            o_line_done <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
