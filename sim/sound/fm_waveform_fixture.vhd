-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fm_waveform_fixture is
    port (
        i_clk : in std_logic;
        o_sample : out std_logic := '0';
        o_complete : out std_logic := '0';
        ou16_left : out unsigned(15 downto 0);
        ou16_right : out unsigned(15 downto 0);
        ou16_full_left : out unsigned(15 downto 0);
        ou16_full_right : out unsigned(15 downto 0)
    );
end entity;

architecture test of fm_waveform_fixture is
    type t_state is (STATE_RESET, STATE_ADDRESS, STATE_ADDRESS_GAP,
        STATE_DATA, STATE_BUSY, STATE_SETTLE, STATE_CAPTURE, STATE_DONE);
    signal styp_state : t_state := STATE_RESET;
    signal sint_delay : natural range 0 to 4096 := 4096;
    signal sint_register : natural range 0 to 283 := 0;
    signal sint_sample_delay : natural range 0 to 4 := 0;
    signal sint_samples : natural range 0 to 288 := 0;
    signal sint_nonzero : natural range 0 to 256 := 0;
    signal s_reset : std_logic := '1';
    signal s_chip_enable, s_half_enable, s_marker : std_logic;
    signal s_previous_marker : std_logic := '0';
    signal s_write, s_data_register : std_logic := '0';
    signal su8_write_data : unsigned(7 downto 0) := (others => '0');
    signal su8_status : unsigned(7 downto 0);
    signal su16_left, su16_right, su16_full_left, su16_full_right : unsigned(15 downto 0);

    -- Initialize every register explicitly; then key four parallel carriers on
    -- channel zero. This checks transport/tool agreement, not board analog tone.
    function register_word(vint_index : natural) return unsigned is
        variable vint_operator, vint_parameter, vint_address, vint_data : natural;
    begin
        if (vint_index < 256) then
            return to_unsigned(vint_index * 256, 16);
        elsif (vint_index < 280) then
            vint_operator := (vint_index - 256) / 6;
            vint_parameter := (vint_index - 256) mod 6;
            vint_address := 16#40# + vint_parameter * 32 + vint_operator * 8;
            vint_data := 0;
            if (vint_parameter = 0) then
                vint_data := 1;
            elsif (vint_parameter = 2) then
                vint_data := 31;
            elsif (vint_parameter = 5) then
                vint_data := 15;
            end if;
            return to_unsigned(vint_address * 256 + vint_data, 16);
        end if;
        case vint_index is
            when 280 =>
                return x"20C7";
            when 281 =>
                return x"284A";
            when 282 =>
                return x"3000";
            when others =>
                return x"0878";
        end case;
    end function;

    function known(vux_value : unsigned) return boolean is
    begin
        for vint_bit in vux_value'range loop
            if (vux_value(vint_bit) /= '0' and vux_value(vint_bit) /= '1') then
                return false;
            end if;
        end loop;
        return true;
    end function;
begin
    ou16_left <= su16_left;
    ou16_right <= su16_right;
    ou16_full_left <= su16_full_left;
    ou16_full_right <= su16_full_right;
    enables : entity work.rabbitpunch_clock_enables
        port map (
            i_clk => i_clk,
            i_reset => '0',
            o_pixel_enable => open,
            o_main_phase_enable => open,
            o_sound_cpu_enable => s_chip_enable,
            o_ym_enable => open,
            o_ym_half_enable => s_half_enable,
            o_adpcm_enable => open
        );
    chip : entity work.rabbitpunch_ym2151
        port map (
            i_clk => i_clk,
            i_reset => s_reset,
            i_chip_enable => s_chip_enable,
            i_half_chip_enable => s_half_enable,
            i_chip_select => '1',
            i_write => s_write,
            i_data_register => s_data_register,
            iu8_write_data => su8_write_data,
            ou8_status => su8_status,
            o_interrupt => open,
            o_sample_marker => s_marker,
            ou16_left_pcm => su16_left,
            ou16_right_pcm => su16_right,
            ou16_full_left_pcm => su16_full_left,
            ou16_full_right_pcm => su16_full_right
        );
    stimulus : process(i_clk)
        variable vu16_register : unsigned(15 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_sample <= '0';
            s_previous_marker <= s_marker;
            vu16_register := register_word(sint_register);
            case styp_state is
                when STATE_RESET =>
                    if (sint_delay = 0) then
                        s_reset <= '0';
                        sint_delay <= 128;
                        styp_state <= STATE_ADDRESS;
                    else
                        sint_delay <= sint_delay - 1;
                    end if;
                when STATE_ADDRESS =>
                    s_data_register <= '0';
                    su8_write_data <= vu16_register(15 downto 8);
                    s_write <= '1';
                    if (sint_delay = 0) then
                        s_write <= '0';
                        sint_delay <= 64;
                        styp_state <= STATE_ADDRESS_GAP;
                    else
                        sint_delay <= sint_delay - 1;
                    end if;
                when STATE_ADDRESS_GAP =>
                    if (sint_delay = 0) then
                        s_data_register <= '1';
                        su8_write_data <= vu16_register(7 downto 0);
                        s_write <= '1';
                        sint_delay <= 128;
                        styp_state <= STATE_DATA;
                    else
                        sint_delay <= sint_delay - 1;
                    end if;
                when STATE_DATA =>
                    if (sint_delay = 0) then
                        s_write <= '0';
                        sint_delay <= 1024;
                        styp_state <= STATE_BUSY;
                    else
                        sint_delay <= sint_delay - 1;
                    end if;
                when STATE_BUSY =>
                    if (sint_delay = 0) then
                        assert (su8_status(7) = '0')
                            report "FM waveform busy flag stuck" severity failure;
                        if (sint_register = 283) then
                            styp_state <= STATE_SETTLE;
                        else
                            sint_register <= sint_register + 1;
                            sint_delay <= 128;
                            styp_state <= STATE_ADDRESS;
                        end if;
                    else
                        sint_delay <= sint_delay - 1;
                    end if;
                when STATE_SETTLE | STATE_CAPTURE =>
                    if (s_marker = '1' and s_previous_marker = '0') then
                        sint_sample_delay <= 4;
                    elsif (sint_sample_delay > 0) then
                        sint_sample_delay <= sint_sample_delay - 1;
                        if (sint_sample_delay = 1) then
                            if (styp_state = STATE_SETTLE) then
                                if (sint_samples = 31) then
                                    sint_samples <= 0;
                                    styp_state <= STATE_CAPTURE;
                                else
                                    sint_samples <= sint_samples + 1;
                                end if;
                            else
                                assert (known(su16_left) and known(su16_right) and
                                    known(su16_full_left) and known(su16_full_right))
                                    report "Keyed FM produced unknown PCM" severity failure;
                                assert (su16_left = su16_right and su16_full_left = su16_full_right)
                                    report "Symmetric FM pan differs between channels" severity failure;
                                o_sample <= '1';
                                if (su16_left /= 0) then
                                    sint_nonzero <= sint_nonzero + 1;
                                end if;
                                if (sint_samples = 255) then
                                    assert (sint_nonzero > 128)
                                        report "Keyed FM waveform was silent" severity failure;
                                    styp_state <= STATE_DONE;
                                else
                                    sint_samples <= sint_samples + 1;
                                end if;
                            end if;
                        end if;
                    end if;
                when STATE_DONE =>
                    o_complete <= '1';
            end case;
        end if;
    end process;
end architecture;
