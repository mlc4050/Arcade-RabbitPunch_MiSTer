-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Exclusive sessions on the acknowledged maintenance byte port. External
-- state/debug access has priority when idle; an active session cannot be stolen.
-- Ended sessions retain ownership until their accepted byte response drains.
entity rabbitpunch_maintenance_clients is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_score_initialize : in std_logic;
        i_external_access : in std_logic;
        i_external_valid : in std_logic;
        i_external_write : in std_logic;
        iu14_external_address : in unsigned(13 downto 0);
        iu8_external_data : in unsigned(7 downto 0);
        o_external_ready : out std_logic;
        o_external_response : out std_logic;
        ou8_external_data : out unsigned(7 downto 0);
        i_score_access : in std_logic;
        i_score_valid : in std_logic;
        i_score_write : in std_logic;
        iu14_score_address : in unsigned(13 downto 0);
        iu8_score_data : in unsigned(7 downto 0);
        o_score_ready : out std_logic;
        o_score_response : out std_logic;
        ou8_score_data : out unsigned(7 downto 0);
        o_memory_initialize : out std_logic;
        o_memory_access : out std_logic;
        o_memory_valid : out std_logic;
        o_memory_write : out std_logic;
        ou14_memory_address : out unsigned(13 downto 0);
        ou8_memory_data : out unsigned(7 downto 0);
        i_memory_ready : in std_logic;
        i_memory_response : in std_logic;
        iu8_memory_data : in unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_maintenance_clients is
    type t_state is (STATE_IDLE, STATE_EXTERNAL, STATE_SCORE);
    signal styp_state : t_state := STATE_IDLE;
    signal s_external, s_score, s_pending, s_valid, s_cancel : std_logic := '0';
begin
    s_external <= '1' when styp_state = STATE_EXTERNAL or
        (styp_state = STATE_IDLE and i_external_access = '1') else '0';
    s_score <= '1' when styp_state = STATE_SCORE or
        (styp_state = STATE_IDLE and i_external_access = '0' and i_score_access = '1') else '0';
    s_cancel <= i_initialize or (s_score and i_score_initialize);
    o_memory_initialize <= s_cancel;
    o_memory_access <= (s_external and i_external_access) or (s_score and i_score_access) or s_pending;
    s_valid <= '1' when s_pending = '0' and s_cancel = '0' and
        ((s_external = '1' and i_external_access = '1' and i_external_valid = '1') or
         (s_score = '1' and i_score_access = '1' and i_score_valid = '1')) else '0';
    o_memory_valid <= s_valid;
    o_memory_write <= i_external_write when s_external = '1' else i_score_write;
    ou14_memory_address <= iu14_external_address when s_external = '1' else iu14_score_address;
    ou8_memory_data <= iu8_external_data when s_external = '1' else iu8_score_data;
    o_external_ready <= s_external and i_memory_ready and not s_pending and not s_cancel;
    o_score_ready <= s_score and i_memory_ready and not s_pending and not s_cancel;
    o_external_response <= s_external and s_pending and i_memory_response and not s_cancel;
    o_score_response <= s_score and s_pending and i_memory_response and not s_cancel;
    ou8_external_data <= iu8_memory_data;
    ou8_score_data <= iu8_memory_data;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (s_cancel = '1') then
                s_pending <= '0';
                styp_state <= STATE_IDLE;
            else
                if (s_valid = '1' and i_memory_ready = '1') then
                    s_pending <= '1';
                elsif (i_memory_response = '1' and s_pending = '1') then
                    s_pending <= '0';
                end if;
                case styp_state is
                    when STATE_IDLE =>
                        if (s_external = '1') then
                            styp_state <= STATE_EXTERNAL;
                        elsif (s_score = '1') then
                            styp_state <= STATE_SCORE;
                        end if;
                    when STATE_EXTERNAL =>
                        if (i_external_access = '0' and s_pending = '0') then
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_SCORE =>
                        if (i_score_access = '0' and s_pending = '0') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
