library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity sound_board_tb is
end entity;

architecture test of sound_board_tb is
    type t_program is array (0 to 255) of unsigned(7 downto 0);
    constant PROGRAM : t_program := (
        0 => x"31", 1 => x"FF", 2 => x"FF", 3 => x"3E", 4 => x"14",
        5 => x"32", 6 => x"00", 7 => x"F0", 8 => x"AF", 9 => x"32",
        10 => x"01", 11 => x"F0", 12 => x"3A", 13 => x"01", 14 => x"F0",
        15 => x"E6", 16 => x"80", 17 => x"FE", 18 => x"80",
        19 => x"C2", 20 => x"FF", 21 => x"00", 22 => x"ED", 23 => x"56",
        24 => x"FB", 25 => x"76", 26 => x"C3", 27 => x"19", 28 => x"00",
        16#38# => x"3A", 16#39# => x"00", 16#3A# => x"F2",
        16#3B# => x"32", 16#3C# => x"00", 16#3D# => x"F8",
        16#3E# => x"FB", 16#3F# => x"ED", 16#40# => x"4D", 255 => x"76", others => x"00");
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_pause, s_paused, s_send, s_pending, s_ack : std_logic := '0';
    signal s_enable, s_half_enable, s_rom_request, s_rom_reply : std_logic := '0';
    signal s_view, s_debug_request, s_debug_write, s_sample : std_logic := '0';
    signal su16_rom_address, su16_debug_address : unsigned(15 downto 0);
    signal su8_rom_data, su8_debug_data, su8_view_data : unsigned(7 downto 0);
    signal su8_command : unsigned(7 downto 0) := x"42";
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_acks, sint_writes, sint_samples : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_half_enable <= '1' when sint_divider = 23 else '0';
    process(s_clk)
        variable v_previous_sample : std_logic := '0';
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 23) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            if (s_ack = '1') then
                s_pending <= '0';
                sint_acks <= sint_acks + 1;
            end if;
            if (s_send = '1') then
                assert (s_pending = '0') report "Synthetic main board overwrote a pending command" severity failure;
                s_pending <= '1';
            end if;
            if (s_debug_request = '1' and s_debug_write = '1' and su16_debug_address = x"F800") then
                assert (su8_debug_data = su8_command) report "Sound interrupt handler stored wrong command" severity failure;
                sint_writes <= sint_writes + 1;
            end if;
            if (s_sample = '1' and v_previous_sample = '0') then
                sint_samples <= sint_samples + 1;
            end if;
            v_previous_sample := s_sample;
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
            iu8_command => su8_command,
            i_command_pending => s_pending,
            o_command_read => s_ack,
            o_rom_request => s_rom_request,
            ou16_rom_address => su16_rom_address,
            i_rom_ready => '1',
            i_rom_response_valid => s_rom_reply,
            iu8_rom_response_data => su8_rom_data,
            o_adpcm_control_write => open,
            o_adpcm_command_write => open,
            ou8_adpcm_data => open,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            o_sample_marker => s_sample,
            i_view_enable => s_view,
            iu11_view_address => to_unsigned(0, 11),
            ou8_view_data => su8_view_data,
            o_debug_request => s_debug_request,
            o_debug_write => s_debug_write,
            ou16_debug_address => su16_debug_address,
            ou8_debug_data => su8_debug_data
        );
    rom : process(s_clk)
        variable v_pending : boolean := false;
        variable vint_delay : natural := 0;
        variable vu8_reply : unsigned(7 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_rom_reply <= '0';
            if (v_pending) then
                if (vint_delay = 0) then
                    su8_rom_data <= vu8_reply;
                    s_rom_reply <= '1';
                    v_pending := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (s_rom_request = '1') then
                assert (not v_pending and su16_rom_address < 256)
                    report "Sound IRQ program fetched unexpected address" severity failure;
                vu8_reply := PROGRAM(to_integer(su16_rom_address(7 downto 0)));
                vint_delay := 20;
                v_pending := true;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_samples_before : natural;
        procedure command(constant vu8_data : unsigned(7 downto 0); constant vint_count : positive) is
        begin
            wait until falling_edge(s_clk);
            su8_command <= vu8_data;
            s_send <= '1';
            wait until falling_edge(s_clk);
            s_send <= '0';
            wait until sint_writes = vint_count for 100 us;
            assert (sint_writes = vint_count and sint_acks = vint_count and s_pending = '0')
                report "Sound command interrupt or acknowledgement failed" severity failure;
            wait until falling_edge(s_clk);
            s_pause <= '1';
            wait until s_paused = '1' for 10 us;
            assert (s_paused = '1') report "Sound board pause did not drain" severity failure;
            wait until falling_edge(s_clk);
            s_view <= '1';
            wait until falling_edge(s_clk);
            assert (su8_view_data = vu8_data) report "Sound handler native RAM inspection mismatch" severity failure;
            s_view <= '0';
            vint_samples_before := sint_samples;
            wait for 40 us;
            assert (sint_samples >= vint_samples_before + 2 and sint_writes = vint_count)
                report "Sound pause stopped YM cadence or allowed CPU writes" severity failure;
            wait until falling_edge(s_clk);
            s_pause <= '0';
        end procedure;
    begin
        wait for 2 us;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        wait until s_debug_request = '1' and su16_debug_address = 25 for 100 us;
        assert (s_debug_request = '1' and su16_debug_address = 25) report "Sound CPU did not pass YM busy readback and reach EI/HALT" severity failure;
        command(x"42", 1);
        command(x"3C", 2);
        report "SOUND_BOARD_PASS ym_busy_readback=checked commands=2 interrupt_ack=checked native_ram=checked pause_keeps_ym_running=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 400 us;
        assert false report "Sound board diagnostic timeout" severity failure;
    end process;
end architecture;
