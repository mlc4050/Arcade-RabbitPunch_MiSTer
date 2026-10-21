-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Evaluation candidate: canonicalize the unchanged controller through ordinary
-- read-only traffic after all game clients drain. No controller reset or
-- hierarchical state access is used. The caller supplies a common raster edge.
entity rabbitpunch_state_sdram_phase is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_prepare : in std_logic;
        i_anchor : in std_logic;
        i_refresh : in std_logic;
        o_aligned : out std_logic;
        o_idle : out std_logic;
        i_client_request : in std_logic;
        i_client_write : in std_logic;
        iu27_client_address : in unsigned(26 downto 0);
        iu16_client_data : in unsigned(15 downto 0);
        iu2_client_bytes : in unsigned(1 downto 0);
        o_client_ready : out std_logic;
        o_client_valid : out std_logic;
        ou64_client_data : out unsigned(63 downto 0);
        o_backend_request : out std_logic;
        o_backend_write : out std_logic;
        ou27_backend_address : out unsigned(26 downto 0);
        ou16_backend_data : out unsigned(15 downto 0);
        ou2_backend_bytes : out unsigned(1 downto 0);
        i_backend_ready : in std_logic;
        i_backend_valid : in std_logic;
        iu64_backend_data : in unsigned(63 downto 0);
        i_phase_known : in std_logic := '0';
        iu7_phase : in unsigned(6 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_state_sdram_phase is
    signal s_active, s_pending, s_hide_reply : std_logic := '0';
    signal s_seen_refresh, s_previous_refresh, s_locked : std_logic := '0';
    signal s_owned, s_read, s_idle : std_logic;
    signal su7_phase : unsigned(6 downto 0) := (others => '0');
    signal sint_refresh_age : natural range 0 to 1023 := 0;
    signal sint_intervals : natural range 0 to 4 := 0;
begin
    s_owned <= i_prepare or s_pending or s_hide_reply;
    s_read <= '1' when i_prepare = '1' and s_active = '1' and
        su7_phase = 64 and s_pending = '0' and s_hide_reply = '0' and
        i_backend_ready = '1' else '0';
    o_backend_request <= s_read when s_owned = '1' else i_client_request;
    o_backend_write <= '0' when s_owned = '1' else i_client_write;
    ou27_backend_address <= (others => '0') when s_owned = '1' else iu27_client_address;
    ou16_backend_data <= (others => '0') when s_owned = '1' else iu16_client_data;
    ou2_backend_bytes <= "00" when s_owned = '1' else iu2_client_bytes;
    o_client_ready <= i_backend_ready and not s_owned;
    -- An old normal response still belongs to its normal client. Only reads
    -- actually accepted from this shim acquire the private response ticket.
    o_client_valid <= i_backend_valid and not s_pending and not s_hide_reply;
    ou64_client_data <= iu64_backend_data;
    s_idle <= not s_pending and not s_hide_reply and not s_read;
    o_idle <= s_idle;
    o_aligned <= '1' when i_prepare = '1' and i_anchor = '1' and
        s_active = '1' and s_locked = '1' and su7_phase = 0 and
        s_pending = '0' and s_hide_reply = '0' and i_backend_ready = '1' else '0';
    normalize : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_initialize = '1') then
                s_active <= '0';
                s_pending <= '0';
                s_hide_reply <= '0';
                s_seen_refresh <= '0';
                s_previous_refresh <= '0';
                s_locked <= '0';
                su7_phase <= (others => '0');
                sint_refresh_age <= 0;
                sint_intervals <= 0;
            else
                s_previous_refresh <= i_refresh;
                if (s_hide_reply = '1' and i_backend_valid = '0') then
                    s_hide_reply <= '0';
                end if;
                if (s_pending = '1' and i_backend_valid = '1') then
                    s_pending <= '0';
                    s_hide_reply <= '1';
                end if;
                if (s_read = '1') then
                    s_pending <= '1';
                end if;
                if (i_prepare = '0') then
                    -- Cancellation withdraws offers, never accepted read debt.
                    s_active <= '0';
                    s_seen_refresh <= '0';
                    s_locked <= '0';
                    su7_phase <= (others => '0');
                    sint_refresh_age <= 0;
                    sint_intervals <= 0;
                elsif (s_active = '0') then
                    if ((i_phase_known = '1' or i_anchor = '1') and s_idle = '1' and i_backend_ready = '1') then
                        s_active <= '1';
                        if (i_phase_known = '1') then
                            su7_phase <= iu7_phase + 1;
                        else
                            su7_phase <= to_unsigned(1, 7);
                        end if;
                    end if;
                else
                    assert (i_phase_known = '0' or su7_phase = iu7_phase)
                        report "SDRAM normalization lost the physical/guest phase offset" severity failure;
                    su7_phase <= su7_phase + 1;
                    if (sint_refresh_age < 1023) then
                        sint_refresh_age <= sint_refresh_age + 1;
                    end if;
                    if (i_refresh = '1' and s_previous_refresh = '0') then
                        s_seen_refresh <= '1';
                        sint_refresh_age <= 0;
                        if (s_seen_refresh = '1' and sint_refresh_age = 127) then
                            if (sint_intervals < 4) then
                                sint_intervals <= sint_intervals + 1;
                            end if;
                            if (sint_intervals >= 3) then
                                s_locked <= '1';
                            end if;
                        else
                            sint_intervals <= 0;
                            s_locked <= '0';
                        end if;
                    end if;
                    if (su7_phase = 64 and s_read = '0') then
                        s_locked <= '0';
                        sint_intervals <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
