library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tile_test_support.all;

entity sprite_renderer_tb is
end entity;

architecture test of sprite_renderer_tb is
    constant C_COUNTS : t_unsigned_words := read_hex("counts.hex", 3, 32);
    constant C_LINES : t_unsigned_words := read_hex("lines.hex", to_integer(C_COUNTS(0)), 64);
    constant C_OFFSETS : t_unsigned_words := read_hex("offsets.hex", C_LINES'length, 64);
    constant C_ADDRESSES : t_unsigned_words := read_hex("addresses.hex", to_integer(C_COUNTS(2)), 11);
    constant C_ENTRIES : t_unsigned_words := read_hex("line_entries.hex", C_LINES'length * 512, 16);
    constant C_RAM : t_unsigned_words := read_hex("ram.hex", 2048, 16);
    constant C_ROM : t_unsigned_words := read_hex("sprites.hex", 131072, 32);
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_valid, s_bank, s_begin_line, s_checking : std_logic := '0';
    signal s_ready, s_done, s_ram_request, s_rom_request : std_logic;
    signal su9_y : unsigned(8 downto 0) := (others => '0');
    signal su6_count, su6_priority : unsigned(5 downto 0) := (others => '0');
    signal su16_flags, su16_ram_data : unsigned(15 downto 0) := (others => '0');
    signal su11_ram_address : unsigned(10 downto 0);
    signal su17_rom_address : unsigned(16 downto 0);
    signal su32_rom_data : unsigned(31 downto 0) := (others => '0');
    signal s_ram_valid, s_rom_valid, s_ram_pending, s_rom_pending : std_logic := '0';
    signal s_view_enable, s_view_ready, s_view_valid : std_logic := '0';
    signal su9_view_x : unsigned(8 downto 0) := (others => '0');
    signal su9_view_y : unsigned(8 downto 0);
    signal su16_view_entry : unsigned(15 downto 0);
    signal sint_case, sint_view_case, sint_view_checks, sint_ram_requests, sint_rom_requests : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_sprites
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_line_valid => s_valid,
            o_line_ready => s_ready,
            i_render_bank => s_bank,
            iu9_line_y => su9_y,
            iu6_sprite_count => su6_count,
            iu6_sprite_priority => su6_priority,
            iu16_video_flags => su16_flags,
            o_line_done => s_done,
            o_ram_request => s_ram_request,
            ou11_ram_word_address => su11_ram_address,
            i_ram_response_valid => s_ram_valid,
            iu16_ram_response_data => su16_ram_data,
            o_rom_request => s_rom_request,
            ou17_rom_word_address => su17_rom_address,
            i_rom_response_valid => s_rom_valid,
            iu32_rom_response_data => su32_rom_data,
            i_view_enable => s_view_enable,
            o_view_ready => s_view_ready,
            i_view_bank => bit_value(sint_view_case mod 2),
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
    responder : process(s_clk)
        variable vint_ram_delay, vint_rom_delay, vint_ram_requests, vint_rom_requests : natural := 0;
        variable vu11_saved_ram : unsigned(10 downto 0);
        variable vu17_saved_rom : unsigned(16 downto 0);
        variable vint_view_x, vint_view_case, vint_offset : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_begin_line = '1') then
                vint_ram_requests := 0;
                vint_rom_requests := 0;
            end if;
            s_ram_valid <= '0';
            if (s_ram_request = '1') then
                assert (s_ram_pending = '0') report "Renderer overlaps descriptor requests" severity failure;
                if (s_checking = '1') then
                    vint_offset := to_integer(C_OFFSETS(sint_case)(63 downto 32));
                    assert (su11_ram_address = C_ADDRESSES(vint_offset + vint_ram_requests))
                        report "Renderer descriptor order mismatch" severity failure;
                end if;
                vint_ram_requests := vint_ram_requests + 1;
                vu11_saved_ram := su11_ram_address;
                vint_ram_delay := delay_cycles(to_integer(su11_ram_address));
                s_ram_pending <= '1';
            elsif (s_ram_pending = '1') then
                if (vint_ram_delay = 0) then
                    s_ram_pending <= '0';
                    s_ram_valid <= '1';
                    su16_ram_data <= C_RAM(to_integer(vu11_saved_ram));
                else
                    vint_ram_delay := vint_ram_delay - 1;
                end if;
            end if;
            s_rom_valid <= '0';
            if (s_rom_request = '1') then
                assert (s_rom_pending = '0') report "Renderer overlaps graphics requests" severity failure;
                vint_rom_requests := vint_rom_requests + 1;
                vu17_saved_rom := su17_rom_address;
                vint_rom_delay := delay_cycles(to_integer(su17_rom_address));
                s_rom_pending <= '1';
            elsif (s_rom_pending = '1') then
                if (vint_rom_delay = 0) then
                    s_rom_pending <= '0';
                    s_rom_valid <= '1';
                    su32_rom_data <= C_ROM(to_integer(vu17_saved_rom));
                else
                    vint_rom_delay := vint_rom_delay - 1;
                end if;
            end if;
            if (s_view_valid = '1' and s_reset = '0') then
                assert (su16_view_entry = C_ENTRIES(vint_view_case * 512 + vint_view_x))
                    report "Renderer line entry mismatch at case " & integer'image(vint_view_case) &
                        " x=" & integer'image(vint_view_x) severity failure;
                assert (su9_view_y = C_LINES(vint_view_case)(8 downto 0))
                    report "Renderer line tag mismatch" severity failure;
                sint_view_checks <= sint_view_checks + 1;
            end if;
            if (s_view_enable = '1' and s_view_ready = '1') then
                vint_view_x := to_integer(su9_view_x);
                vint_view_case := sint_view_case;
            end if;
            sint_ram_requests <= vint_ram_requests;
            sint_rom_requests <= vint_rom_requests;
        end if;
    end process;

    stimulus : process
        variable vint_max_cycles, vint_trials : natural := 0;
        procedure begin_line(vint_case : natural) is
            variable vu64_line : unsigned(63 downto 0);
        begin
            wait until falling_edge(s_clk) and s_ready = '1';
            vu64_line := C_LINES(vint_case);
            sint_case <= vint_case;
            s_bank <= bit_value(vint_case mod 2);
            su9_y <= vu64_line(8 downto 0);
            su6_count <= vu64_line(14 downto 9);
            su6_priority <= vu64_line(20 downto 15);
            su16_flags <= vu64_line(36 downto 21);
            s_begin_line <= '1';
            s_checking <= '1';
            s_valid <= '1';
            wait until falling_edge(s_clk);
            s_valid <= '0';
            s_begin_line <= '0';
            s_bank <= not bit_value(vint_case mod 2);
            su9_y <= not vu64_line(8 downto 0);
            su6_count <= not vu64_line(14 downto 9);
            su6_priority <= not vu64_line(20 downto 15);
            su16_flags <= not vu64_line(36 downto 21);
        end procedure;
        procedure trial(vint_case : natural) is
            variable vint_cycles, vint_row_end, vint_address_end, vint_before_checks : natural := 0;
        begin
            begin_line(vint_case);
            while (s_done /= '1') loop
                wait until falling_edge(s_clk);
                vint_cycles := vint_cycles + 1;
            end loop;
            assert (s_ready = '1' and s_ram_pending = '0' and s_rom_pending = '0')
                report "Renderer completed before draining work" severity failure;
            vint_row_end := to_integer(C_COUNTS(1));
            vint_address_end := C_ADDRESSES'length;
            if (vint_case < C_LINES'high) then
                vint_row_end := to_integer(C_OFFSETS(vint_case + 1)(31 downto 0));
                vint_address_end := to_integer(C_OFFSETS(vint_case + 1)(63 downto 32));
            end if;
            assert (sint_ram_requests = vint_address_end - to_integer(C_OFFSETS(vint_case)(63 downto 32)) and
                sint_rom_requests = 2 * (vint_row_end - to_integer(C_OFFSETS(vint_case)(31 downto 0))))
                report "Renderer transaction count mismatch" severity failure;
            if (vint_cycles > vint_max_cycles) then
                vint_max_cycles := vint_cycles;
            end if;
            sint_view_case <= vint_case;
            s_view_enable <= '1';
            vint_before_checks := sint_view_checks;
            wait until falling_edge(s_clk) and sint_view_checks >= vint_before_checks + 1024;
            s_checking <= '0';
            vint_trials := vint_trials + 1;
        end procedure;
        procedure reset_and_drain is
        begin
            s_reset <= '1';
            s_checking <= '0';
            s_view_enable <= '0';
            for vint_cycle in 1 to 3 loop
                wait until falling_edge(s_clk);
            end loop;
            s_reset <= '0';
            wait until falling_edge(s_clk) and s_ready = '1';
            assert (s_ram_pending = '0' and s_rom_pending = '0' and s_view_ready = '0')
                report "Renderer reset left pending work or exposed stale bank" severity failure;
        end procedure;
    begin
        for vint_cycle in 1 to 3 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        for vint_case in C_LINES'range loop
            trial(vint_case);
        end loop;
        for vint_abort in 0 to 2 loop
            s_view_enable <= '0';
            for vint_cycle in 1 to 2 loop
                wait until falling_edge(s_clk);
            end loop;
            begin_line(0);
            if (vint_abort = 0) then
                wait until falling_edge(s_clk) and s_ram_pending = '1';
            elsif (vint_abort = 1) then
                wait until falling_edge(s_clk) and s_rom_pending = '1';
            else
                wait until falling_edge(s_clk) and s_rom_pending = '1' and sint_rom_requests = 2;
            end if;
            reset_and_drain;
            trial(0);
        end loop;
        report "SPRITE_RENDERER_PASS: " & integer'image(vint_trials) &
            " scans; max_cycles=" & integer'image(vint_max_cycles) & "; concurrent native readout and whole-renderer reset";
        std.env.finish;
        wait;
    end process;
end architecture;
