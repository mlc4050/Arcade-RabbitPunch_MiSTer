-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity sound_fast_fixture is
    generic (
        GINT_WRITE_LIMIT : positive := 4096
    );
    port (
        i_clk : in std_logic;
        o_write : out std_logic := '0';
        ou16_address : out unsigned(15 downto 0);
        ou8_data : out unsigned(7 downto 0);
        o_complete : out std_logic := '0'
    );
end entity;
architecture test of sound_fast_fixture is
    type t_rom is array (0 to 65535) of unsigned(7 downto 0);
    impure function load_rom return t_rom is
        file v_rom_file : text open read_mode is "audio_rom.hex";
        variable v_line : line;
        variable v_rom : t_rom;
    begin
        for vint_address in v_rom'range loop
            readline(v_rom_file, v_line);
            hread(v_line, v_rom(vint_address));
        end loop;
        return v_rom;
    end function;
    constant C_ROM : t_rom := load_rom;
    signal s_reset : std_logic := '1';
    signal s_pause : std_logic := '0';
    signal s_paused, s_enable, s_half_enable : std_logic;
    signal s_request, s_write, s_rom_request : std_logic;
    signal s_rom_response : std_logic := '0';
    signal su16_address, su16_rom_address : unsigned(15 downto 0);
    signal su8_data, su8_rom_data : unsigned(7 downto 0);
    signal sint_cycles : natural range 0 to 20000000 := 0;
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_writes : natural range 0 to GINT_WRITE_LIMIT + 1 := 0;
    signal sint_delayed_reads : natural := 0;
begin
    s_enable <= '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_half_enable <= '1' when sint_divider = 23 else '0';
    board : entity work.rabbitpunch_sound_board
        port map (
            i_clk => i_clk,
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
    monitor : process(i_clk)
        variable vint_quiet : natural range 0 to 96 := 0;
    begin
        if (rising_edge(i_clk)) then
            sint_cycles <= sint_cycles + 1;
            if (sint_cycles = 96) then
                s_reset <= '0';
            end if;
            if (sint_divider = 23) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            o_write <= '0';
            if (s_request = '1' and s_write = '1') then
                assert (sint_writes < GINT_WRITE_LIMIT) report "Fast sound CPU wrote beyond pause boundary" severity failure;
                o_write <= '1';
                ou16_address <= su16_address;
                ou8_data <= su8_data;
                sint_writes <= sint_writes + 1;
            end if;
            if (sint_writes = GINT_WRITE_LIMIT) then
                s_pause <= '1';
                if (s_paused = '1') then
                    assert (sint_delayed_reads > 0) report "Fast sound test missed delayed ROM reads" severity failure;
                    if (vint_quiet = 96) then
                        o_complete <= '1';
                    else
                        vint_quiet := vint_quiet + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    rom_transport : process(i_clk)
        variable v_pending : boolean := false;
        variable vint_delay : natural range 0 to 53 := 0;
        variable vint_requests : natural := 0;
        variable vu8_reply : unsigned(7 downto 0);
    begin
        if (rising_edge(i_clk)) then
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
                assert (not v_pending and su16_rom_address < x"F000")
                    report "Fast sound board overlapped or misdecoded a ROM read" severity failure;
                vint_requests := vint_requests + 1;
                vu8_reply := C_ROM(to_integer(su16_rom_address));
                vint_delay := 0;
                if (vint_requests mod 31 = 0) then
                    vint_delay := 53;
                    sint_delayed_reads <= sint_delayed_reads + 1;
                end if;
                v_pending := true;
            end if;
        end if;
    end process;
end architecture;
