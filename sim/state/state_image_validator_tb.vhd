-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;

entity state_image_validator_tb is
end entity;

architecture test of state_image_validator_tb is
    -- Independent Python struct/zlib headers for the complete107216-byte
    -- fixture body. The second has a CRC-valid but illegal68000 SR.
    constant CU512_HEADER : unsigned(511 downto 0) :=
        x"000000007CE5061A00000018000001F80000004000000020000000600001A0000001A31090ABCDEF4D04ED9B0001A2D055667788102030400040000131535052";
    constant CU512_BAD_SR_HEADER : unsigned(511 downto 0) :=
        x"000000000368D9BC00000018000001F80000004000000020000000600001A0000001A31090ABCDEF677046A70001A2D055667788102030400040000131535052";
    signal s_clk : std_logic := '0';
    signal s_initialize, s_start, s_cancel, s_begin, s_fill, s_seal : std_logic := '0';
    signal s_fill_ready, s_sealed, s_buffer_error, s_read, s_raw_response, s_raw_error : std_logic;
    signal su8_fill, su8_raw, su8_pipe0, su8_pipe1 : unsigned(7 downto 0) := (others => '0');
    signal su18_address, su18_count, su18_last_address, su18_pipe0_address, su18_pipe1_address :
        unsigned(17 downto 0) := (others => '0');
    signal s_pipe0, s_pipe1, s_pipe0_error, s_pipe1_error, s_error : std_logic := '0';
    signal s_active, s_finished, s_valid : std_logic;
    signal su6_error : unsigned(5 downto 0);
    signal su32_rom : unsigned(31 downto 0) := x"55667788";
    signal sint_case : natural := 0;
    function F_BYTE(vint_address, vint_case : natural) return unsigned is
        variable vint_body, vint_word, vint_lane : natural;
        variable vu512_header : unsigned(511 downto 0);
        variable vu32_word : unsigned(31 downto 0) := (others => '0');
    begin
        if (vint_address < 64) then
            vu512_header := CU512_HEADER;
            if (vint_case = 1) then
                vu512_header := CU512_BAD_SR_HEADER;
            end if;
            return vu512_header(8*vint_address + 7 downto 8*vint_address);
        end if;
        vint_body := vint_address - 64;
        if (vint_body < CINT_RAM_BYTES) then
            if (vint_case = 2 and vint_body = 42) then
                return to_unsigned(43, 8);
            end if;
            return to_unsigned(vint_body mod 256, 8);
        elsif (vint_body < CINT_T80_BASE) then
            vint_word := (vint_body - CINT_M68K_BASE)/4;
            vint_lane := (vint_body - CINT_M68K_BASE) mod 4;
            case vint_word is
                when 18 => vu32_word := x"000FF7FA";
                when 19 =>
                    if (vint_case = 1) then
                        vu32_word := x"00002800";
                    else
                        vu32_word := x"00002000";
                    end if;
                when 20 => vu32_word := x"00000400";
                when others => null;
            end case;
            return vu32_word(8*vint_lane + 7 downto 8*vint_lane);
        end if;
        return x"00";
    end function;
