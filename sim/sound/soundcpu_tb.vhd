library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity soundcpu_tb is
end entity;

architecture test of soundcpu_tb is
    type t_program is array (0 to 255) of unsigned(7 downto 0);
    constant PROGRAM : t_program := (
        0 => x"3E", 1 => x"42", 2 => x"32", 3 => x"00", 4 => x"F8",
        5 => x"3A", 6 => x"00", 7 => x"F8", 8 => x"FE", 9 => x"42",
        10 => x"C2", 11 => x"20", 12 => x"00", 13 => x"32", 14 => x"00",
        15 => x"F0", 16 => x"76", others => x"76");
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_pause : std_logic := '0';
    signal s_enable, s_request, s_write, s_response, s_paused, s_halted : std_logic := '0';
    signal s_pending : std_logic := '0';
    signal su16_address : unsigned(15 downto 0);
    signal su8_data, su8_reply : unsigned(7 downto 0);
    signal sint_divider : natural range 0 to 11 := 0;
    signal sint_writes, sint_requests : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 else '0';
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 11) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
        end if;
    end process;
    dut : entity work.rabbitpunch_soundcpu
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_pause => s_pause,
            i_interrupt => '0',
            o_request => s_request,
            o_request_write => s_write,
            ou16_request_address => su16_address,
            ou8_request_data => su8_data,
            i_response_valid => s_response,
            iu8_response_data => su8_reply,
            o_paused => s_paused,
            o_halted => s_halted
        );
    backend : process(s_clk)
        variable vint_delay : natural := 0;
        variable vu8_saved_reply : unsigned(7 downto 0);
        variable vu8_ram : unsigned(7 downto 0) := x"00";
    begin
        if (rising_edge(s_clk)) then
            s_response <= '0';
            if (s_pending = '1') then
                if (vint_delay = 0) then
                    s_pending <= '0';
                    s_response <= '1';
                    su8_reply <= vu8_saved_reply;
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (s_request = '1') then
                assert (s_pending = '0') report "Sound CPU overlapping request" severity failure;
                s_pending <= '1';
                sint_requests <= sint_requests + 1;
                vint_delay := 65;
                vu8_saved_reply := x"FF";
                if (s_write = '1') then
                    assert (su8_data = x"42") report "Sound CPU readback/write data wrong" severity failure;
                    if (sint_writes mod 2 = 0) then
                        assert (su16_address = x"F800") report "Sound RAM write missing" severity failure;
                        vu8_ram := su8_data;
                    else
                        assert (su16_address = x"F000") report "Sound peripheral write missing" severity failure;
                    end if;
                    sint_writes <= sint_writes + 1;
                elsif (su16_address = x"F800") then
                    vu8_saved_reply := vu8_ram;
                else
                    assert (su16_address < 17) report "Sound program branched or fetched wrong data" severity failure;
                    vu8_saved_reply := PROGRAM(to_integer(su16_address(7 downto 0)));
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_requests_before : natural;
    begin
        wait for 2 us;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        wait until s_pending = '1' for 10 us;
        assert (s_pending = '1') report "Sound CPU never requested reset opcode" severity failure;
        wait until falling_edge(s_clk);
        s_pause <= '1';
        wait until s_paused = '1' for 10 us;
        assert (s_paused = '1' and s_pending = '0') report "Sound pause failed to drain" severity failure;
        vint_requests_before := sint_requests;
        wait for 2 us;
        assert (sint_requests = vint_requests_before and sint_writes = 0)
            report "Sound pause issued new transactions" severity failure;
        wait until falling_edge(s_clk);
        s_pause <= '0';
        wait until s_halted = '1' for 100 us;
        assert (s_halted = '1' and sint_writes = 2) report "Sound CPU first program failed" severity failure;
        wait until falling_edge(s_clk);
        s_reset <= '1';
        wait for 1 us;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        wait until s_pending = '1' for 10 us;
        assert (s_pending = '1') report "Sound reset did not restart CPU" severity failure;
        wait until falling_edge(s_clk);
        s_reset <= '1';
        wait until falling_edge(s_clk);
        s_reset <= '0';
        vint_requests_before := sint_requests;
        wait until s_pending = '0' for 10 us;
        assert (s_pending = '0' and sint_requests = vint_requests_before)
            report "Sound reset did not drain the old response" severity failure;
        wait until s_halted = '1' for 100 us;
        assert (s_halted = '1' and sint_writes = 4) report "Sound CPU reset/replay failed" severity failure;
        report "SOUNDCPU_PASS writes=4 pause_drain=checked reset_drain=checked delayed_replies=65";
        finish;
        wait;
    end process;
    process
    begin
        wait for 250 us;
        assert false report "Sound CPU diagnostic timeout" severity failure;
    end process;
end architecture;
