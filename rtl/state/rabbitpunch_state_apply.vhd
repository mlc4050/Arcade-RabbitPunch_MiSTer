-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- Apply only the same immutable private image that passed full validation.
-- The parent retains its image lease and machine hold through final CPU return
-- preparation. Once a write is accepted, cancellation cannot release a partial
-- machine: o_incomplete remains set until a complete retry or full game reset.
entity rabbitpunch_state_apply is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_reset_completed : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        i_image_valid : in std_logic;
        i_machine_held : in std_logic;
        o_machine_hold_request : out std_logic;
        o_image_read : out std_logic;
        ou18_image_address : out unsigned(17 downto 0);
        i_image_response : in std_logic;
        i_image_error : in std_logic;
        iu8_image_data : in unsigned(7 downto 0);
        o_body_request : out std_logic;
        i_body_ready : in std_logic;
        ou18_body_address : out unsigned(17 downto 0);
        ou8_body_data : out unsigned(7 downto 0);
        i_body_response : in std_logic;
        i_body_error : in std_logic;
        o_body_commit : out std_logic;
        i_body_committed : in std_logic;
        i_body_commit_error : in std_logic := '0';
        o_active : out std_logic;
        o_finished : out std_logic;
        o_success : out std_logic;
        o_incomplete : out std_logic;
        ou4_error : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_apply is
    type t_state is (STATE_IDLE, STATE_READ, STATE_READ_WAIT, STATE_WRITE,
        STATE_WRITE_WAIT, STATE_COMMIT, STATE_COMMIT_WAIT, STATE_FAIL,
        STATE_DRAIN_READ, STATE_DRAIN_WRITE, STATE_DRAIN_COMMIT);
    signal styp_state : t_state := STATE_IDLE;
    signal su18_address : unsigned(17 downto 0) := (others => '0');
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal s_incomplete, s_report_abort : std_logic := '0';
    signal s_abort, s_operating : std_logic;
    signal su4_error : unsigned(3 downto 0) := (others => '0');
begin
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    o_incomplete <= s_incomplete;
    o_machine_hold_request <= o_active or s_incomplete;
    ou4_error <= su4_error;
    s_operating <= '0' when styp_state = STATE_IDLE or styp_state = STATE_FAIL or
        styp_state = STATE_DRAIN_READ or styp_state = STATE_DRAIN_WRITE or
        styp_state = STATE_DRAIN_COMMIT else '1';
    s_abort <= '1' when i_initialize = '1' or (s_operating = '1' and
        (i_cancel = '1' or i_image_valid /= '1' or i_machine_held /= '1')) else '0';
    o_image_read <= '1' when styp_state = STATE_READ and s_abort = '0' else '0';
    ou18_image_address <= su18_address + 64;
    o_body_request <= '1' when styp_state = STATE_WRITE and s_abort = '0' else '0';
    ou18_body_address <= su18_address;
    ou8_body_data <= su8_data;
    o_body_commit <= '1' when styp_state = STATE_COMMIT and s_abort = '0' else '0';
    apply_image : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_success <= '0';
            assert (i_image_response /= '1' or styp_state = STATE_READ_WAIT or
                styp_state = STATE_DRAIN_READ) report "Unowned apply image reply" severity failure;
            assert (i_body_response /= '1' or styp_state = STATE_WRITE_WAIT or
                styp_state = STATE_DRAIN_WRITE) report "Unowned apply body reply" severity failure;
            assert (i_body_committed /= '1' or styp_state = STATE_COMMIT_WAIT or
                styp_state = STATE_DRAIN_COMMIT) report "Unowned apply commit reply" severity failure;
            -- Reset completion is an explicit parent acknowledgement, never a
            -- mere one-clock reset request while accepted writes remain owed.
            if (i_game_reset_completed = '1' and styp_state = STATE_IDLE) then
                s_incomplete <= '0';
            end if;
            if (s_abort = '1') then
                if (i_initialize = '1') then
                    su4_error <= (others => '0');
                    s_report_abort <= '0';
                else
                    s_report_abort <= '1';
                    if (i_cancel = '1') then
                        su4_error <= to_unsigned(1, 4);
                    elsif (i_image_valid /= '1') then
                        su4_error <= to_unsigned(2, 4);
                    else
                        su4_error <= to_unsigned(3, 4);
                    end if;
                end if;
                if ((styp_state = STATE_READ_WAIT or styp_state = STATE_DRAIN_READ) and
                    i_image_response /= '1') then
                    styp_state <= STATE_DRAIN_READ;
                elsif ((styp_state = STATE_WRITE_WAIT or styp_state = STATE_DRAIN_WRITE) and
                    i_body_response /= '1') then
                    styp_state <= STATE_DRAIN_WRITE;
                elsif ((styp_state = STATE_COMMIT_WAIT or styp_state = STATE_DRAIN_COMMIT) and
                    i_body_committed /= '1') then
                    styp_state <= STATE_DRAIN_COMMIT;
                elsif (i_initialize = '1') then
                    styp_state <= STATE_IDLE;
                else
                    styp_state <= STATE_FAIL;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_start = '1') then
                            su4_error <= (others => '0');
                            s_report_abort <= '0';
                            if (i_image_valid /= '1' or i_machine_held /= '1') then
                                o_finished <= '1';
                                if (i_image_valid /= '1') then
                                    su4_error <= to_unsigned(2, 4);
                                else
                                    su4_error <= to_unsigned(3, 4);
                                end if;
                            else
                                su18_address <= (others => '0');
                                styp_state <= STATE_READ;
                            end if;
                        end if;
                    when STATE_READ =>
                        styp_state <= STATE_READ_WAIT;
                    when STATE_READ_WAIT =>
                        if (i_image_response = '1') then
                            if (i_image_error = '1') then
                                su4_error <= to_unsigned(4, 4);
                                styp_state <= STATE_FAIL;
                            else
                                su8_data <= iu8_image_data;
                                styp_state <= STATE_WRITE;
                            end if;
                        end if;
                    when STATE_WRITE =>
                        if (i_body_ready = '1') then
                            s_incomplete <= '1';
                            styp_state <= STATE_WRITE_WAIT;
                        end if;
                    when STATE_WRITE_WAIT =>
                        if (i_body_response = '1') then
                            if (i_body_error = '1') then
                                su4_error <= to_unsigned(5, 4);
                                styp_state <= STATE_FAIL;
                            elsif (su18_address = CINT_BODY_BYTES - 1) then
                                styp_state <= STATE_COMMIT;
                            else
                                su18_address <= su18_address + 1;
                                styp_state <= STATE_READ;
                            end if;
                        end if;
                    when STATE_COMMIT =>
                        styp_state <= STATE_COMMIT_WAIT;
                    when STATE_COMMIT_WAIT =>
                        if (i_body_committed = '1') then
                            o_finished <= '1';
                            if (i_body_commit_error = '1') then
                                su4_error <= to_unsigned(6, 4);
                            else
                                s_incomplete <= '0';
                                o_success <= '1';
                            end if;
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_FAIL =>
                        o_finished <= '1';
                        styp_state <= STATE_IDLE;
                    when STATE_DRAIN_READ | STATE_DRAIN_WRITE | STATE_DRAIN_COMMIT =>
                        if ((styp_state = STATE_DRAIN_READ and i_image_response = '1') or
                            (styp_state = STATE_DRAIN_WRITE and i_body_response = '1') or
                            (styp_state = STATE_DRAIN_COMMIT and i_body_committed = '1')) then
                            if (s_report_abort = '1') then
                                styp_state <= STATE_FAIL;
                            else
                                styp_state <= STATE_IDLE;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
