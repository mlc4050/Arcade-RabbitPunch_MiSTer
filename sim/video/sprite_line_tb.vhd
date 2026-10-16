library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity sprite_line_tb is
end entity;

architecture test of sprite_line_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_start, s_finish, s_bank, s_valid, s_behind : std_logic := '0';
    signal s_ready, s_candidate_ready, s_done : std_logic;
    signal su9_y, su9_x : unsigned(8 downto 0) := (others => '0');
    signal su6_index : unsigned(5 downto 0) := (others => '0');
    signal su8_palette : unsigned(7 downto 0) := (others => '0');
    signal s_view_enable, s_view_bank : std_logic := '0';
    signal s_view_ready, s_view_valid : std_logic;
    signal su9_view_x : unsigned(8 downto 0) := (others => '0');
    signal su9_view_y : unsigned(8 downto 0);
    signal su16_view_entry : unsigned(15 downto 0);
    type t_entries is array (0 to 1023) of unsigned(15 downto 0);
    type t_line_tags is array (0 to 1) of unsigned(8 downto 0);
    signal su16_expected : t_entries := (others => (others => '0'));
    signal su9_expected_y : t_line_tags := (others => (others => '0'));
    signal sint_view_checks : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_sprite_line
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_line_start => s_start,
            o_line_ready => s_ready,
            i_render_bank => s_bank,
            iu9_line_y => su9_y,
            i_line_finish => s_finish,
            o_line_done => s_done,
            i_candidate_valid => s_valid,
            o_candidate_ready => s_candidate_ready,
            iu9_candidate_x => su9_x,
            iu6_candidate_index => su6_index,
            iu8_candidate_palette => su8_palette,
            i_candidate_behind_foreground => s_behind,
            i_view_enable => s_view_enable,
            o_view_ready => s_view_ready,
            i_view_bank => s_view_bank,
            iu9_view_x => su9_view_x,
            o_view_valid => s_view_valid,
            ou9_view_line_y => su9_view_y,
            ou16_view_entry => su16_view_entry
        );

    display_address : process(s_clk)
    begin
        if (falling_edge(s_clk)) then
            su9_view_x <= su9_view_x + 1;
        end if;
    end process;

    display_check : process(s_clk)
        variable vint_address, vint_bank : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_reset = '0') then
                if (s_view_valid = '1') then
                    assert (su16_view_entry = su16_expected(vint_bank * 512 + vint_address))
                        report "Sprite line RAM pixel mismatch at bank " & integer'image(vint_bank) &
                            " x=" & integer'image(vint_address) severity failure;
                    assert (su9_view_y = su9_expected_y(vint_bank)) report "Sprite line tag mismatch" severity failure;
                    sint_view_checks <= sint_view_checks + 1;
                end if;
                if (s_view_enable = '1' and s_view_ready = '1') then
                    vint_address := to_integer(su9_view_x);
                    vint_bank := 0;
                    if (s_view_bank = '1') then
                        vint_bank := 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    stimulus : process
        variable vint_bank, vint_seed, vint_before_checks : natural := 0;
        variable vint_candidates : natural := 0;
        procedure begin_line(vint_bank_number, vint_y : natural) is
            variable vint_clear_cycles : natural := 0;
        begin
            wait until falling_edge(s_clk) and s_ready = '1';
            vint_bank := vint_bank_number;
            s_bank <= bit_value(vint_bank_number);
            su9_y <= to_unsigned(vint_y, 9);
            su9_expected_y(vint_bank_number) <= to_unsigned(vint_y, 9);
            for vint_x in 0 to 511 loop
                su16_expected(vint_bank_number * 512 + vint_x) <= (others => '0');
            end loop;
            s_start <= '1';
            wait until falling_edge(s_clk);
            s_start <= '0';
            s_bank <= not bit_value(vint_bank_number);
            su9_y <= not to_unsigned(vint_y, 9);
            while (s_candidate_ready /= '1') loop
                wait until falling_edge(s_clk);
                vint_clear_cycles := vint_clear_cycles + 1;
            end loop;
            assert (vint_clear_cycles = 512) report "Sprite line clear was not 512 clocks" severity failure;
        end procedure;
        procedure candidate(vint_x, vint_index, vint_palette, vint_behind : natural) is
            variable vu16_old : unsigned(15 downto 0);
        begin
            wait until falling_edge(s_clk) and s_candidate_ready = '1';
            su9_x <= to_unsigned(vint_x, 9);
            su6_index <= to_unsigned(vint_index, 6);
            su8_palette <= to_unsigned(vint_palette, 8);
            s_behind <= bit_value(vint_behind);
            s_valid <= '1';
            vu16_old := su16_expected(vint_bank * 512 + vint_x);
            if (vint_palette mod 16 /= 15) then
                if (vu16_old(15) = '0' or vint_index > to_integer(vu16_old(13 downto 8))) then
                    su16_expected(vint_bank * 512 + vint_x) <=
                        '1' & bit_value(vint_behind) & to_unsigned(vint_index, 6) & to_unsigned(vint_palette, 8);
                end if;
            end if;
            vint_candidates := vint_candidates + 1;
        end procedure;
        procedure finish_line is
        begin
            wait until falling_edge(s_clk);
            s_valid <= '0';
            s_finish <= '1';
            wait until falling_edge(s_clk);
            s_finish <= '0';
            wait until falling_edge(s_clk) and s_done = '1';
            assert (s_ready = '1' and s_candidate_ready = '0') report "Line completion did not drain pipeline" severity failure;
            s_view_bank <= bit_value(vint_bank);
            s_view_enable <= '1';
            vint_before_checks := sint_view_checks;
            wait until falling_edge(s_clk) and sint_view_checks >= vint_before_checks + 1024;
        end procedure;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        wait until falling_edge(s_clk);
        assert (s_view_ready = '0') report "Uninitialized bank exposed after reset" severity failure;
        for vint_line in 0 to 5 loop
            begin_line(vint_line mod 2, (vint_line * 137) mod 512);
            for vint_x in 0 to 511 loop
                candidate(vint_x, 1, vint_x mod 256, vint_x mod 2);
            end loop;
            -- Continuous same-address updates: both wins and losses must bypass
            -- a simultaneous physical RAM write, including pen-15 candidates.
            for vint_index in 0 to 63 loop
                candidate(17, vint_index, (vint_index * 7) mod 256, vint_index mod 2);
            end loop;
            for vint_index in 63 downto 0 loop
                candidate(17, vint_index, (vint_index * 11) mod 256, (vint_index + 1) mod 2);
            end loop;
            for vint_random in 1 to 5000 loop
                vint_seed := (vint_seed * 25173 + 13849) mod 65536;
                candidate(vint_seed mod 512, (vint_seed / 512) mod 64,
                    (vint_seed / 64) mod 256, vint_seed mod 2);
            end loop;
            finish_line;
        end loop;

        -- Abort a clear, then an in-flight read/modify/write. Both banks must
        -- become unavailable until a complete new line has been committed.
        s_view_enable <= '0';
        wait until falling_edge(s_clk);
        s_start <= '1';
        s_bank <= '0';
        wait until falling_edge(s_clk);
        s_start <= '0';
        for vint_cycle in 1 to 10 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '1';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        wait until falling_edge(s_clk);
        assert (s_view_ready = '0') report "Reset retained bank validity" severity failure;
        begin_line(0, 511);
        candidate(511, 62, 16#E7#, 1);
        wait until falling_edge(s_clk);
        s_valid <= '0';
        s_reset <= '1';
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        begin_line(0, 0);
        candidate(511, 2, 16#A5#, 0);
        candidate(511, 1, 16#B6#, 1);
        candidate(511, 3, 16#FF#, 1);
        finish_line;
        report "SPRITE_LINE_PASS: " & integer'image(vint_candidates) &
            " candidates; " & integer'image(sint_view_checks) &
            " display reads; native RAM, clearing, collision bypass, bank reuse and reset";
        std.env.finish;
        wait;
    end process;
end architecture;
