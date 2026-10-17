-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Byte access to the 16 KiB work RAM through its existing CPU bus port.
-- The enclosing owner mux must assert i_bus_idle only after main-CPU debt
-- drains, route only our replies here, and honor o_pause until it drops.
-- Gameplay reset/session removal never cancels an issued memory access.
entity rabbitpunch_maintenance is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_access_requested : in std_logic;
        o_pause : out std_logic;
        i_cpu_paused : in std_logic;
        i_bus_idle : in std_logic;
        i_byte_valid : in std_logic;
        o_byte_ready : out std_logic;
        i_byte_write : in std_logic;
        iu14_byte_address : in unsigned(13 downto 0);
        iu8_byte_data : in unsigned(7 downto 0);
        o_byte_response_valid : out std_logic;
        ou8_byte_response_data : out unsigned(7 downto 0);
        o_idle : out std_logic;
        o_bus_request : out std_logic;
        o_bus_write : out std_logic;
        ou24_bus_address : out unsigned(23 downto 0);
        ou16_bus_data : out unsigned(15 downto 0);
        ou2_bus_bytes : out unsigned(1 downto 0);
        i_bus_response_valid : in std_logic;
        iu16_bus_response_data : in unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_maintenance is
    type t_state is (STATE_IDLE, STATE_WAITING, STATE_DRAINING);
    signal styp_state : t_state := STATE_IDLE;
    signal s_ready, s_lower_byte : std_logic := '0';
begin
    o_pause <= '1' when i_access_requested = '1' or styp_state /= STATE_IDLE else '0';
    o_idle <= '1' when styp_state = STATE_IDLE else '0';
    s_ready <= '1' when i_access_requested = '1' and i_cpu_paused = '1' and i_bus_idle = '1' and
        styp_state = STATE_IDLE and i_initialize = '0' else '0';
    o_byte_ready <= s_ready;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_bus_request <= '0';
            o_byte_response_valid <= '0';
            assert (i_bus_response_valid /= '1' or styp_state /= STATE_IDLE)
                report "Maintenance received an unowned bus response" severity failure;
            if (i_initialize = '1') then
                if (styp_state /= STATE_IDLE and i_bus_response_valid /= '1') then
                    styp_state <= STATE_DRAINING;
                else
                    styp_state <= STATE_IDLE;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_byte_valid = '1' and s_ready = '1') then
                            s_lower_byte <= iu14_byte_address(0);
                            o_bus_request <= '1';
                            o_bus_write <= i_byte_write;
                            ou24_bus_address <= to_unsigned(16#FC000#, 24) + resize(iu14_byte_address(13 downto 1) & '0', 24);
                            ou16_bus_data <= iu8_byte_data & iu8_byte_data;
                            if (iu14_byte_address(0) = '1') then
                                ou2_bus_bytes <= "01";
                            else
                                ou2_bus_bytes <= "10";
                            end if;
                            styp_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_bus_response_valid = '1') then
                            if (s_lower_byte = '1') then
                                ou8_byte_response_data <= iu16_bus_response_data(7 downto 0);
                            else
                                ou8_byte_response_data <= iu16_bus_response_data(15 downto 8);
                            end if;
                            o_byte_response_valid <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAINING =>
                        if (i_bus_response_valid = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
