-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Ordered single-beat DDR save transport, including the standard host header.
-- Parent supplies a complete, immutable board payload (header first). Success
-- means DDR command acceptance, not host polling or SD durability. Canceled
-- saves invalidate their slot before overwriting any payload bytes.
entity rabbitpunch_state_slot_writer is
    generic (
        GINT_PAYLOAD_BYTES : positive
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        iu2_slot : in unsigned(1 downto 0);
        i_payload_valid : in std_logic;
        o_payload_ready : out std_logic;
        iu64_payload_data : in unsigned(63 downto 0);
        o_active : out std_logic;
        o_finished : out std_logic;
        o_success : out std_logic;
        o_error : out std_logic;
        o_ddr_read : out std_logic;
        o_ddr_write : out std_logic;
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_write_data : out unsigned(63 downto 0);
        i_ddr_busy : in std_logic;
        i_ddr_read_valid : in std_logic;
        iu64_ddr_read_data : in unsigned(63 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_slot_writer is
    type t_state is (STATE_IDLE, STATE_READ, STATE_WAIT, STATE_INVALIDATE, STATE_STREAM, STATE_COMMIT, STATE_DRAIN);
    signal styp_state : t_state := STATE_IDLE;
    signal su29_base : unsigned(28 downto 0) := (others => '0');
    signal su15_index : unsigned(14 downto 0) := (others => '0');
    signal su32_counter : unsigned(31 downto 0) := (others => '0');
    signal su32_previous_counter : unsigned(31 downto 0) := (others => '0');
    signal s_error, s_report_abort : std_logic := '0';
begin
    assert (GINT_PAYLOAD_BYTES >= 64 and GINT_PAYLOAD_BYTES <= 262136 and
        GINT_PAYLOAD_BYTES mod 8 = 0) report "Invalid state slot payload size" severity failure;
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    o_error <= s_error;
    o_payload_ready <= '1' when styp_state = STATE_STREAM and i_ddr_busy = '0' and
        i_initialize = '0' and i_cancel = '0' else '0';
    commands : process(all)
    begin
        o_ddr_read <= '0';
        o_ddr_write <= '0';
        ou29_ddr_word_address <= su29_base;
        ou64_ddr_write_data <= iu64_payload_data;
        if (i_initialize = '0' and i_cancel = '0' and i_ddr_busy = '0') then
            case styp_state is
                when STATE_READ =>
                    o_ddr_read <= '1';
                when STATE_STREAM =>
                    o_ddr_write <= i_payload_valid;
                    ou29_ddr_word_address <= su29_base + 1 + resize(su15_index, 29);
                when STATE_INVALIDATE =>
                    o_ddr_write <= '1';
                    ou64_ddr_write_data <= to_unsigned(0, 32) & su32_previous_counter;
                when STATE_COMMIT =>
                    o_ddr_write <= '1';
                    ou64_ddr_write_data <= to_unsigned(GINT_PAYLOAD_BYTES/4, 32) & su32_counter;
                when others =>
                    null;
            end case;
        end if;
    end process;
    transfer : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_success <= '0';
            if (i_initialize = '1' or i_cancel = '1') then
                if (i_initialize = '1') then
                    s_error <= '0';
                    s_report_abort <= '0';
                else
                    s_error <= '1';
                    s_report_abort <= '1';
                end if;
                if ((styp_state = STATE_WAIT or styp_state = STATE_DRAIN) and i_ddr_read_valid = '0') then
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
                            s_error <= '0';
                            s_report_abort <= '0';
                            styp_state <= STATE_READ;
                        end if;
                    when STATE_READ =>
                        if (i_ddr_busy = '0') then
                            styp_state <= STATE_WAIT;
                        end if;
                    when STATE_WAIT =>
                        if (i_ddr_read_valid = '1') then
                            su32_previous_counter <= iu64_ddr_read_data(31 downto 0);
                            -- FFFFFFFF is the host's startup sentinel; never
                            -- publish it, including on increment wraparound.
                            if (iu64_ddr_read_data(31 downto 0) >= x"FFFFFFFE") then
                                su32_counter <= (others => '0');
                            else
                                su32_counter <= iu64_ddr_read_data(31 downto 0) + 1;
                            end if;
                            styp_state <= STATE_INVALIDATE;
                        end if;
                    when STATE_INVALIDATE =>
                        if (i_ddr_busy = '0') then
                            styp_state <= STATE_STREAM;
                        end if;
                    when STATE_STREAM =>
                        if (i_payload_valid = '1' and i_ddr_busy = '0') then
                            if (su15_index = GINT_PAYLOAD_BYTES/8 - 1) then
                                styp_state <= STATE_COMMIT;
                            else
                                su15_index <= su15_index + 1;
                            end if;
                        end if;
                    when STATE_COMMIT =>
                        if (i_ddr_busy = '0') then
                            o_finished <= '1';
                            o_success <= '1';
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
