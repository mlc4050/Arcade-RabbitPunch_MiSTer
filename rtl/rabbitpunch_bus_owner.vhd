-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One queued pulse per client, one physical transaction. A late already-issued
-- CPU request wins ahead of maintenance, even when both arrive together.
-- No gameplay reset: all accepted requests and replies retain their owner.
entity rabbitpunch_bus_owner is
    port (
        i_clk : in std_logic;
        i_cpu_request : in std_logic;
        i_cpu_write : in std_logic;
        iu24_cpu_address : in unsigned(23 downto 0);
        iu16_cpu_data : in unsigned(15 downto 0);
        iu2_cpu_bytes : in unsigned(1 downto 0);
        o_cpu_idle : out std_logic;
        o_idle : out std_logic;
        o_cpu_response_valid : out std_logic;
        ou16_cpu_response_data : out unsigned(15 downto 0);
        i_maintenance_allowed : in std_logic;
        i_maintenance_request : in std_logic;
        i_maintenance_write : in std_logic;
        iu24_maintenance_address : in unsigned(23 downto 0);
        iu16_maintenance_data : in unsigned(15 downto 0);
        iu2_maintenance_bytes : in unsigned(1 downto 0);
        o_maintenance_response_valid : out std_logic;
        ou16_maintenance_response_data : out unsigned(15 downto 0);
        o_backend_request : out std_logic;
        o_backend_write : out std_logic;
        ou24_backend_address : out unsigned(23 downto 0);
        ou16_backend_data : out unsigned(15 downto 0);
        ou2_backend_bytes : out unsigned(1 downto 0);
        i_backend_response_valid : in std_logic;
        iu16_backend_response_data : in unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_bus_owner is
    type t_state is (STATE_IDLE, STATE_WAITING);
    type t_addresses is array (0 to 1) of unsigned(23 downto 0);
    type t_data is array (0 to 1) of unsigned(15 downto 0);
    type t_bytes is array (0 to 1) of unsigned(1 downto 0);
    signal styp_state : t_state := STATE_IDLE;
    signal su2_pending, su2_write : unsigned(1 downto 0) := "00";
    signal su24_address : t_addresses;
    signal su16_data : t_data;
    signal su2_bytes : t_bytes;
    signal s_owner : std_logic := '0';
begin
    o_idle <= '1' when styp_state = STATE_IDLE and su2_pending = "00" and
        i_cpu_request = '0' and i_maintenance_request = '0' else '0';
    o_cpu_idle <= '1' when su2_pending(0) = '0' and i_cpu_request = '0' and
        not (styp_state = STATE_WAITING and s_owner = '0') else '0';
    o_cpu_response_valid <= i_backend_response_valid when styp_state = STATE_WAITING and s_owner = '0' else '0';
    o_maintenance_response_valid <= i_backend_response_valid when styp_state = STATE_WAITING and s_owner = '1' else '0';
    ou16_cpu_response_data <= iu16_backend_response_data;
    ou16_maintenance_response_data <= iu16_backend_response_data;
    process(i_clk)
        variable vint_owner : integer range -1 to 1;
    begin
        if (rising_edge(i_clk)) then
            o_backend_request <= '0';
            assert (i_backend_response_valid /= '1' or styp_state = STATE_WAITING)
                report "Shared bus received an unowned reply" severity failure;
            if (i_cpu_request = '1') then
                assert (su2_pending(0) = '0' and not (styp_state = STATE_WAITING and s_owner = '0'))
                    report "CPU exceeded one outstanding shared-bus credit" severity failure;
                su2_pending(0) <= '1';
                su2_write(0) <= i_cpu_write;
                su24_address(0) <= iu24_cpu_address;
                su16_data(0) <= iu16_cpu_data;
                su2_bytes(0) <= iu2_cpu_bytes;
            end if;
            if (i_maintenance_request = '1') then
                assert (su2_pending(1) = '0' and not (styp_state = STATE_WAITING and s_owner = '1'))
                    report "Maintenance exceeded one outstanding shared-bus credit" severity failure;
                su2_pending(1) <= '1';
                su2_write(1) <= i_maintenance_write;
                su24_address(1) <= iu24_maintenance_address;
                su16_data(1) <= iu16_maintenance_data;
                su2_bytes(1) <= iu2_maintenance_bytes;
            end if;
            case styp_state is
                when STATE_IDLE =>
                    vint_owner := -1;
                    if (su2_pending(0) = '1') then
                        vint_owner := 0;
                    elsif (i_cpu_request = '0' and su2_pending(1) = '1' and i_maintenance_allowed = '1') then
                        vint_owner := 1;
                    end if;
                    if (vint_owner >= 0) then
                        o_backend_request <= '1';
                        o_backend_write <= su2_write(vint_owner);
                        ou24_backend_address <= su24_address(vint_owner);
                        ou16_backend_data <= su16_data(vint_owner);
                        ou2_backend_bytes <= su2_bytes(vint_owner);
                        su2_pending(vint_owner) <= '0';
                        if (vint_owner = 0) then
                            s_owner <= '0';
                        else
                            s_owner <= '1';
                        end if;
                        styp_state <= STATE_WAITING;
                    end if;
                when STATE_WAITING =>
                    if (i_backend_response_valid = '1') then
                        styp_state <= STATE_IDLE;
                    end if;
            end case;
        end if;
    end process;
end architecture;
