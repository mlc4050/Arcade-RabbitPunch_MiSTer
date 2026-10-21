-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity adpcm_netlist_state_tb is
    generic (
        GBOOL_CORRECTED : boolean := false;
        GINT_STATE_BITS : positive := 192
    );
end entity;

architecture test of adpcm_netlist_state_tb is
    type t_words is array(0 to (GINT_STATE_BITS + 31) / 32 - 1) of unsigned(31 downto 0);
    function F_MASK(vint_word : natural) return unsigned is
        variable vu32_mask : unsigned(31 downto 0) := (others => '0');
    begin
        for vint_bit in 0 to 31 loop
            if (vint_word * 32 + vint_bit < GINT_STATE_BITS) then
                vu32_mask(vint_bit) := '1';
            end if;
        end loop;
        return vu32_mask;
    end function;
    type t_trace is array(0 to 4095) of unsigned(28 downto 0);
    component jt7759 is
        port (
            rst, clk, cen, stn, cs, mdn : in std_logic;
            busyn : out std_logic;
            wrn : in std_logic;
            din : in unsigned(7 downto 0);
            drqn, rom_cs : out std_logic;
            rom_addr : out unsigned(16 downto 0);
            rom_data : in unsigned(7 downto 0);
            rom_ok : in std_logic;
            sound : out unsigned(8 downto 0)
        );
    end component;
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
            when 16#41# => return x"89";
            when 16#42# => return x"1F";
            when 16#43# to 16#52# => return to_unsigned(16#17# + to_integer(vu17_address(3 downto 0)), 8);
            when others => return x"00";
        end case;
    end function;
    signal s_clk : std_logic := '0';
    signal s_reset, s_start_n : std_logic := '1';
    signal s_hold, s_load, s_phase_load, s_compare_native : std_logic := '0';
    signal su8_phase, su8_restore_phase : unsigned(7 downto 0) := (others => '0');
    signal s_enable, s_rom_valid : std_logic;
    signal s_busy_n, s_request, s_data_request_n : std_logic;
    signal s_native_busy_n, s_native_request, s_native_data_request_n : std_logic;
    signal s_native_busy : std_logic;
    signal su17_address, su17_native_address : unsigned(16 downto 0);
    signal su9_pcm, su9_native_pcm : unsigned(8 downto 0);
    signal su8_data, su8_native_data : unsigned(7 downto 0);
    signal su16_state_address : unsigned(15 downto 0) := (others => '0');
    signal su32_state_write, su32_state_read : unsigned(31 downto 0) := (others => '0');
    signal su29_observed, su29_native : unsigned(28 downto 0);
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when su8_phase(1 downto 0) = 3 and s_hold = '0' else '0';
    s_rom_valid <= '1' when su8_phase(3 downto 0) >= 5 else '0';
    su8_data <= F_ROM(su17_address) when not is_x(su17_address) else x"00";
    su8_native_data <= F_ROM(su17_native_address) when not is_x(su17_native_address) else x"00";
    su29_observed <= s_busy_n & s_request & s_data_request_n & su17_address & su9_pcm;
    su29_native <= s_native_busy_n & s_native_request & s_native_data_request_n & su17_native_address & su9_native_pcm;
    phase : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_phase_load = '1') then
                su8_phase <= su8_restore_phase;
            elsif (s_hold = '0') then
                su8_phase <= su8_phase + 1;
            end if;
        end if;
    end process;
    legacy_reference : if (not GBOOL_CORRECTED) generate
        native : jt7759
        port map (
            rst => s_reset,
            clk => s_clk,
            cen => s_enable,
            stn => s_start_n,
            cs => '1',
            mdn => '1',
            busyn => s_native_busy_n,
            wrn => '1',
            din => x"00",
            drqn => s_native_data_request_n,
            rom_cs => s_native_request,
            rom_addr => su17_native_address,
            rom_data => su8_native_data,
            rom_ok => s_rom_valid and s_native_request,
            sound => su9_native_pcm
        );
    end generate;
    corrected_reference : if (GBOOL_CORRECTED) generate
        s_native_busy_n <= not s_native_busy;
        native : entity work.rabbitpunch_corrected_adpcm_reference
            port map (
                i_clk => s_clk,
                i_reset => s_reset,
                i_enable => s_enable,
                i_start => not s_start_n,
                iu8_command => x"00",
                o_busy => s_native_busy,
                o_data_request_n => s_native_data_request_n,
                o_rom_request => s_native_request,
                ou17_rom_address => su17_native_address,
                i_rom_valid => s_rom_valid and s_native_request,
                iu8_rom_data => su8_native_data,
                ou9_pcm => su9_native_pcm
            );
    end generate;
    state_chip : entity work.rabbitpunch_jt7759_state_netlist
        port map (
            i_reset => s_reset,
            i_clk => s_clk,
            i_chip_enable => s_enable,
            i_start_n => s_start_n,
            i_chip_select => '1',
            i_standalone_mode => '1',
            o_busy_n => s_busy_n,
            i_write_n => '1',
            iu8_write_data => x"00",
            o_data_request_n => s_data_request_n,
            o_rom_request => s_request,
            ou17_rom_address => su17_address,
            iu8_rom_data => su8_data,
            i_rom_valid => s_rom_valid and s_request,
            ou9_pcm => su9_pcm,
            i_state_hold => s_hold,
            i_state_write => s_load,
            iu16_state_word_address => su16_state_address,
            iu32_state_write_data => su32_state_write,
            ou32_state_read_data => su32_state_read
        );
    stimulus : process
        variable vu32_image : t_words;
        variable vu29_trace : t_trace;
        variable vu8_saved_phase : unsigned(7 downto 0);
        variable vint_normal_checks : natural := 0;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
                if (s_compare_native = '1') then
                    assert (not is_x(su29_observed) and su29_observed = su29_native)
                        report "Generated ADPCM normal operation differs from pristine native chip" severity failure;
                    vint_normal_checks := vint_normal_checks + 1;
                end if;
            end loop;
        end procedure;
    begin
        cycles(100);
        s_compare_native <= '1';
        cycles(100);
        s_reset <= '0';
        cycles(200);
        s_start_n <= '0';
        cycles(16);
        s_start_n <= '1';
        for vint_wait in 0 to 10000 loop
            cycles;
            exit when (s_busy_n = '0' and su9_pcm /= 0);
        end loop;
        assert (s_busy_n = '0' and su9_pcm /= 0) report "ADPCM state fixture never played nonzero PCM" severity failure;
        s_compare_native <= '0';
        s_hold <= '1';
        cycles;
        vu8_saved_phase := su8_phase;
        for vint_word in vu32_image'range loop
            su16_state_address <= to_unsigned(vint_word, 16);
            cycles;
            assert (not is_x(su32_state_read)) report "Unknown ADPCM scan state" severity failure;
            vu32_image(vint_word) := su32_state_read;
        end loop;
        -- Every FF, including ungated controls and internally reset decoder
        -- state, must stay constant over a long hold.
        cycles(20);
        for vint_word in vu32_image'range loop
            su16_state_address <= to_unsigned(vint_word, 16);
            cycles;
            assert (su32_state_read = vu32_image(vint_word)) report "ADPCM freeze missed state" severity failure;
        end loop;
        s_hold <= '0';
        wait for 1 ns;
        for vint_cycle in vu29_trace'range loop
            vu29_trace(vint_cycle) := su29_observed;
            cycles;
        end loop;
        for vint_round in 1 to 3 loop
            cycles(1000 + vint_round);
            s_start_n <= '0';
            cycles(16);
            s_start_n <= '1';
            cycles(317);
            s_hold <= '1';
            cycles;
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                su32_state_write <= (not vu32_image(vint_word)) and F_MASK(vint_word);
                s_load <= '1';
                cycles;
            end loop;
            s_load <= '0';
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                cycles;
                assert (su32_state_read = ((not vu32_image(vint_word)) and F_MASK(vint_word))) report "ADPCM scan missed complemented state bit" severity failure;
            end loop;
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                su32_state_write <= vu32_image(vint_word);
                s_load <= '1';
                cycles;
            end loop;
            s_load <= '0';
            for vint_word in vu32_image'range loop
                su16_state_address <= to_unsigned(vint_word, 16);
                cycles;
                assert (su32_state_read = vu32_image(vint_word)) report "ADPCM scan round trip differs" severity failure;
            end loop;
            su8_restore_phase <= vu8_saved_phase;
            s_phase_load <= '1';
            cycles;
            s_phase_load <= '0';
            s_hold <= '0';
            wait for 1 ns;
            for vint_cycle in vu29_trace'range loop
                assert (not is_x(su29_observed) and su29_observed = vu29_trace(vint_cycle))
                    report "ADPCM immediate continuation differs at cycle " & integer'image(vint_cycle) severity failure;
                cycles;
            end loop;
        end loop;
        assert (vint_normal_checks > 1000) report "ADPCM native comparison too short" severity failure;
        report "ADPCM_NETLIST_STATE_PASS normal_native_cycles=" & integer'image(vint_normal_checks) &
            " state_bits=" & integer'image(GINT_STATE_BITS) &
            " repeated_restores=3 immediate_continuation_cycles=12288";
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 2 ms;
        assert (false) report "ADPCM netlist state test timed out" severity failure;
        wait;
    end process;
end architecture;
