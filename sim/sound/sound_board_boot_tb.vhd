library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity sound_board_boot_tb is
    generic (GINT_WRITE_LIMIT : positive := 4096);
end entity;

architecture test of sound_board_boot_tb is
    type t_rom is array (0 to 65535) of unsigned(7 downto 0);
    impure function load_rom return t_rom is
        file f_rom : text open read_mode is "audio_rom.hex";
        variable v_line : line;
        variable v_rom : t_rom;
    begin
        for vint_address in v_rom'range loop
            readline(f_rom, v_line);
            hread(v_line, v_rom(vint_address));
        end loop;
        return v_rom;
    end function;
    constant ROM : t_rom := load_rom;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_enable, s_half_enable, s_request, s_write : std_logic := '0';
    signal s_rom_request, s_rom_response : std_logic := '0';
    signal su16_rom_address : unsigned(15 downto 0);
    signal su8_rom_data : unsigned(7 downto 0);
    signal s_pause, s_paused : std_logic := '0';
    signal su16_address : unsigned(15 downto 0);
    signal su8_data : unsigned(7 downto 0);
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_writes : natural := 0;
    signal sint_delayed_reads : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_half_enable <= '1' when sint_divider = 23 else '0';
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 23) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
        end if;
    end process;
    board : entity work.rabbitpunch_sound_board
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_cpu_enable => s_enable,
            i_ym_enable => s_enable,
            i_ym_half_enable => s_half_enable,
            i_pause => s_pause,
            o_paused => s_paused,
            iu8_command => x"00",
            i_command_pending => '0',
            o_command_read => open,
            o_rom_request => s_rom_request,
            ou16_rom_address => su16_rom_address,
            i_rom_ready => '1',
            i_rom_response_valid => s_rom_response,
            iu8_rom_response_data => su8_rom_data,
            o_adpcm_control_write => open,
            o_adpcm_command_write => open,
            ou8_adpcm_data => open,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            o_sample_marker => open,
            i_view_enable => '0',
            iu11_view_address => to_unsigned(0, 11),
            ou8_view_data => open,
            o_debug_request => s_request,
            o_debug_write => s_write,
            ou16_debug_address => su16_address,
            ou8_debug_data => su8_data
        );
    monitor : process(s_clk)
        file f_trace : text open write_mode is "rtl_sound_writes.txt";
        variable v_line : line;
    begin
        if (rising_edge(s_clk)) then
            if (s_request = '1' and s_write = '1') then
                hwrite(v_line, su16_address);
                write(v_line, string'(" FF "));
                hwrite(v_line, su8_data);
                writeline(f_trace, v_line);
                sint_writes <= sint_writes + 1;
            end if;
        end if;
    end process;
    rom_transport : process(s_clk)
        variable v_pending : boolean := false;
        variable vint_delay, vint_requests : natural := 0;
        variable vu8_reply : unsigned(7 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_rom_response <= '0';
            if (v_pending) then
                if (vint_delay = 0) then
                    su8_rom_data <= vu8_reply;
                    s_rom_response <= '1';
                    v_pending := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (s_rom_request = '1') then
                assert (not v_pending) report "Sound board overlapped ROM reads" severity failure;
                assert (su16_rom_address < x"F000") report "Sound board ROM address outside decoded region" severity failure;
                vint_requests := vint_requests + 1;
                vu8_reply := ROM(to_integer(su16_rom_address));
                vint_delay := 0;
                if (vint_requests mod 31 = 0) then
                    vint_delay := 53;
                    sint_delayed_reads <= sint_delayed_reads + 1;
                end if;
                v_pending := true;
            end if;
        end if;
    end process;
    stimulus : process
    begin
        wait for 2 us;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        wait until sint_writes = GINT_WRITE_LIMIT for 100 ms;
        assert (sint_writes = GINT_WRITE_LIMIT) report "Sound startup write limit not reached" severity failure;
        wait until falling_edge(s_clk);
        s_pause <= '1';
        wait until s_paused = '1' for 10 us;
        assert (s_paused = '1' and sint_delayed_reads > 0)
            report "Sound startup did not pause/drain delayed requests" severity failure;
        wait for 2 us;
        assert (sint_writes = GINT_WRITE_LIMIT) report "Sound CPU wrote after pause" severity failure;
        report "SOUND_BOARD_BOOT_PASS writes=" & integer'image(sint_writes) &
            " delayed_transactions=" & integer'image(sint_delayed_reads);
        finish;
        wait;
    end process;
end architecture;
