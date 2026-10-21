-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity state_ddr_arbiter_tb is
end entity;

architecture test of state_ddr_arbiter_tb is
    signal s_clk : std_logic := '0';
    signal s_initialize, s_loader, s_loader_read, s_loader_write : std_logic := '0';
    signal s_rotation_write, s_state, s_state_read, s_state_write : std_logic := '0';
    signal s_loader_busy, s_loader_valid, s_rotation_busy, s_state_busy, s_state_valid, s_idle : std_logic;
    signal s_busy, s_valid, s_read, s_write : std_logic := '0';
    signal su8_loader_burst : unsigned(7 downto 0) := to_unsigned(3, 8);
    signal su8_burst, su8_bytes : unsigned(7 downto 0);
    signal su29_address : unsigned(28 downto 0);
    signal su64_data, su64_reply, su64_loader_reply, su64_state_reply : unsigned(63 downto 0) := (others => '0');
begin
    s_clk <= not s_clk after 5 ns;
    arbiter : entity work.rabbitpunch_state_ddr_arbiter
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_loader_active => s_loader,
            i_loader_read => s_loader_read,
            i_loader_write => s_loader_write,
            iu8_loader_burst_count => su8_loader_burst,
            iu29_loader_word_address => to_unsigned(16#1000#, 29),
            iu64_loader_write_data => x"1122334455667788",
            iu8_loader_byte_enables => x"FF",
            o_loader_busy => s_loader_busy,
            o_loader_read_valid => s_loader_valid,
            ou64_loader_read_data => su64_loader_reply,
            i_rotation_write => s_rotation_write,
            iu29_rotation_word_address => to_unsigned(16#2000#, 29),
            iu64_rotation_data => x"F0E0D0C0B0A09080",
            iu8_rotation_byte_enables => x"B3",
            o_rotation_busy => s_rotation_busy,
            i_state_active => s_state,
            i_state_read => s_state_read,
            i_state_write => s_state_write,
            iu29_state_word_address => to_unsigned(16#3000#, 29),
            iu64_state_write_data => x"0123456789ABCDEF",
            iu8_state_byte_enables => x"0F",
            o_state_busy => s_state_busy,
            o_state_read_valid => s_state_valid,
            ou64_state_read_data => su64_state_reply,
            o_read_idle => s_idle,
            i_ddr_busy => s_busy,
            i_ddr_read_valid => s_valid,
            iu64_ddr_read_data => su64_reply,
            ou8_ddr_burst_count => su8_burst,
            ou29_ddr_word_address => su29_address,
            ou64_ddr_write_data => su64_data,
            ou8_ddr_byte_enables => su8_bytes,
            o_ddr_read => s_read,
            o_ddr_write => s_write
        );
    stimulus : process
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure reply(v_loader : boolean; vint_value : natural) is
        begin
            s_valid <= '1';
            su64_reply <= to_unsigned(vint_value, 64);
            wait for 1 ns;
            assert ((s_loader_valid = '1') = v_loader and (s_state_valid = '1') /= v_loader)
                report "DDR response delivered to wrong/canceled client" severity failure;
            assert (su64_state_reply = vint_value and su64_loader_reply = vint_value) severity failure;
            cycles;
            s_valid <= '0';
            wait for 1 ns;
        end procedure;
    begin
        s_initialize <= '1';
        cycles(2);
        s_initialize <= '0';
        s_state <= '1';
        s_state_read <= '1';
        wait for 1 ns;
        assert (s_state_busy = '0' and s_read = '1' and su8_burst = 1 and su29_address = 16#3000#)
            severity failure;
        cycles;
        s_state_read <= '0';
        s_state <= '0';
        s_rotation_write <= '1';
        wait for 1 ns;
        assert (s_idle = '0' and s_rotation_busy = '0' and s_write = '1' and su8_bytes = x"B3")
            report "Pending state read blocked queued rotation writes" severity failure;
        cycles;
        s_rotation_write <= '0';
        s_loader <= '1';
        s_loader_read <= '1';
        s_initialize <= '1';
        cycles(3);
        assert (s_read = '0' and s_write = '0' and s_loader_busy = '1' and s_idle = '0') severity failure;
        reply(false, 123);
        assert (s_idle = '1') severity failure;
        s_initialize <= '0';
        wait for 1 ns;
        assert (s_loader_busy = '0' and s_read = '1' and su8_burst = 3 and su29_address = 16#1000#)
            report "Loader takeover did not wait for state response debt" severity failure;
        cycles;
        s_loader_read <= '0';
        s_loader <= '0';
        s_rotation_write <= '1';
        s_state <= '1';
        s_state_write <= '1';
        wait for 1 ns;
        assert (s_rotation_busy = '1' and s_state_busy = '1' and s_write = '0') severity failure;
        reply(true, 1);
        s_initialize <= '1';
        reply(true, 2);
        s_initialize <= '0';
        reply(true, 3);
        assert (s_idle = '1' and s_state_busy = '1' and s_rotation_busy = '0' and
            s_write = '1' and su29_address = 16#2000# and su64_data = x"F0E0D0C0B0A09080")
            report "Canceled loader debt lost ownership or rotation priority" severity failure;
        s_busy <= '1';
        cycles(4);
        assert (s_write = '0' and s_read = '0' and s_state_busy = '1' and s_rotation_busy = '1') severity failure;
        s_busy <= '0';
        cycles;
        s_rotation_write <= '0';
        wait for 1 ns;
        assert (s_state_busy = '0' and s_write = '1' and su29_address = 16#3000# and
            su64_data = x"0123456789ABCDEF" and su8_bytes = x"0F") severity failure;
        cycles;
        s_state_write <= '0';
        s_loader <= '1';
        s_loader_read <= '1';
        su8_loader_burst <= to_unsigned(255, 8);
        cycles;
        s_loader_read <= '0';
        s_loader <= '0';
        for vint_beat in 1 to 255 loop
            assert (s_idle = '0' and s_state_busy = '1') severity failure;
            reply(true, vint_beat);
        end loop;
        assert (s_idle = '1' and s_state_valid = '0' and s_loader_valid = '0') severity failure;
        s_loader <= '1';
        s_loader_write <= '1';
        su8_loader_burst <= to_unsigned(1, 8);
        s_rotation_write <= '1';
        s_state_write <= '1';
        wait for 1 ns;
        assert (s_loader_busy = '0' and s_state_busy = '1' and s_rotation_busy = '1' and
            s_write = '1' and s_read = '0' and su29_address = 16#1000# and
            su64_data = x"1122334455667788" and su8_bytes = x"FF") severity failure;
        cycles;
        s_initialize <= '1';
        wait for 1 ns;
        assert (s_write = '0' and s_read = '0' and s_idle = '1') severity failure;
        report "STATE_DDR_ARBITER_PASS state_cancel=drained loader_cancel=drained bursts=3,255 rotation=priority";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 100 us;
        assert (false) report "DDR arbiter timeout" severity failure;
        wait;
    end process;
end architecture;