begin
    s_clk <= not s_clk after 5 ns;
    s_error <= '1' when s_pipe1 = '1' and sint_case = 7 and su18_pipe1_address = 32 else s_pipe1_error;
    validator : entity work.rabbitpunch_state_image_validator
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            i_image_sealed => s_sealed,
            i_rom_identity_valid => '1',
            iu32_abi_signature => x"10203040",
            iu32_rom_identity => su32_rom,
            iu32_config_identity => x"90ABCDEF",
            o_image_read => s_read,
            ou18_image_address => su18_address,
            i_image_response => s_pipe1,
            i_image_error => s_error,
            iu8_image_data => su8_pipe1,
            o_active => s_active,
            o_finished => s_finished,
            o_valid => s_valid,
            ou6_error => su6_error
        );
    image : entity work.rabbitpunch_state_image_buffer
        generic map (
            GINT_IMAGE_BYTES => CINT_IMAGE_BYTES
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_begin => s_begin,
            i_cancel => '0',
            i_fill_valid => s_fill,
            o_fill_ready => s_fill_ready,
            iu8_fill_data => su8_fill,
            i_seal => s_seal,
            o_sealed => s_sealed,
            o_error => s_buffer_error,
            ou18_filled_bytes => su18_count,
            i_read_valid => s_read,
            iu18_read_address => su18_address,
            o_read_response => s_raw_response,
            o_read_error => s_raw_error,
            ou8_read_data => su8_raw
        );
    -- Extra registered read latency injects genuine owed response debt. It
    -- continues retiring accepted requests during cancel/gameplay reset.
    read_pipeline : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_read = '1') then
                su18_last_address <= su18_address;
            end if;
            s_pipe0 <= '0';
            if (s_raw_response = '1') then
                s_pipe0 <= '1';
            end if;
            su8_pipe0 <= su8_raw;
            s_pipe0_error <= s_raw_error;
            su18_pipe0_address <= su18_last_address;
            s_pipe1 <= s_pipe0;
            su8_pipe1 <= su8_pipe0;
            s_pipe1_error <= s_pipe0_error;
            su18_pipe1_address <= su18_pipe0_address;
        end if;
    end process;
    stimulus : process
        variable vu6_expected : unsigned(5 downto 0);
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        for vint_case in 0 to 8 loop
            sint_case <= vint_case;
            su32_rom <= x"55667788";
            s_begin <= '1';
            cycles;
            s_begin <= '0';
            wait for 1 ns;
            if (vint_case /= 4) then
                for vint_byte in 0 to CINT_IMAGE_BYTES - 1 loop
                    assert (s_fill_ready = '1') severity failure;
                    su8_fill <= F_BYTE(vint_byte, vint_case);
                    s_fill <= '1';
                    if (vint_byte = CINT_IMAGE_BYTES - 1) then
                        s_seal <= '1';
                    end if;
                    cycles;
                end loop;
                s_fill <= '0';
                s_seal <= '0';
                assert (s_sealed = '1' and s_buffer_error = '0') severity failure;
            end if;
            if (vint_case = 3) then
                su32_rom <= x"DEADBEEF";
            end if;
            s_start <= '1';
            cycles;
            s_start <= '0';
            if (vint_case = 5 or vint_case = 8) then
                while (s_read = '0') loop
                    cycles;
                end loop;
                cycles;
                assert (s_pipe1 = '0') severity failure;
                if (vint_case = 5) then
                    s_cancel <= '1';
                else
                    s_initialize <= '1';
                end if;
                cycles;
                s_cancel <= '0';
                s_initialize <= '0';
                assert (s_active = '1') report "Validator discarded accepted read debt" severity failure;
            end if;
            for vint_timeout in 0 to 999999 loop
                exit when s_finished = '1' or (vint_case = 8 and s_active = '0');
                cycles;
                assert (vint_timeout < 999999) report "Image validation stalled" severity failure;
            end loop;
            vu6_expected := (others => '0');
            case vint_case is
                when 1 => vu6_expected := to_unsigned(34, 6);
                when 2 => vu6_expected := to_unsigned(23, 6);
                when 3 => vu6_expected := to_unsigned(20, 6);
                when 4 => vu6_expected := to_unsigned(48, 6);
                when 5 => vu6_expected := to_unsigned(50, 6);
                when 7 => vu6_expected := to_unsigned(49, 6);
                when others => null;
            end case;
            assert (su6_error = vu6_expected)
                report "Wrong combined validation error case=" & integer'image(vint_case) &
                " value=" & to_hstring(su6_error) severity failure;
            if (vint_case = 0 or vint_case = 6) then
                assert (s_valid = '1') severity failure;
                su32_rom <= x"12345678";
                wait for 1 ns;
                assert (s_valid = '0') report "Stale ROM identity retained apply permission" severity failure;
                su32_rom <= x"55667788";
            else
                assert (s_valid = '0') severity failure;
            end if;
            cycles(3);
        end loop;
        report "STATE_IMAGE_VALIDATOR_PASS full private image,CRC-valid badSR,CRC/identity rejection,unsealed source,cancel/reset debt,read error,retry" severity note;
        stop;
        wait;
    end process;
end architecture;
