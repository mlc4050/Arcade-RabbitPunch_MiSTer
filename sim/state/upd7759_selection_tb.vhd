-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity upd7759_selection_tb is
end entity;

architecture test of upd7759_selection_tb is
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_start, s_compare : std_logic := '0';
    signal su8_phase : unsigned(7 downto 0) := (others => '0');
    signal s_enable, s_rom_valid, s_native_busy, s_state_busy : std_logic;
    signal s_native_request, s_state_request : std_logic;
    signal su17_native_address, su17_state_address : unsigned(16 downto 0);
    signal su8_native_data, su8_state_data : unsigned(7 downto 0);
    signal su9_native_pcm, su9_state_pcm : unsigned(8 downto 0);
    signal su28_native, su28_state : unsigned(27 downto 0);
    signal su32_native_state : unsigned(31 downto 0);
    function F_ROM(vu17_address : unsigned(16 downto 0)) return unsigned is
    begin
        case to_integer(vu17_address) is
            when 0 => return x"00";
            when 1 => return x"5A";
            when 2 => return x"A5";
            when 3 => return x"69";
            when 4 => return x"55";
            when 5 => return x"00";
            when 6 => return x"20";
            -- Corrected silence is2048 control enables, then a nonzero block.
            when 16#41# => return x"01";
            when 16#42# => return x"89";
            when 16#43# => return x"1F";
            when 16#44# to 16#53# => return to_unsigned(16#17# + to_integer(vu17_address(3 downto 0)), 8);
            when others => return x"00";
        end case;
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when su8_phase(1 downto 0) = 3 else '0';
    s_rom_valid <= '1' when su8_phase(3 downto 0) >= 5 else '0';
    su8_native_data <= F_ROM(su17_native_address) when not is_x(su17_native_address) else x"00";
    su8_state_data <= F_ROM(su17_state_address) when not is_x(su17_state_address) else x"00";
    su28_native <= s_native_busy & s_native_request & su17_native_address & su9_native_pcm;
    su28_state <= s_state_busy & s_state_request & su17_state_address & su9_state_pcm;
    phase : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            su8_phase <= su8_phase + 1;
        end if;
    end process;
    native_selection : entity work.rabbitpunch_upd7759
        generic map (
            GBOOL_STATE_CAPABLE => false
        )
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_start => s_start,
            iu8_command => x"00",
            o_busy => s_native_busy,
            o_rom_request => s_native_request,
            ou17_rom_address => su17_native_address,
            i_rom_valid => s_rom_valid and s_native_request,
            iu8_rom_data => su8_native_data,
            ou9_pcm => su9_native_pcm,
            ou32_state_read_data => su32_native_state
        );
    state_selection : entity work.rabbitpunch_upd7759
        generic map (
            GBOOL_STATE_CAPABLE => true
        )
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_start => s_start,
            iu8_command => x"00",
            o_busy => s_state_busy,
            o_rom_request => s_state_request,
            ou17_rom_address => su17_state_address,
            i_rom_valid => s_rom_valid and s_state_request,
            iu8_rom_data => su8_state_data,
            ou9_pcm => su9_state_pcm,
            ou32_state_read_data => open
        );
    stimulus : process
        variable vint_checks, vint_onset : natural := 0;
        variable v_played : boolean := false;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
                if (s_compare = '1') then
                    assert (not is_x(su28_state) and su28_state = su28_native and su32_native_state = 0)
                        report "Default and state-capable corrected ADPCM selections differ" severity failure;
                    vint_checks := vint_checks + 1;
                end if;
            end loop;
        end procedure;
    begin
        cycles(100);
        s_compare <= '1';
        cycles(100);
        s_reset <= '0';
        cycles(200);
        s_start <= '1';
        cycles(16);
        s_start <= '0';
        for vint_cycle in 1 to 50000 loop
            cycles;
            if (su9_state_pcm /= 0 and not v_played) then
                v_played := true;
                vint_onset := vint_cycle;
            end if;
            exit when (v_played and s_state_busy = '0');
        end loop;
        assert (v_played and s_state_busy = '0') report "Corrected synthetic silence/sample did not complete" severity failure;
        assert (vint_onset >= 1024*2*4 - 16)
            report "Default selection regressed to the imported short silence" severity failure;
        cycles(100);
        report "UPD7759_SELECTION_PASS exact_native_state_cycles=" & integer'image(vint_checks) &
            " corrected_silence_first_pcm_cycle=" & integer'image(vint_onset);
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 1 ms;
        assert (false) report "ADPCM selection test timed out" severity failure;
        wait;
    end process;
end architecture;
