library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity z80_wrapper_tb is
end entity;

architecture test of z80_wrapper_tb is
    type t_program is array (0 to 255) of unsigned(7 downto 0);
    constant PROGRAM : t_program := (
        0 => x"3E", 1 => x"42", 2 => x"32", 3 => x"00", 4 => x"80",
        5 => x"D3", 6 => x"00", 7 => x"76", others => x"00");
    signal s_clk : std_logic := '0';
    signal s_reset, s_run : std_logic := '1';
    signal s_wait : std_logic := '0';
    signal s_enable, s_opcode, s_memory, s_io, s_read, s_write, s_refresh, s_halted, s_grant : std_logic;
    signal s_wait_exercised : std_logic := '0';
    signal su16_address : unsigned(15 downto 0);
    signal su8_data, su8_read_data : unsigned(7 downto 0);
    signal sint_divider : natural range 0 to 11 := 0;
    signal sint_memory_writes, sint_io_writes : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 and s_run = '1' else '0';
    su8_read_data <= PROGRAM(to_integer(su16_address(7 downto 0))) when s_memory = '1' and s_read = '1' else x"00";
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
    cpu : entity work.rabbitpunch_z80
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_wait => s_wait,
            i_interrupt => '0',
            i_non_maskable_interrupt => '0',
            i_bus_request => '0',
            iu8_read_data => su8_read_data,
            ou16_address => su16_address,
            ou8_write_data => su8_data,
            o_opcode_fetch => s_opcode,
            o_memory_request => s_memory,
            o_io_request => s_io,
            o_read => s_read,
            o_write => s_write,
            o_refresh => s_refresh,
            o_halted => s_halted,
            o_bus_grant => s_grant
        );
    monitor : process(s_clk)
        variable v_previous_write : std_logic := '0';
    begin
        if (rising_edge(s_clk)) then
            if (s_write = '1' and v_previous_write = '0') then
                assert (su8_data = x"42") report "Z80 wrapper changed write data" severity failure;
                if (s_memory = '1') then
                    assert (su16_address = x"8000") report "Z80 memory address mismatch" severity failure;
                    sint_memory_writes <= sint_memory_writes + 1;
                elsif (s_io = '1') then
                    assert (su16_address(7 downto 0) = 0) report "Z80 I/O port mismatch" severity failure;
                    sint_io_writes <= sint_io_writes + 1;
                else
                    assert false report "Z80 write lacks memory/I/O ownership" severity failure;
                end if;
            end if;
            v_previous_write := s_write;
        end if;
    end process;
    wait_stimulus : process
    begin
        wait until falling_edge(s_clk) and s_memory = '1' and s_read = '1' and su16_address = 2;
        s_wait <= '1';
        for vint_cycle in 1 to 96 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (su16_address = 2 and s_read = '1' and s_memory = '1')
            report "Z80 WAIT did not retain the read cycle" severity failure;
        s_wait <= '0';
        s_wait_exercised <= '1';
        wait;
    end process;
    stimulus : process
        variable vu16_paused_address : unsigned(15 downto 0);
    begin
        for vint_cycle in 1 to 48 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        wait until s_halted = '1' for 50 us;
        assert (s_halted = '1' and sint_memory_writes = 1 and sint_io_writes = 1 and s_wait_exercised = '1')
            report "Z80 wrapper boot/write/WAIT diagnostic failed" severity failure;
        wait until falling_edge(s_clk);
        s_run <= '0';
        vu16_paused_address := su16_address;
        for vint_cycle in 1 to 96 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (su16_address = vu16_paused_address and s_halted = '1' and s_grant = '0')
            report "Z80 enable stop failed" severity failure;
        report "Z80_WRAPPER_PASS memory_writes=1 io_writes=1 wait_states=checked enable_stop=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 60 us;
        assert false report "Z80 wrapper timeout" severity failure;
    end process;
end architecture;
