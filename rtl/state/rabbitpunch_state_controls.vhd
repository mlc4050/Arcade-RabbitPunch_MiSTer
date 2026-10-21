-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Host controls only. Service completion means final DDR publication for SAVE;
-- private CPU return is deliberately not a completion input here.
entity rabbitpunch_state_controls is
    generic (
        GBOOL_ENABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        iu128_status : in unsigned(127 downto 0);
        iu32_joystick0 : in unsigned(31 downto 0) := (others => '0');
        iu32_joystick1 : in unsigned(31 downto 0) := (others => '0');
        i_service_ready : in std_logic;
        i_service_busy : in std_logic;
        i_service_finished : in std_logic;
        i_service_success : in std_logic;
        i_service_incomplete : in std_logic := '0';
        o_save : out std_logic := '0';
        o_restore : out std_logic := '0';
        ou2_slot : out unsigned(1 downto 0);
        o_unavailable : out std_logic;
        o_save_unavailable : out std_logic;
        o_status_set : out std_logic := '0';
        ou128_status_data : out unsigned(127 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_state_controls is
    signal s_previous_save, s_previous_restore : std_logic := '0';
    signal s_request_save, s_request_restore : std_logic;
    signal s_pending, s_saving, s_increment : std_logic := '0';
    signal s_feedback_pending : std_logic := '0';
    signal su2_slot : unsigned(1 downto 0) := (others => '0');
    signal su2_feedback_source : unsigned(1 downto 0) := (others => '0');
begin
    -- MRA action 12 is joystick bit15; direction bits2/3 are Down/Up.
    -- Each chord belongs to one controller, avoiding cross-player commands.
    s_request_save <= iu128_status(8) or
        (iu32_joystick0(15) and iu32_joystick0(2)) or
        (iu32_joystick1(15) and iu32_joystick1(2));
    s_request_restore <= iu128_status(9) or
        (iu32_joystick0(15) and iu32_joystick0(3)) or
        (iu32_joystick1(15) and iu32_joystick1(3));
    ou2_slot <= su2_slot when s_pending = '1' else iu128_status(6 downto 5);
    o_unavailable <= '1' when not GBOOL_ENABLE else
        s_pending or s_feedback_pending or i_service_busy or not i_service_ready;
    o_save_unavailable <= o_unavailable or i_service_incomplete;

    process(i_clk)
        variable vu128_status : unsigned(127 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_save <= '0';
            o_restore <= '0';
            o_status_set <= '0';
            s_previous_save <= s_request_save;
            s_previous_restore <= s_request_restore;
            if (i_initialize = '1') then
                s_pending <= '0';
                s_saving <= '0';
                s_increment <= '0';
                s_feedback_pending <= '0';
            elsif (GBOOL_ENABLE) then
                -- hps_io publishes a status request; the host writes the new
                -- status back later. Do not admit another action on the old
                -- slot in that interval. A different manual slot also resolves
                -- the ticket without overwriting that host selection.
                if (s_feedback_pending = '1' and iu128_status(6 downto 5) /= su2_feedback_source) then
                    s_feedback_pending <= '0';
                end if;
                if (s_pending = '1') then
                    if (i_service_finished = '1') then
                        s_pending <= '0';
                        -- Preserve a slot changed during the transfer. Also
                        -- honor disabling autoincrement before completion.
                        if (s_saving = '1' and i_service_success = '1' and
                            s_increment = '1' and iu128_status(7) = '1' and
                            iu128_status(6 downto 5) = su2_slot) then
                            vu128_status := iu128_status;
                            vu128_status(6 downto 5) := su2_slot + 1;
                            ou128_status_data <= vu128_status;
                            o_status_set <= '1';
                            s_feedback_pending <= '1';
                            su2_feedback_source <= su2_slot;
                        end if;
                    end if;
                elsif (i_service_ready = '1' and i_service_busy = '0' and s_feedback_pending = '0') then
                    -- Partial application advertises ready for RESTORE only.
                    -- Never create a SAVE ticket that the service must ignore.
                    if (s_request_save = '1' and s_previous_save = '0' and i_service_incomplete = '0') then
                        o_save <= '1';
                        s_pending <= '1';
                        s_saving <= '1';
                        s_increment <= iu128_status(7);
                        su2_slot <= iu128_status(6 downto 5);
                    elsif (s_request_restore = '1' and s_previous_restore = '0') then
                        o_restore <= '1';
                        s_pending <= '1';
                        s_saving <= '0';
                        s_increment <= '0';
                        su2_slot <= iu128_status(6 downto 5);
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
