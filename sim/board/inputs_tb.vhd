-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity inputs_tb is
end entity;

architecture test of inputs_tb is
    type t_addresses is array (natural range <>) of natural;
    constant IGNORED_ADDRESSES : t_addresses := (2, 3, 128, 16#4000000#, 16#7FFFFFF#);
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal su32_joy0, su32_joy1 : unsigned(31 downto 0) := (others => '0');
    signal su11_key : unsigned(10 downto 0) := (others => '0');
    signal s_file_write : std_logic := '0';
    signal su16_file_index : unsigned(15 downto 0) := (others => '0');
    signal su27_file_address : unsigned(26 downto 0) := (others => '0');
    signal su8_file_data : unsigned(7 downto 0) := (others => '0');
    signal su8_player1, su8_player2, su8_service : unsigned(7 downto 0);
    signal su16_dips : unsigned(15 downto 0);
    signal s_pause : std_logic;
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_inputs
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            iu32_joystick0 => su32_joy0,
            iu32_joystick1 => su32_joy1,
            iu11_key_event => su11_key,
            i_file_write => s_file_write,
            iu16_file_index => su16_file_index,
            iu27_file_byte_address => su27_file_address,
            iu8_file_data => su8_file_data,
            ou8_player1 => su8_player1,
            ou8_player2 => su8_player2,
            ou8_service => su8_service,
            ou16_dips => su16_dips,
            o_pause_pressed => s_pause
        );
    process
        file vectors : text open read_mode is "input_vectors.hex";
        variable v_line : line;
        variable vu32_joy0, vu32_joy1 : unsigned(31 downto 0);
        variable vu12_key : unsigned(11 downto 0);
        variable vu8_pause, vu8_player1, vu8_player2, vu8_service : unsigned(7 downto 0);
        variable vu11_event : unsigned(10 downto 0);
        variable v_pause : std_logic;
        variable vint_vectors, vint_key_vectors : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure check_ports(vu8_p1, vu8_p2, vu8_svc : unsigned(7 downto 0); v_pause_expected : std_logic := '0') is
        begin
            assert (su8_player1 = vu8_p1 and su8_player2 = vu8_p2 and su8_service = vu8_svc and s_pause = v_pause_expected)
                report "Pad/key board input differs from live MAME port reference" severity failure;
        end procedure;
        procedure key(vint_code : natural; v_pressed : std_logic) is
        begin
            vu11_event := su11_key;
            vu11_event(10) := not vu11_event(10);
            vu11_event(9) := v_pressed;
            vu11_event(8 downto 0) := to_unsigned(vint_code, 9);
            su11_key <= vu11_event;
            tick;
            tick;
        end procedure;
        procedure metadata(vint_index, vint_address, vint_data : natural) is
        begin
            su16_file_index <= to_unsigned(vint_index, 16);
            su27_file_address <= to_unsigned(vint_address, 27);
            su8_file_data <= to_unsigned(vint_data, 8);
            s_file_write <= '1';
            tick;
            s_file_write <= '0';
            su8_file_data <= (others => '1');
            tick;
        end procedure;
    begin
        tick;
        assert (su16_dips = 0) report "Japan fallback DIP initialization mismatch" severity failure;
        s_initialize <= '0';
        tick;
        while (not endfile(vectors)) loop
            readline(vectors, v_line);
            hread(v_line, vu32_joy0);
            hread(v_line, vu32_joy1);
            hread(v_line, vu12_key);
            hread(v_line, vu8_pause);
            hread(v_line, vu8_player1);
            hread(v_line, vu8_player2);
            hread(v_line, vu8_service);
            v_pause := '0';
            if (vu8_pause /= 0) then
                v_pause := '1';
            end if;
            su32_joy0 <= vu32_joy0;
            su32_joy1 <= vu32_joy1;
            tick;
            check_ports(vu8_player1, vu8_player2, vu8_service, v_pause);
            su32_joy0 <= (others => '0');
            su32_joy1 <= (others => '0');
            tick;
            check_ports(x"00", x"00", x"00");
            if (vu12_key /= x"FFF") then
                key(to_integer(vu12_key), '1');
                check_ports(vu8_player1, vu8_player2, vu8_service, v_pause);
                key(to_integer(vu12_key), '0');
                check_ports(x"00", x"00", x"00");
                vint_key_vectors := vint_key_vectors + 1;
            end if;
            vint_vectors := vint_vectors + 1;
        end loop;
        key(16#14#, '1');
        check_ports(x"10", x"00", x"00");
        -- Payload changes without a toggle must not become another key event.
        su11_key(9) <= '0';
        tick;
        tick;
        check_ports(x"10", x"00", x"00");
        su32_joy0(4) <= '1';
        key(16#14#, '0');
        check_ports(x"10", x"00", x"00");
        su32_joy0 <= (others => '0');
        tick;
        check_ports(x"00", x"00", x"00");
        key(16#14#, '1');
        key(16#11#, '1');
        check_ports(x"30", x"00", x"00");
        key(16#14#, '0');
        check_ports(x"20", x"00", x"00");
        key(16#11#, '0');
        key(16#114#, '1');
        check_ports(x"00", x"00", x"00");
        key(16#114#, '0');
        metadata(254, 0, 0);
        metadata(254, 1, 0);
        assert (su16_dips = x"0000") report "Japan MRA DIP word mismatch" severity failure;
        metadata(254, 1, 16#20#);
        assert (su16_dips = x"2000") report "US MRA demo-sound DIP default mismatch" severity failure;
        for vint_byte in 0 to 255 loop
            metadata(254, 0, vint_byte);
            assert (su16_dips = 16#2000# + vint_byte) report "DIP low-byte lane/strobe mismatch" severity failure;
        end loop;
        metadata(254, 0, 16#5A#);
        for vint_byte in 0 to 255 loop
            metadata(254, 1, vint_byte);
            assert (su16_dips = vint_byte * 256 + 16#5A#) report "DIP high-byte lane/strobe mismatch" severity failure;
        end loop;
        for vint_index in 0 to 1 loop
            metadata(vint_index, 0, 0);
            assert (su16_dips = x"FF5A") report "ROM/mod download changed DIPs" severity failure;
        end loop;
        for vint_index in IGNORED_ADDRESSES'range loop
            metadata(254, IGNORED_ADDRESSES(vint_index), 0);
            assert (su16_dips = x"FF5A") report "DIP metadata address aliased to a live byte" severity failure;
        end loop;
        tick;
        assert (su16_dips = x"FF5A") report "DIPs changed without a write strobe" severity failure;
        s_initialize <= '1';
        tick;
        assert (su16_dips = 0) report "Cold input initialization did not restore its configured fallback" severity failure;
        report "INPUTS_PASS mame_pad_vectors=" & integer'image(vint_vectors) & " mame_key_vectors=" & integer'image(vint_key_vectors) &
            " active_high=checked dip_byte_values=512 per_set_defaults=checked pad_key_union=checked event_toggle=checked";
        finish;
        wait;
    end process;
end architecture;
