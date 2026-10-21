-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity adpcm_wrapper_state_tb is
end entity;

architecture test of adpcm_wrapper_state_tb is
    type t_words is array(0 to 5) of unsigned(31 downto 0);
    type t_trace is array(0 to 1023) of unsigned(45 downto 0);
    function F_MASK(vint_word : natural) return unsigned is
    begin
        if (vint_word = 5) then
            return unsigned'(x"1FFFFFFF");
        end if;
        return unsigned'(x"FFFFFFFF");
    end function;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_control, s_command, s_hold, s_load, s_chip_load, s_phase_load : std_logic := '0';
    signal s_run : std_logic := '0';
    signal s_enable, s_busy, s_request, s_rom_valid, s_bank, s_chip_reset : std_logic;
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal su8_rom_data : unsigned(7 downto 0);
    signal su8_phase, su8_restore_phase : unsigned(7 downto 0) := (others => '0');
    signal su18_rom_address : unsigned(17 downto 0);
    signal su9_pcm : unsigned(8 downto 0);
    signal su16_state, su16_write_state, su16_word : unsigned(15 downto 0) := (others => '0');
    signal su32_write, su32_read : unsigned(31 downto 0) := (others => '0');
    signal su46_observed : unsigned(45 downto 0);
    function F_ROM(vu18_address : unsigned(17 downto 0)) return unsigned is
    begin
        case to_integer(vu18_address(16 downto 0)) is
            when 0 => return x"00";
            when 1 => return x"5A";
            when 2 => return x"A5";
            when 3 => return x"69";
            when 4 => return x"55";
            when 5 => return x"00";
            when 6 => return x"20";
            when 16#41# => return x"89";
            when 16#42# => return x"1F";
            when 16#43# to 16#52# => return to_unsigned(16#17# + to_integer(vu18_address(3 downto 0)), 8);
            when others => return x"00";
        end case;
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= s_run when su8_phase(1 downto 0) = 3 else '0';
    s_rom_valid <= s_request when su8_phase(3 downto 0) >= 5 else '0';
    su8_rom_data <= F_ROM(su18_rom_address) when not is_x(su18_rom_address) else x"00";
    su46_observed <= s_request & s_busy & s_bank & s_chip_reset & su18_rom_address & su9_pcm & su16_state(14 downto 0);
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
    adpcm : entity work.rabbitpunch_adpcm
        generic map (
            GBOOL_STATE_CAPABLE => true
        )
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_control_write => s_control,
            i_command_write => s_command,
            iu8_write_data => su8_data,
            o_busy => s_busy,
            o_rom_request => s_request,
            ou18_rom_address => su18_rom_address,
            i_rom_valid => s_rom_valid,
            iu8_rom_data => su8_rom_data,
            ou9_pcm => su9_pcm,
            o_bank => s_bank,
            o_reset_asserted => s_chip_reset,
            i_state_hold => s_hold,
            i_state_load => s_load,
            iu16_state => su16_write_state,
            ou16_state => su16_state,
            i_chip_state_write => s_chip_load,
            iu16_chip_state_word_address => su16_word,
            iu32_chip_state_write_data => su32_write,
            ou32_chip_state_read_data => su32_read
        );
    stimulus : process
        variable vu32_image : t_words;
        variable vu46_trace : t_trace;
        variable vu16_image : unsigned(15 downto 0);
        variable vu8_phase : unsigned(7 downto 0);
        variable vint_nonzero : natural := 0;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        for vint_case in 0 to 2 loop
            s_reset <= '1';
            s_run <= '0';
            cycles(40);
            s_reset <= '0';
            su8_data <= x"81";
            s_control <= '1';
            cycles;
            s_control <= '0';
            if (vint_case /= 0) then
                s_run <= '1';
                cycles(20);
            end if;
            su8_data <= x"00";
            s_command <= '1';
            cycles;
            s_command <= '0';
            if (vint_case = 2) then
                cycles(3000);
            end if;
            s_hold <= '1';
            cycles;
            vu16_image := su16_state;
            vu8_phase := su8_phase;
            assert (s_request = '0') report "Held ADPCM leaked ROM request" severity failure;
            if (vint_case < 2) then
                assert (su16_state(1 downto 0) = vint_case + 1)
                    report "Pending command fixture missed WAITING/START" severity failure;
            end if;
            for vint_word in 0 to 5 loop
                su16_word <= to_unsigned(vint_word, 16);
                cycles;
                vu32_image(vint_word) := su32_read;
                assert (not is_x(su32_read)) severity failure;
            end loop;
            s_hold <= '0';
            s_run <= '1';
            wait for 1 ns;
            for vint_cycle in vu46_trace'range loop
                vu46_trace(vint_cycle) := su46_observed;
                if (su9_pcm /= 0) then
                    vint_nonzero := vint_nonzero + 1;
                end if;
                cycles;
            end loop;
            for vint_round in 1 to 3 loop
                cycles(113);
                s_hold <= '1';
                cycles;
                su16_write_state <= vu16_image xor x"1FFC";
                s_load <= '1';
                cycles;
                s_load <= '0';
                assert (su16_state = (vu16_image xor x"1FFC")) severity failure;
                for vint_word in 0 to 5 loop
                    su16_word <= to_unsigned(vint_word, 16);
                    su32_write <= (not vu32_image(vint_word)) and F_MASK(vint_word);
                    s_chip_load <= '1';
                    cycles;
                end loop;
                s_chip_load <= '0';
                assert (s_request = '0') severity failure;
                for vint_word in 0 to 5 loop
                    su16_word <= to_unsigned(vint_word, 16);
                    cycles;
                    assert (su32_read = ((not vu32_image(vint_word)) and F_MASK(vint_word))) severity failure;
                end loop;
                su16_write_state <= vu16_image;
                s_load <= '1';
                cycles;
                s_load <= '0';
                for vint_word in 0 to 5 loop
                    su16_word <= to_unsigned(vint_word, 16);
                    su32_write <= vu32_image(vint_word);
                    s_chip_load <= '1';
                    cycles;
                end loop;
                s_chip_load <= '0';
                su8_restore_phase <= vu8_phase;
                s_phase_load <= '1';
                cycles;
                s_phase_load <= '0';
                s_hold <= '0';
                wait for 1 ns;
                for vint_cycle in vu46_trace'range loop
                    assert (su46_observed = vu46_trace(vint_cycle))
                        report "ADPCM wrapper continuation differs case=" & integer'image(vint_case) &
                        " cycle=" & integer'image(vint_cycle) severity failure;
                    cycles;
                end loop;
            end loop;
        end loop;
        assert (vint_nonzero > 0) report "Wrapper fixture never reached nonzero PCM" severity failure;
        -- A real gameplay reset dominates an interrupted scan load. Internal
        -- control reset remains masked during ordinary loading, separately.
        s_hold <= '1';
        cycles;
        for vint_word in 0 to 5 loop
            su16_word <= to_unsigned(vint_word, 16);
            su32_write <= (others => '1');
            s_chip_load <= '1';
            cycles;
        end loop;
        s_chip_load <= '0';
        s_reset <= '1';
        cycles(4);
        assert (su16_state = x"0008" and su9_pcm = 0 and s_busy = '0' and s_request = '0')
            report "Gameplay reset lost priority over held partial chip load" severity failure;
        s_reset <= '0';
        cycles(4);
        assert (su16_state = x"0008" and su9_pcm = 0 and s_request = '0') severity failure;
        report "ADPCM_WRAPPER_STATE_PASS pending WAITING/START,bank/reset/command,state complement,masked ROM,nine1024-clock continuations,reset during partial scan" severity note;
        stop;
        wait;
    end process;
end architecture;
