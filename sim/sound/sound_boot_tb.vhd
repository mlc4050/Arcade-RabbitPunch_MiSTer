library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity sound_boot_tb is
    generic (GINT_WRITE_LIMIT : positive := 4096);
end entity;

architecture test of sound_boot_tb is
    type t_rom is array (0 to 65535) of unsigned(7 downto 0);
    type t_ram is array (0 to 2047) of unsigned(7 downto 0);
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
    signal s_enable, s_half_enable, s_request, s_write, s_response : std_logic := '0';
    signal s_ym_select, s_ym_data, s_ym_interrupt, s_pause, s_paused : std_logic := '0';
    signal su16_address : unsigned(15 downto 0);
    signal su8_data, su8_reply, su8_status, su8_ym_data : unsigned(7 downto 0);
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
    cpu : entity work.rabbitpunch_soundcpu
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_pause => s_pause,
            i_interrupt => s_ym_interrupt,
            o_request => s_request,
            o_request_write => s_write,
            ou16_request_address => su16_address,
            ou8_request_data => su8_data,
            i_response_valid => s_response,
            iu8_response_data => su8_reply,
            o_paused => s_paused,
            o_halted => open
        );
    ym : entity work.rabbitpunch_ym2151
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_chip_enable => s_enable,
            i_half_chip_enable => s_half_enable,
            i_chip_select => s_ym_select,
            i_write => s_ym_select,
            i_data_register => s_ym_data,
            iu8_write_data => su8_ym_data,
            ou8_status => su8_status,
            o_interrupt => s_ym_interrupt,
            o_sample_marker => open,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            ou16_full_left_pcm => open,
            ou16_full_right_pcm => open
        );
    backend : process(s_clk)
        file f_trace : text open write_mode is "rtl_sound_writes.txt";
        variable v_line : line;
        variable v_ram : t_ram := (others => x"00");
        variable vint_delay : natural := 0;
        variable vint_address : natural range 0 to 65535;
        variable vint_requests : natural := 0;
        variable v_pending : boolean := false;
        variable vu8_reply : unsigned(7 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_response <= '0';
            if (s_ym_select = '1' and s_enable = '1') then
                s_ym_select <= '0';
            end if;
            if (v_pending) then
                if (vint_delay = 0 and s_ym_select = '0') then
                    su8_reply <= vu8_reply;
                    s_response <= '1';
                    v_pending := false;
                elsif (vint_delay /= 0) then
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (s_request = '1') then
                assert (not v_pending) report "Sound CPU issued overlapping requests" severity failure;
                vint_address := to_integer(su16_address);
                vint_requests := vint_requests + 1;
                vu8_reply := x"FF";
                vint_delay := 0;
                if (vint_requests mod 31 = 0) then
                    vint_delay := 53;
                    sint_delayed_reads <= sint_delayed_reads + 1;
                end if;
                if (s_write = '1') then
                    hwrite(v_line, su16_address);
                    write(v_line, string'(" FF "));
                    hwrite(v_line, su8_data);
                    writeline(f_trace, v_line);
                    sint_writes <= sint_writes + 1;
                    if (vint_address >= 16#F800#) then
                        v_ram(vint_address - 16#F800#) := su8_data;
                    elsif (vint_address = 16#F000# or vint_address = 16#F001#) then
                        s_ym_select <= '1';
                        s_ym_data <= su16_address(0);
                        su8_ym_data <= su8_data;
                    else
                        assert (vint_address = 16#F400# or vint_address = 16#F600#)
                            report "Unexpected sound peripheral write" severity failure;
                    end if;
                elsif (vint_address < 16#F000#) then
                    vu8_reply := ROM(vint_address);
                elsif (vint_address >= 16#F800#) then
                    vu8_reply := v_ram(vint_address - 16#F800#);
                elsif (vint_address = 16#F000# or vint_address = 16#F001#) then
                    vu8_reply := su8_status;
                else
                    assert false report "Sound startup reached mailbox or unmapped read" severity failure;
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
        report "SOUND_BOOT_PASS writes=" & integer'image(sint_writes) &
            " delayed_transactions=" & integer'image(sint_delayed_reads);
        finish;
        wait;
    end process;
end architecture;
