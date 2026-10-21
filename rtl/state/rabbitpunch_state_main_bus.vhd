-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The dense RAM adapter's state request is already an accepted credit. Never
-- gate it with a later access-mode change, CPU hold or gameplay reset. Latch
-- its response owner and retain CPU reset until that debt/session has retired.
entity rabbitpunch_state_main_bus is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        o_cpu_reset : out std_logic;
        i_cpu_request : in std_logic;
        i_cpu_write : in std_logic;
        iu24_cpu_address : in unsigned(23 downto 0);
        iu16_cpu_data : in unsigned(15 downto 0);
        iu2_cpu_bytes : in unsigned(1 downto 0);
        o_cpu_idle : out std_logic;
        o_idle : out std_logic;
        o_cpu_response : out std_logic;
        ou16_cpu_data : out unsigned(15 downto 0);
        i_maintenance_allowed : in std_logic;
        i_maintenance_request : in std_logic;
        i_maintenance_write : in std_logic;
        iu24_maintenance_address : in unsigned(23 downto 0);
        iu16_maintenance_data : in unsigned(15 downto 0);
        iu2_maintenance_bytes : in unsigned(1 downto 0);
        o_maintenance_response : out std_logic;
        ou16_maintenance_data : out unsigned(15 downto 0);
        o_maintenance_block : out std_logic;
        i_state_access : in std_logic;
        i_state_request : in std_logic;
        i_state_write : in std_logic;
        iu24_state_address : in unsigned(23 downto 0);
        iu16_state_data : in unsigned(15 downto 0);
        iu2_state_bytes : in unsigned(1 downto 0);
        o_state_response : out std_logic;
        ou16_state_data : out unsigned(15 downto 0);
        o_state_busy : out std_logic;
        o_backend_request : out std_logic;
        o_backend_write : out std_logic;
        ou24_backend_address : out unsigned(23 downto 0);
        ou16_backend_data : out unsigned(15 downto 0);
        ou2_backend_bytes : out unsigned(1 downto 0);
        i_backend_response : in std_logic;
        iu16_backend_data : in unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_main_bus is
    signal s_state_owner, s_maintenance_pending, s_reset_drain : std_logic := '0';
    signal s_maintenance_request, s_maintenance_write, s_maintenance_response, s_idle : std_logic;
    signal su24_maintenance_address : unsigned(23 downto 0);
    signal su16_maintenance_write_data, su16_maintenance_read_data : unsigned(15 downto 0);
    signal su2_maintenance_bytes : unsigned(1 downto 0);
begin
    o_cpu_reset <= i_reset or s_reset_drain;
    o_state_busy <= i_state_access or s_state_owner or i_state_request;
    o_maintenance_block <= o_state_busy;
    o_idle <= s_idle and not s_maintenance_pending;
    -- Both request inputs represent credits already accepted upstream. The
    -- block output prevents new admission; it cannot withdraw a queued pulse.
    s_maintenance_request <= i_state_request or i_maintenance_request;
    s_maintenance_write <= i_state_write when i_state_request = '1' else i_maintenance_write;
    su24_maintenance_address <= iu24_state_address when i_state_request = '1' else iu24_maintenance_address;
    su16_maintenance_write_data <= iu16_state_data when i_state_request = '1' else iu16_maintenance_data;
    su2_maintenance_bytes <= iu2_state_bytes when i_state_request = '1' else iu2_maintenance_bytes;
    o_state_response <= s_maintenance_response and s_state_owner;
    o_maintenance_response <= s_maintenance_response and not s_state_owner;
    ou16_state_data <= su16_maintenance_read_data;
    ou16_maintenance_data <= su16_maintenance_read_data;
    ownership : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            assert (not (i_state_request = '1' and i_maintenance_request = '1'))
                report "State and NVRAM RAM sessions were not serialized" severity failure;
            if (s_maintenance_request = '1') then
                assert (s_maintenance_pending = '0')
                    report "Main RAM maintenance client exceeded one credit" severity failure;
                s_maintenance_pending <= '1';
                s_state_owner <= i_state_request;
            elsif (s_maintenance_response = '1') then
                assert (s_maintenance_pending = '1')
                    report "Main RAM maintenance reply has no owner" severity failure;
                s_maintenance_pending <= '0';
                s_state_owner <= '0';
            end if;
            if (i_reset = '1' and (i_state_access = '1' or s_state_owner = '1' or i_state_request = '1')) then
                s_reset_drain <= '1';
            elsif (i_state_access = '0' and s_state_owner = '0' and i_state_request = '0') then
                s_reset_drain <= '0';
            end if;
        end if;
    end process;
    bus_owner : entity work.rabbitpunch_bus_owner
        port map (
            i_clk => i_clk,
            i_cpu_request => i_cpu_request,
            i_cpu_write => i_cpu_write,
            iu24_cpu_address => iu24_cpu_address,
            iu16_cpu_data => iu16_cpu_data,
            iu2_cpu_bytes => iu2_cpu_bytes,
            o_cpu_idle => o_cpu_idle,
            o_idle => s_idle,
            o_cpu_response_valid => o_cpu_response,
            ou16_cpu_response_data => ou16_cpu_data,
            i_maintenance_allowed => i_maintenance_allowed or i_state_request or s_state_owner,
            i_maintenance_request => s_maintenance_request,
            i_maintenance_write => s_maintenance_write,
            iu24_maintenance_address => su24_maintenance_address,
            iu16_maintenance_data => su16_maintenance_write_data,
            iu2_maintenance_bytes => su2_maintenance_bytes,
            o_maintenance_response_valid => s_maintenance_response,
            ou16_maintenance_response_data => su16_maintenance_read_data,
            o_backend_request => o_backend_request,
            o_backend_write => o_backend_write,
            ou24_backend_address => ou24_backend_address,
            ou16_backend_data => ou16_backend_data,
            ou2_backend_bytes => ou2_backend_bytes,
            i_backend_response_valid => i_backend_response,
            iu16_backend_response_data => iu16_backend_data
        );
end architecture;
