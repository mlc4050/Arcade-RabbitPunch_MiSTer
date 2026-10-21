-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Copy an external slot into private staging, never directly into game state.
-- Recheck its outer header after receipt; the parent seals only on success,
-- then validates CRC/identity/semantics from the immutable private copy.
entity rabbitpunch_state_slot_reader is
    generic (
        GINT_PAYLOAD_BYTES : positive
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        iu2_slot : in unsigned(1 downto 0);
        o_byte_valid : out std_logic;
        i_byte_ready : in std_logic;
        ou8_byte_data : out unsigned(7 downto 0);
        o_active : out std_logic;
        o_finished : out std_logic;
        o_success : out std_logic;
        ou3_error : out unsigned(2 downto 0);
        o_ddr_read : out std_logic;
        ou29_ddr_word_address : out unsigned(28 downto 0);
        i_ddr_busy : in std_logic;
        i_ddr_read_valid : in std_logic;
        iu64_ddr_read_data : in unsigned(63 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_slot_reader is
    type t_state is (STATE_IDLE, STATE_HEADER, STATE_WAIT_HEADER, STATE_PAYLOAD,
        STATE_WAIT_PAYLOAD, STATE_BYTES, STATE_CHECK, STATE_WAIT_CHECK, STATE_DRAIN);
    signal styp_state : t_state := STATE_IDLE;
    signal su29_base : unsigned(28 downto 0) := (others => '0');
    signal su15_index : unsigned(14 downto 0) := (others => '0');
    signal su3_byte : unsigned(2 downto 0) := (others => '0');
    signal su64_control, su64_data : unsigned(63 downto 0) := (others => '0');
    signal su3_error : unsigned(2 downto 0) := (others => '0');
    signal s_report_abort : std_logic := '0';
begin
    assert (GINT_PAYLOAD_BYTES >= 64 and GINT_PAYLOAD_BYTES <= 262136 and
        GINT_PAYLOAD_BYTES mod 8 = 0) report "Invalid state slot payload size" severity failure;
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    ou3_error <= su3_error;
    o_byte_valid <= '1' when styp_state = STATE_BYTES and i_initialize = '0' and i_cancel = '0' else '0';
    ou8_byte_data <= su64_data(8*to_integer(su3_byte) + 7 downto 8*to_integer(su3_byte));
    o_ddr_read <= '1' when (styp_state = STATE_HEADER or styp_state = STATE_PAYLOAD or
        styp_state = STATE_CHECK) and i_ddr_busy = '0' and i_initialize = '0' and i_cancel = '0' else '0';
    ou29_ddr_word_address <= su29_base + 1 + resize(su15_index, 29) when
        styp_state = STATE_PAYLOAD else su29_base;
    receive_image : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_success <= '0';
            if (i_initialize = '1' or i_cancel = '1') then
                if (i_initialize = '1') then
                    su3_error <= (others => '0');
                    s_report_abort <= '0';
                else
                    su3_error <= to_unsigned(4, 3);
                    s_report_abort <= '1';
                end if;
                if ((styp_state = STATE_WAIT_HEADER or styp_state = STATE_WAIT_PAYLOAD or
                    styp_state = STATE_WAIT_CHECK or styp_state = STATE_DRAIN) and i_ddr_read_valid = '0') then
                    styp_state <= STATE_DRAIN;
                else
                    if (styp_state /= STATE_IDLE and i_initialize = '0') then
                        o_finished <= '1';
                    end if;
                    styp_state <= STATE_IDLE;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_start = '1') then
                            su29_base <= to_unsigned(16#07C00000#, 29) +
                                shift_left(resize(iu2_slot, 29), 15);
                            su15_index <= (others => '0');
                            su3_error <= (others => '0');
                            s_report_abort <= '0';
                            styp_state <= STATE_HEADER;
                        end if;
                    when STATE_HEADER =>
                        if (i_ddr_busy = '0') then
                            styp_state <= STATE_WAIT_HEADER;
                        end if;
                    when STATE_WAIT_HEADER =>
                        if (i_ddr_read_valid = '1') then
                            -- ARM marks every file-loaded slot FFFFFFFF.
                            -- Length, then the full private preflight, decide
                            -- validity; the counter only detects concurrent
                            -- replacement during this acknowledged copy.
                            if (iu64_ddr_read_data(63 downto 32) = 0) then
                                su3_error <= to_unsigned(1, 3);
                                o_finished <= '1';
                                styp_state <= STATE_IDLE;
                            elsif (iu64_ddr_read_data(63 downto 32) /= GINT_PAYLOAD_BYTES/4) then
                                su3_error <= to_unsigned(2, 3);
                                o_finished <= '1';
                                styp_state <= STATE_IDLE;
                            else
                                su64_control <= iu64_ddr_read_data;
                                styp_state <= STATE_PAYLOAD;
                            end if;
                        end if;
                    when STATE_PAYLOAD =>
                        if (i_ddr_busy = '0') then
                            styp_state <= STATE_WAIT_PAYLOAD;
                        end if;
                    when STATE_WAIT_PAYLOAD =>
                        if (i_ddr_read_valid = '1') then
                            su64_data <= iu64_ddr_read_data;
                            su3_byte <= (others => '0');
                            styp_state <= STATE_BYTES;
                        end if;
                    when STATE_BYTES =>
                        if (i_byte_ready = '1') then
                            if (su3_byte = 7) then
                                if (su15_index = GINT_PAYLOAD_BYTES/8 - 1) then
                                    styp_state <= STATE_CHECK;
                                else
                                    su15_index <= su15_index + 1;
                                    styp_state <= STATE_PAYLOAD;
                                end if;
                            else
                                su3_byte <= su3_byte + 1;
                            end if;
                        end if;
                    when STATE_CHECK =>
                        if (i_ddr_busy = '0') then
                            styp_state <= STATE_WAIT_CHECK;
                        end if;
                    when STATE_WAIT_CHECK =>
                        if (i_ddr_read_valid = '1') then
                            o_finished <= '1';
                            if (iu64_ddr_read_data = su64_control) then
                                o_success <= '1';
                            else
                                su3_error <= to_unsigned(3, 3);
                            end if;
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAIN =>
                        if (i_ddr_read_valid = '1') then
                            o_finished <= s_report_abort;
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
