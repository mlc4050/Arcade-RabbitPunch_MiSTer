library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity sound_bus_tb is
end entity;

architecture test of sound_bus_tb is
    signal s_clk : std_logic := '0';
    signal s_request, s_write, s_response, s_rom_request : std_logic := '0';
    signal s_rom_ready, s_rom_response, s_ym_enable : std_logic := '0';
    signal s_ym_write, s_ym_data, s_command_read, s_control_write, s_command_write : std_logic;
    signal s_view_enable : std_logic := '0';
    signal su16_address, su16_rom_address : unsigned(15 downto 0) := (others => '0');
    signal su8_data, su8_reply, su8_rom_data, su8_ym_data, su8_adpcm_data, su8_view_data : unsigned(7 downto 0) := (others => '0');
    signal su11_view_address : unsigned(10 downto 0) := (others => '0');
    signal sint_divider : natural range 0 to 11 := 0;
    signal sint_ym_writes, sint_reads, sint_controls, sint_commands, sint_rom_reads : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_ym_enable <= '1' when sint_divider = 11 else '0';
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 11) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            assert (s_ym_write /= '1' or s_ym_enable = '1')
                report "YM write extended beyond its single enable edge" severity failure;
            if (s_ym_write = '1' and s_ym_enable = '1') then
                if (sint_ym_writes = 0) then
                    assert (s_ym_data = '0' and su8_ym_data = x"14") report "YM address latch failed" severity failure;
                else
                    assert (s_ym_data = '1' and su8_ym_data = x"30") report "YM data latch failed" severity failure;
                end if;
                sint_ym_writes <= sint_ym_writes + 1;
            end if;
            if (s_command_read = '1') then
                sint_reads <= sint_reads + 1;
            end if;
            if (s_control_write = '1') then
                assert (su8_adpcm_data = x"81") report "ADPCM control data changed" severity failure;
                sint_controls <= sint_controls + 1;
            end if;
            if (s_command_write = '1') then
                assert (su8_adpcm_data = x"27") report "ADPCM command data changed" severity failure;
                sint_commands <= sint_commands + 1;
            end if;
        end if;
    end process;
    dut : entity work.rabbitpunch_sound_bus
        port map (
            i_clk => s_clk,
            i_request => s_request,
            i_request_write => s_write,
            iu16_request_address => su16_address,
            iu8_request_data => su8_data,
            o_response_valid => s_response,
            ou8_response_data => su8_reply,
            o_rom_request => s_rom_request,
            ou16_rom_address => su16_rom_address,
            i_rom_ready => s_rom_ready,
            i_rom_response_valid => s_rom_response,
            iu8_rom_response_data => su8_rom_data,
            i_ym_write_enable => s_ym_enable,
            iu8_ym_status => x"A5",
            o_ym_write => s_ym_write,
            o_ym_data_register => s_ym_data,
            ou8_ym_write_data => su8_ym_data,
            iu8_command => x"69",
            o_command_read => s_command_read,
            o_adpcm_control_write => s_control_write,
            o_adpcm_command_write => s_command_write,
            ou8_adpcm_data => su8_adpcm_data,
            i_view_enable => s_view_enable,
            iu11_view_address => su11_view_address,
            ou8_view_data => su8_view_data
        );
    rom : process
        variable vu16_address : unsigned(15 downto 0);
    begin
        loop
            wait until s_rom_request = '1';
            vu16_address := su16_rom_address;
            for vint_cycle in 1 to 17 loop
                wait until falling_edge(s_clk);
                assert (s_rom_request = '1' and su16_rom_address = vu16_address)
                    report "Sound ROM request was not held under backpressure" severity failure;
            end loop;
            s_rom_ready <= '1';
            wait until falling_edge(s_clk);
            s_rom_ready <= '0';
            for vint_cycle in 1 to 53 loop
                wait until falling_edge(s_clk);
            end loop;
            su8_rom_data <= vu16_address(7 downto 0) xor x"5A";
            s_rom_response <= '1';
            sint_rom_reads <= sint_rom_reads + 1;
            wait until falling_edge(s_clk);
            s_rom_response <= '0';
        end loop;
    end process;
    stimulus : process
        procedure transfer(constant vint_address : natural; constant v_write : std_logic;
                           constant vu8_data : unsigned(7 downto 0);
                           constant CU8_VU8_EXPECTED : unsigned(7 downto 0) := x"FF") is
            variable v_seen : boolean;
        begin
            wait until falling_edge(s_clk);
            su16_address <= to_unsigned(vint_address, 16);
            su8_data <= vu8_data;
            s_write <= v_write;
            s_request <= '1';
            wait until falling_edge(s_clk);
            s_request <= '0';
            su16_address <= x"DEAD";
            su8_data <= x"CC";
            v_seen := s_response = '1';
            for vint_cycle in 1 to 200 loop
                exit when v_seen;
                wait until falling_edge(s_clk);
                v_seen := s_response = '1';
            end loop;
            assert (v_seen) report "Sound bus transaction timed out" severity failure;
            if (v_write = '0') then
                assert (su8_reply = CU8_VU8_EXPECTED) report "Sound bus read data mismatch at " & integer'image(vint_address) severity failure;
            end if;
            wait until falling_edge(s_clk);
            assert (s_response = '0') report "Sound bus duplicated reply" severity failure;
        end procedure;
    begin
        for vint_address in 0 to 2047 loop
            transfer(16#F800# + vint_address, '1', to_unsigned(vint_address mod 256, 8) xor x"53");
        end loop;
        for vint_address in 0 to 2047 loop
            transfer(16#F800# + vint_address, '0', x"00", to_unsigned(vint_address mod 256, 8) xor x"53");
            s_view_enable <= '1';
            su11_view_address <= to_unsigned(vint_address, 11);
            wait until falling_edge(s_clk);
            assert (su8_view_data = (to_unsigned(vint_address mod 256, 8) xor x"53"))
                report "Sound RAM inspection mismatch" severity failure;
            s_view_enable <= '0';
        end loop;
        transfer(0, '0', x"00", x"5A");
        transfer(16#EFFF#, '0', x"00", x"A5");
        transfer(16#F000#, '0', x"00", x"FF");
        transfer(16#F001#, '0', x"00", x"A5");
        transfer(16#F200#, '0', x"00", x"69");
        transfer(16#F000#, '1', x"14");
        transfer(16#F001#, '1', x"30");
        transfer(16#F400#, '1', x"81");
        transfer(16#F600#, '1', x"27");
        transfer(16#F201#, '0', x"00");
        transfer(16#F7FF#, '0', x"00");
        transfer(16#F400#, '0', x"00");
        transfer(16#F600#, '0', x"00");
        transfer(0, '1', x"AA");
        transfer(16#F201#, '1', x"BB");
        assert (sint_ym_writes = 2 and sint_reads = 1 and sint_controls = 1 and sint_commands = 1 and sint_rom_reads = 2)
            report "Sound bus side effects missing or duplicated" severity failure;
        report "SOUND_BUS_PASS ram_bytes=2048 inspection_bytes=2048 rom_backpressure=checked peripherals=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "Sound bus timeout" severity failure;
    end process;
end architecture;
