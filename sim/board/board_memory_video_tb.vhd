library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity board_memory_video_tb is
end entity;

architecture test of board_memory_video_tb is
    signal s_clk : std_logic := '0';
    signal s_request, s_write : std_logic := '0';
    signal su24_address : unsigned(23 downto 0) := (others => '0');
    signal su16_write_data, su16_read_data : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes : unsigned(1 downto 0) := "11";
    signal s_supported, s_response : std_logic;
    signal s_inspect : std_logic := '0';
    signal su5_inspect_target : target_t := CU5_TARGET_NONE;
    signal su15_inspect_address : unsigned(14 downto 0) := (others => '0');
    signal s_inspect_valid, s_sprite_valid, s_tile_valid : std_logic;
    signal su16_inspect_data : unsigned(15 downto 0);
    type t_addresses is array (0 to 3) of unsigned(14 downto 0);
    type t_words is array (0 to 3) of unsigned(15 downto 0);
    signal su15_video_address : t_addresses := (others => (others => '0'));
    signal su16_video_data : t_words;
    signal su4_video_enable : unsigned(3 downto 0) := "0000";
    type t_bases is array (0 to 4) of natural;
    constant C_BASES : t_bases := (16#40000#, 16#60000#, 16#80000#, 16#A0000#, 16#FC000#);
begin
    s_clk <= not s_clk after 5 ns;
    dut : entity work.rabbitpunch_board_memory
        port map (
            i_clk => s_clk,
            i_request => s_request,
            i_request_write => s_write,
            iu24_request_address => su24_address,
            iu16_request_data => su16_write_data,
            iu2_request_bytes => su2_bytes,
            o_request_supported => s_supported,
            o_response_valid => s_response,
            ou16_response_data => su16_read_data,
            o_rom_request => open,
            ou18_rom_byte_address => open,
            i_rom_response_valid => '0',
            iu16_rom_response_data => (others => '0'),
            i_view_enable => s_inspect,
            iu5_view_target => su5_inspect_target,
            iu15_view_word_address => su15_inspect_address,
            o_view_valid => s_inspect_valid,
            ou16_view_data => su16_inspect_data,
            i_bitmap_read_enable => su4_video_enable(0),
            iu15_bitmap_word_address => su15_video_address(0),
            ou16_bitmap_data => su16_video_data(0),
            i_palette_read_enable => su4_video_enable(3),
            iu10_palette_word_address => su15_video_address(3)(9 downto 0),
            ou16_palette_data => su16_video_data(3),
            i_sprite_request => su4_video_enable(1),
            iu11_sprite_word_address => su15_video_address(1)(10 downto 0),
            o_sprite_response_valid => s_sprite_valid,
            ou16_sprite_data => su16_video_data(1),
            i_tile_request => su4_video_enable(2),
            iu13_tile_word_address => su15_video_address(2)(12 downto 0),
            o_tile_response_valid => s_tile_valid,
            ou16_tile_data => su16_video_data(2)
        );
    stimulus : process
        variable vint_checks, vint_waited : natural := 0;
        variable vu16_expected : unsigned(15 downto 0);
        procedure access_memory(vint_bank, vint_word : natural; v_write : std_logic;
            vu2_lanes : unsigned(1 downto 0); vu16_data, vu16_expected : unsigned(15 downto 0)) is
            variable vint_age : natural := 0;
        begin
            wait until falling_edge(s_clk);
            s_request <= '1';
            s_write <= v_write;
            su24_address <= to_unsigned(C_BASES(vint_bank) + vint_word * 2, 24);
            su16_write_data <= vu16_data;
            su2_bytes <= vu2_lanes;
            wait until falling_edge(s_clk);
            s_request <= '0';
            while (s_response /= '1' and vint_age < 100) loop
                wait until falling_edge(s_clk);
                vint_age := vint_age + 1;
            end loop;
            assert (s_response = '1' and vint_age = 1) report "Unexpected CPU RAM response latency" severity failure;
            if (v_write = '0') then
                assert (su16_read_data = vu16_expected) report "CPU memory data mismatch" severity failure;
            end if;
            vint_checks := vint_checks + 1;
            wait until falling_edge(s_clk);
            assert (s_response = '0') report "Repeated CPU acknowledgment" severity failure;
        end procedure;
    begin
        -- Check mapped configuration-time contents before any CPU write.
        for vint_bank in 0 to 4 loop
            vu16_expected := x"0000";
            if (vint_bank = 0) then
                vu16_expected := x"FFFF";
            end if;
            for vint_word in 0 to 63 loop
                access_memory(vint_bank, vint_word, '0', "11", x"0000", vu16_expected);
            end loop;
        end loop;
        for vint_bank in 0 to 4 loop
            for vint_word in 0 to 63 loop
                access_memory(vint_bank, vint_word, '1', "11", to_unsigned(vint_bank * 4096 + vint_word, 16), x"0000");
            end loop;
        end loop;
        -- All four video banks read concurrently, independent of CPU work RAM.
        for vint_word in 0 to 63 loop
            wait until falling_edge(s_clk);
            su4_video_enable <= "1111";
            for vint_bank in 0 to 3 loop
                su15_video_address(vint_bank) <= to_unsigned(vint_word, 15);
            end loop;
            wait until rising_edge(s_clk);
            wait for 1 ns;
            for vint_bank in 0 to 3 loop
                assert (su16_video_data(vint_bank) = to_unsigned(vint_bank * 4096 + vint_word, 16))
                    report "Parallel native video read mismatch" severity failure;
                vint_checks := vint_checks + 1;
            end loop;
            assert (s_sprite_valid = '1' and s_tile_valid = '1') report "Descriptor response missing" severity failure;
        end loop;
        for vint_word in 0 to 63 loop
            access_memory(4, vint_word, '1', "11", to_unsigned(16#8000# + vint_word, 16), x"0000");
            access_memory(4, vint_word, '0', "11", x"0000", to_unsigned(16#8000# + vint_word, 16));
        end loop;
        wait until falling_edge(s_clk);
        su4_video_enable <= "0000";
        -- Same-address CPU reads remain legal. Writes wait without losing the
        -- original pulsed request, including mirrored addresses and byte lanes.
        for vint_bank in 0 to 3 loop
            for vint_lane in 1 to 3 loop
                for vint_delay in 0 to 2 loop
                    access_memory(vint_bank, 7, '1', "11", x"A55A", x"0000");
                    access_memory(vint_bank, 8, '1', "11", x"1234", x"0000");
                    wait until falling_edge(s_clk);
                    su4_video_enable(vint_bank) <= '1';
                    su15_video_address(vint_bank) <= to_unsigned(7, 15);
                    access_memory(vint_bank, 7, '0', "11", x"0000", x"A55A");
                    wait until falling_edge(s_clk);
                    s_request <= '1';
                    s_write <= '1';
                    su24_address <= to_unsigned(C_BASES(vint_bank) + 16#100000# + 14, 24);
                    su16_write_data <= x"5C39";
                    su2_bytes <= to_unsigned(vint_lane, 2);
                    wait until falling_edge(s_clk);
                    s_request <= '0';
                    -- Change all external fields while the accepted write waits.
                    su24_address <= to_unsigned(C_BASES(4), 24);
                    su16_write_data <= x"FFFF";
                    su2_bytes <= "00";
                    s_write <= '0';
                    for vint_cycle in 0 to vint_delay * 8 loop
                        wait until falling_edge(s_clk);
                        assert (s_response = '0' and su16_video_data(vint_bank) = x"A55A")
                            report "Colliding write was not held or corrupted the video read" severity failure;
                        vint_waited := vint_waited + 1;
                    end loop;
                    -- Moving the read to another word permits the held write
                    -- while keeping that bank's video port continuously active.
                    su15_video_address(vint_bank) <= to_unsigned(8, 15);
                    wait until falling_edge(s_clk);
                    assert (s_response = '0' and su16_video_data(vint_bank) = x"1234")
                        report "Unrelated video read blocked safe write or read wrong data" severity failure;
                    wait until falling_edge(s_clk);
                    assert (s_response = '1') report "Held CPU write did not complete" severity failure;
                    su15_video_address(vint_bank) <= to_unsigned(7, 15);
                    vu16_expected := x"A55A";
                    if (vint_lane mod 2 = 1) then
                        vu16_expected(7 downto 0) := x"39";
                    end if;
                    if (vint_lane >= 2) then
                        vu16_expected(15 downto 8) := x"5C";
                    end if;
                    wait until falling_edge(s_clk);
                    assert (s_response = '0' and su16_video_data(vint_bank) = vu16_expected)
                        report "Held write lost byte lanes, address or data" severity failure;
                    su4_video_enable(vint_bank) <= '0';
                    access_memory(vint_bank, 7, '0', "11", x"0000", vu16_expected);
                end loop;
            end loop;
        end loop;
        -- Inspection borrows a paused video bank and returns raw stored bytes.
        wait until falling_edge(s_clk);
        s_inspect <= '1';
        su5_inspect_target <= CU5_TARGET_WORKRAM;
        su15_inspect_address <= to_unsigned(3, 15);
        s_request <= '1';
        s_write <= '1';
        su24_address <= to_unsigned(C_BASES(4) + 6, 24);
        su16_write_data <= x"BEEF";
        su2_bytes <= "11";
        wait until falling_edge(s_clk);
        s_request <= '0';
        for vint_cycle in 1 to 5 loop
            wait until falling_edge(s_clk);
            assert (s_inspect_valid = '1' and su16_inspect_data = x"8003" and s_response = '0')
                report "Inspection collision mishandled" severity failure;
        end loop;
        s_inspect <= '0';
        wait until falling_edge(s_clk);
        wait until falling_edge(s_clk);
        assert (s_response = '1') report "Inspection blocked write after releasing port" severity failure;
        wait until falling_edge(s_clk);
        access_memory(4, 3, '0', "11", x"0000", x"BEEF");
        report "BOARD_MEMORY_VIDEO_PASS: parallel native reads, CPU traffic, mirrored byte-write collisions and raw inspection; checks=" &
            integer'image(vint_checks) & "; held_cycles=" & integer'image(vint_waited);
        std.env.finish;
        wait;
    end process;
end architecture;
