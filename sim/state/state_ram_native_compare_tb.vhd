-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual adapter and paired native/model RAM endpoints; no CPU/chip substitution.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.rabbitpunch_layout.all;
entity state_ram_native_compare_tb is
end entity;
architecture test of state_ram_native_compare_tb is
    type t_flags is array(0 to 1) of std_logic;
    type t_words is array(0 to 1) of unsigned(15 downto 0);
    type t_bytes is array(0 to 1) of unsigned(7 downto 0);
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_session, s_drained, s_byte_valid, s_byte_write : std_logic := '0';
    signal s_byte_ready, s_byte_response, s_byte_error, s_pause, s_idle : std_logic;
    signal su17_byte_address : unsigned(16 downto 0) := (others => '0');
    signal su8_byte_write_data : unsigned(7 downto 0) := (others => '0');
    signal su8_byte_read_data : unsigned(7 downto 0);
    signal s_main_request, s_main_write, s_sound_request, s_sound_write : std_logic;
    signal su24_main_address : unsigned(23 downto 0);
    signal su16_main_write_data, su16_sound_address : unsigned(15 downto 0);
    signal su16_sound_bus_address : unsigned(15 downto 0);
    signal su2_main_bytes : unsigned(1 downto 0);
    signal su8_sound_write_data : unsigned(7 downto 0);
    signal s_supported, s_main_response, s_sound_response : t_flags;
    signal s_rom_request, s_sound_rom_request : t_flags;
    signal su16_main_data : t_words;
    signal su8_sound_data : t_bytes;
    signal s_main_credit, s_sound_credit : std_logic := '0';
    signal su16_main_credit_data : unsigned(15 downto 0) := (others => '0');
    signal su8_sound_credit_data : unsigned(7 downto 0) := (others => '0');
    signal sint_main_delay, sint_sound_delay : natural range 0 to 8 := 0;
    function F_PATTERN(vint_address, vint_epoch : natural) return unsigned is
    begin
        if (vint_epoch = 0) then
            if (vint_address < 65536) then
                return to_unsigned(255, 8);
            end if;
            return to_unsigned(0, 8);
        end if;
        return to_unsigned((vint_address * 37 + vint_address / 256 + vint_epoch * 83) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    su16_sound_bus_address <= su16_sound_address when s_sound_request = '1' else x"F800";
    adapter : entity work.rabbitpunch_state_memory
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_session => s_session,
            i_drained => s_drained,
            o_pause => s_pause,
            o_idle => s_idle,
            i_byte_valid => s_byte_valid,
            o_byte_ready => s_byte_ready,
            i_byte_write => s_byte_write,
            iu17_byte_address => su17_byte_address,
            iu8_byte_data => su8_byte_write_data,
            o_byte_response => s_byte_response,
            o_byte_error => s_byte_error,
            ou8_byte_data => su8_byte_read_data,
            o_main_request => s_main_request,
            o_main_write => s_main_write,
            ou24_main_address => su24_main_address,
            ou16_main_data => su16_main_write_data,
            ou2_main_bytes => su2_main_bytes,
            i_main_response => s_main_credit,
            iu16_main_data => su16_main_credit_data,
            o_sound_request => s_sound_request,
            o_sound_write => s_sound_write,
            ou16_sound_address => su16_sound_address,
            ou8_sound_data => su8_sound_write_data,
            i_sound_response => s_sound_credit,
            iu8_sound_data => su8_sound_credit_data
        );
    side0 : if (true) generate
        constant CINT_SIDE : natural := 0;
    begin
        main_ram : entity work.rabbitpunch_board_memory
            port map (
                i_clk => s_clk,
                i_request => s_main_request,
                i_request_write => s_main_write,
                iu24_request_address => su24_main_address,
                iu16_request_data => su16_main_write_data,
                iu2_request_bytes => su2_main_bytes,
                o_request_supported => s_supported(CINT_SIDE),
                o_response_valid => s_main_response(CINT_SIDE),
                ou16_response_data => su16_main_data(CINT_SIDE),
                o_rom_request => s_rom_request(CINT_SIDE),
                ou18_rom_byte_address => open,
                i_rom_response_valid => '0',
                iu16_rom_response_data => (others => '0'),
                i_view_enable => '0',
                iu5_view_target => CU5_TARGET_NONE,
                iu15_view_word_address => (others => '0'),
                o_view_valid => open,
                ou16_view_data => open,
                i_bitmap_read_enable => '0',
                iu15_bitmap_word_address => (others => '0'),
                ou16_bitmap_data => open,
                i_palette_read_enable => '0',
                iu10_palette_word_address => (others => '0'),
                ou16_palette_data => open,
                i_sprite_request => '0',
                iu11_sprite_word_address => (others => '0'),
                o_sprite_response_valid => open,
                ou16_sprite_data => open,
                i_tile_request => '0',
                iu13_tile_word_address => (others => '0'),
                o_tile_response_valid => open,
                ou16_tile_data => open
            );
        sound_ram : entity work.rabbitpunch_sound_bus
            port map (
                i_clk => s_clk,
                i_request => s_sound_request,
                i_request_write => s_sound_write,
                iu16_request_address => su16_sound_bus_address,
                iu8_request_data => su8_sound_write_data,
                o_response_valid => s_sound_response(CINT_SIDE),
                ou8_response_data => su8_sound_data(CINT_SIDE),
                o_rom_request => s_sound_rom_request(CINT_SIDE),
                ou16_rom_address => open,
                i_rom_ready => '0',
                i_rom_response_valid => '0',
                iu8_rom_response_data => (others => '0'),
                i_ym_write_enable => '0',
                iu8_ym_status => (others => '0'),
                o_ym_write => open,
                o_ym_data_register => open,
                ou8_ym_write_data => open,
                iu8_command => (others => '0'),
                o_command_read => open,
                o_adpcm_control_write => open,
                o_adpcm_command_write => open,
                ou8_adpcm_data => open,
                i_view_enable => '0',
                iu11_view_address => (others => '0'),
                ou8_view_data => open,
                o_idle => open
            );
    end generate;
    side1 : if (true) generate
        constant CINT_SIDE : natural := 1;
    begin
        main_ram : entity work.rabbitpunch_board_memory_model
            port map (
                i_clk => s_clk,
                i_request => s_main_request,
                i_request_write => s_main_write,
                iu24_request_address => su24_main_address,
                iu16_request_data => su16_main_write_data,
                iu2_request_bytes => su2_main_bytes,
                o_request_supported => s_supported(CINT_SIDE),
                o_response_valid => s_main_response(CINT_SIDE),
                ou16_response_data => su16_main_data(CINT_SIDE),
                o_rom_request => s_rom_request(CINT_SIDE),
                ou18_rom_byte_address => open,
                i_rom_response_valid => '0',
                iu16_rom_response_data => (others => '0'),
                i_view_enable => '0',
                iu5_view_target => CU5_TARGET_NONE,
                iu15_view_word_address => (others => '0'),
                o_view_valid => open,
                ou16_view_data => open,
                i_bitmap_read_enable => '0',
                iu15_bitmap_word_address => (others => '0'),
                ou16_bitmap_data => open,
                i_palette_read_enable => '0',
                iu10_palette_word_address => (others => '0'),
                ou16_palette_data => open,
                i_sprite_request => '0',
                iu11_sprite_word_address => (others => '0'),
                o_sprite_response_valid => open,
                ou16_sprite_data => open,
                i_tile_request => '0',
                iu13_tile_word_address => (others => '0'),
                o_tile_response_valid => open,
                ou16_tile_data => open
            );
        sound_ram : entity work.rabbitpunch_sound_bus_model
            port map (
                i_clk => s_clk,
                i_request => s_sound_request,
                i_request_write => s_sound_write,
                iu16_request_address => su16_sound_bus_address,
                iu8_request_data => su8_sound_write_data,
                o_response_valid => s_sound_response(CINT_SIDE),
                ou8_response_data => su8_sound_data(CINT_SIDE),
                o_rom_request => s_sound_rom_request(CINT_SIDE),
                ou16_rom_address => open,
                i_rom_ready => '0',
                i_rom_response_valid => '0',
                iu8_rom_response_data => (others => '0'),
                i_ym_write_enable => '0',
                iu8_ym_status => (others => '0'),
                o_ym_write => open,
                o_ym_data_register => open,
                ou8_ym_write_data => open,
                iu8_command => (others => '0'),
                o_command_read => open,
                o_adpcm_control_write => open,
                o_adpcm_command_write => open,
                ou8_adpcm_data => open,
                i_view_enable => '0',
                iu11_view_address => (others => '0'),
                ou8_view_data => open,
                o_idle => open
            );
    end generate;
    compare_and_delay : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            s_main_credit <= '0';
            s_sound_credit <= '0';
            if (s_initialize = '0') then
                assert (s_main_response(0) = s_main_response(1) and s_sound_response(0) = s_sound_response(1))
                    report "Native/model response timing mismatch" severity failure;
                assert (s_rom_request(0) = '0' and s_rom_request(1) = '0' and
                    s_sound_rom_request(0) = '0' and s_sound_rom_request(1) = '0')
                    report "State RAM access escaped to ROM" severity failure;
                if (s_main_request = '1') then
                    assert (s_supported(0) = '1' and s_supported(1) = '1')
                        report "State main RAM mapping unsupported" severity failure;
                end if;
                if (s_main_response(0) = '1') then
                    assert (sint_main_delay = 0) report "Overlapping main credit" severity failure;
                    if (s_main_write = '0') then
                        assert (su16_main_data(0) = su16_main_data(1))
                            report "Native/model main read mismatch" severity failure;
                    end if;
                    su16_main_credit_data <= su16_main_data(0);
                    sint_main_delay <= 1 + to_integer(su24_main_address(3 downto 1)) mod 5;
                elsif (sint_main_delay = 1) then
                    sint_main_delay <= 0;
                    s_main_credit <= '1';
                elsif (sint_main_delay > 1) then
                    sint_main_delay <= sint_main_delay - 1;
                end if;
                if (s_sound_response(0) = '1') then
                    assert (sint_sound_delay = 0) report "Overlapping sound credit" severity failure;
                    if (s_sound_write = '0') then
                        assert (su8_sound_data(0) = su8_sound_data(1))
                            report "Native/model sound read mismatch" severity failure;
                    end if;
                    su8_sound_credit_data <= su8_sound_data(0);
                    sint_sound_delay <= 1 + to_integer(su16_sound_address(2 downto 0)) mod 5;
                elsif (sint_sound_delay = 1) then
                    sint_sound_delay <= 0;
                    s_sound_credit <= '1';
                elsif (sint_sound_delay > 1) then
                    sint_sound_delay <= sint_sound_delay - 1;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        file v_trace : text open write_mode is "state_ram_trace.txt";
        variable v_line : line;
        variable vint_operations : natural := 0;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure transfer(vint_address, vint_epoch : natural; vbool_write : boolean) is
            variable vbool_received : boolean := false;
        begin
            assert (s_byte_ready = '1') report "State adapter not ready" severity failure;
            su17_byte_address <= to_unsigned(vint_address, 17);
            su8_byte_write_data <= F_PATTERN(vint_address, vint_epoch);
            if (vbool_write) then
                s_byte_write <= '1';
            else
                s_byte_write <= '0';
            end if;
            s_byte_valid <= '1';
            cycles(1);
            s_byte_valid <= '0';
            for vint_wait in 0 to 63 loop
                cycles(1);
                if (s_byte_response = '1') then
                    assert (s_byte_error = '0') report "State adapter byte error" severity failure;
                    if (not vbool_write) then
                        assert (su8_byte_read_data = F_PATTERN(vint_address, vint_epoch))
                            report "State read expected pattern mismatch at " & integer'image(vint_address) severity failure;
                    end if;
                    vbool_received := true;
                    exit;
                end if;
                assert (s_byte_ready = '0') report "Credit returned before actual response" severity failure;
            end loop;
            assert (vbool_received) report "Bounded state RAM response timeout" severity failure;
            write(v_line, vint_operations);
            write(v_line, string'(" "));
            write(v_line, vint_address);
            write(v_line, string'(" "));
            write(v_line, boolean'image(vbool_write));
            if (not vbool_write) then
                write(v_line, string'(" "));
                write(v_line, to_hstring(su8_byte_read_data));
            end if;
            writeline(v_trace, v_line);
            vint_operations := vint_operations + 1;
        end procedure;
    begin
        cycles(6);
        s_initialize <= '0';
        s_session <= '1';
        cycles(3);
        assert (s_byte_ready = '0') report "Undrained state access accepted" severity failure;
        s_drained <= '1';
        cycles(2);
        for vint_address in 0 to 106495 loop
            transfer(vint_address, 0, false);
        end loop;
        for vint_epoch in 1 to 2 loop
            for vint_address in 0 to 106495 loop
                transfer(vint_address, vint_epoch, true);
            end loop;
            for vint_address in 0 to 106495 loop
                transfer(vint_address, vint_epoch, false);
            end loop;
        end loop;
        assert (vint_operations = 532480) report "Incomplete state RAM sweep" severity failure;
        report "STATE_RAM_NATIVE_COMPARE_PASS operations=" & integer'image(vint_operations);
        finish;
    end process;
    wall_bound : process
    begin
        wait for 100 ms;
        assert (false) report "State RAM comparison simulation time limit" severity failure;
    end process;
end architecture;
