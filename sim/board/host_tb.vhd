-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity host_tb is
end entity;

architecture test of host_tb is
    component host_check is
    port (
        i_clk : in std_logic;
        iu16_host_data : in unsigned(15 downto 0);
        i_host_strobe : in std_logic;
        i_uio_select : in std_logic;
        i_file_select : in std_logic;
        ou16_host_response : out unsigned(15 downto 0);
        o_host_wait : out std_logic;
        o_wide_mode : out std_logic;
        iu16_menu_mask : in unsigned(15 downto 0);
        ou128_status : out unsigned(127 downto 0);
        ou32_joystick0 : out unsigned(31 downto 0);
        ou32_joystick1 : out unsigned(31 downto 0);
        ou11_key_event : out unsigned(10 downto 0);
        ou2_buttons : out unsigned(1 downto 0);
        o_forced_scandoubler : out std_logic;
        o_direct_video : out std_logic;
        ou16_sdram_configuration : out unsigned(15 downto 0);
        o_file_download : out std_logic;
        ou16_file_index : out unsigned(15 downto 0);
        o_file_write : out std_logic;
        ou27_file_byte_address : out unsigned(26 downto 0);
        ou8_file_data : out unsigned(7 downto 0);
        i_file_wait : in std_logic
    );
    end component;
    constant CONFIG : string := "RabbitPunch;;R0,Reset;";
    signal s_clk : std_logic := '0';
    signal su46_bus, su46_master : unsigned(45 downto 0) := (others => 'Z');
    signal su128_status : unsigned(127 downto 0);
    signal su32_joystick0, su32_joystick1 : unsigned(31 downto 0);
    signal su11_key : unsigned(10 downto 0);
    signal su2_buttons : unsigned(1 downto 0);
    signal s_scandoubler, s_direct, s_download, s_write : std_logic;
    signal s_wait : std_logic := '0';
    signal su16_sdram, su16_index : unsigned(15 downto 0);
    signal su27_address : unsigned(26 downto 0);
    signal su8_data : unsigned(7 downto 0);
    signal sint_writes : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    su46_bus <= su46_master;
    dut : host_check
        port map (
            i_clk => s_clk,
            iu16_host_data => su46_master(31 downto 16),
            i_host_strobe => su46_master(33),
            i_uio_select => su46_master(34),
            i_file_select => su46_master(35),
            ou16_host_response => su46_bus(15 downto 0),
            o_host_wait => su46_bus(37),
            o_wide_mode => su46_bus(32),
            iu16_menu_mask => (others => '0'),
            ou128_status => su128_status,
            ou32_joystick0 => su32_joystick0,
            ou32_joystick1 => su32_joystick1,
            ou11_key_event => su11_key,
            ou2_buttons => su2_buttons,
            o_forced_scandoubler => s_scandoubler,
            o_direct_video => s_direct,
            ou16_sdram_configuration => su16_sdram,
            o_file_download => s_download,
            ou16_file_index => su16_index,
            o_file_write => s_write,
            ou27_file_byte_address => su27_address,
            ou8_file_data => su8_data,
            i_file_wait => s_wait
        );
    monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_write = '1') then
                assert (s_download = '1' and su16_index = 0 and su27_address = sint_writes and
                    su8_data = 16#A0# + sint_writes)
                    report "Native HPS file data/address/index/pulse mismatch" severity failure;
                sint_writes <= sint_writes + 1;
            end if;
        end if;
    end process;
    process
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure word(vint_data : natural) is
        begin
            su46_master(31 downto 16) <= to_unsigned(vint_data, 16);
            su46_master(33) <= '1';
            cycles(1);
            su46_master(33) <= '0';
            cycles(3);
        end procedure;
        procedure file_command(vint_command, vint_data : natural) is
        begin
            cycles(1);
            su46_master(35) <= '1';
            word(vint_command);
            word(vint_data);
            su46_master(35) <= '0';
            cycles(4);
        end procedure;
        procedure uio_begin(vint_command : natural) is
        begin
            cycles(1);
            su46_master(34) <= '1';
            word(vint_command);
        end procedure;
        procedure uio_end is
        begin
            su46_master(34) <= '0';
            cycles(4);
        end procedure;
    begin
        su46_master(45 downto 38) <= (others => '0');
        su46_master(35 downto 33) <= "000";
        su46_master(31 downto 16) <= (others => '0');
        cycles(5);
        assert (su46_bus(32) = '0') report "Host wrapper unexpectedly enabled wide file mode" severity failure;
        uio_begin(16#14#);
        for vint_char in CONFIG'range loop
            word(0);
            assert (su46_bus(7 downto 0) = character'pos(CONFIG(vint_char)))
                report "Host configuration string generic/byte order mismatch" severity failure;
        end loop;
        uio_end;
        uio_begin(1);
        word(16#0413#);
        uio_end;
        assert (su2_buttons = 3 and s_scandoubler = '1' and s_direct = '1')
            report "Host button/video configuration mapping mismatch" severity failure;
        uio_begin(2);
        word(16#1234#);
        word(16#ABCD#);
        uio_end;
        uio_begin(3);
        word(16#5678#);
        word(16#9ABC#);
        uio_end;
        assert (su32_joystick0 = x"ABCD1234" and su32_joystick1 = x"9ABC5678")
            report "Host joystick bit/word ordering mismatch" severity failure;
        uio_begin(16#1E#);
        for vint_word in 0 to 7 loop
            word(16#1000# + vint_word);
        end loop;
        uio_end;
        for vint_word in 0 to 7 loop
            assert (su128_status(vint_word * 16 + 15 downto vint_word * 16) = 16#1000# + vint_word)
                report "Host 128-bit status word ordering mismatch" severity failure;
        end loop;
        uio_begin(5);
        word(16#06#);
        uio_end;
        assert (su11_key(9 downto 0) = 16#206# and su11_key(10) = '1')
            report "Native F2 key press flags/code mismatch" severity failure;
        uio_begin(5);
        word(16#F0#);
        word(16#06#);
        uio_end;
        assert (su11_key(9 downto 0) = 16#006# and su11_key(10) = '0')
            report "Native F2 key release/toggle mismatch" severity failure;
        uio_begin(5);
        word(16#E0#);
        word(16#75#);
        uio_end;
        assert (su11_key(9 downto 0) = 16#375# and su11_key(10) = '1')
            report "Native extended arrow press mismatch" severity failure;
        uio_begin(5);
        word(16#E0#);
        word(16#F0#);
        word(16#75#);
        uio_end;
        assert (su11_key(9 downto 0) = 16#175# and su11_key(10) = '0')
            report "Native extended arrow release mismatch" severity failure;
        file_command(16#55#, 0);
        file_command(16#53#, 1);
        assert (s_download = '1' and su16_index = 0) report "Host did not start file download" severity failure;
        s_wait <= '1';
        cycles(3);
        assert (su46_bus(37) = '1' and sint_writes = 0) report "Native HPS wait response mismatch" severity failure;
        s_wait <= '0';
        cycles(3);
        su46_master(35) <= '1';
        word(16#54#);
        for vint_byte in 0 to 7 loop
            word(16#A0# + vint_byte);
        end loop;
        su46_master(35) <= '0';
        cycles(4);
        file_command(16#53#, 0);
        assert (s_download = '0' and sint_writes = 8) report "Host download end or byte count mismatch" severity failure;
        report "HOST_PASS native_hps_io=checked config_string=checked joystick_status_order=checked byte_download=8 wait_pin=checked keyboard_press_release=checked";
        finish;
        wait;
    end process;
end architecture;
