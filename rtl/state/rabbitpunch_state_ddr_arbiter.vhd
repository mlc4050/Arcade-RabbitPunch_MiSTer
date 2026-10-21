-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Single clock DDR command/response boundary. Loader ownership is exclusive;
-- otherwise queued rotation writes have priority over single-beat snapshots.
-- Accepted read debt outlives cancellation and initialization. Each reader must
-- consume/discard its own late responses; BUSY does not describe response debt.
-- Commands are strobed only when DDR is ready, so no stalled command is exposed.
entity rabbitpunch_state_ddr_arbiter is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_loader_active : in std_logic;
        i_loader_read : in std_logic;
        i_loader_write : in std_logic;
        iu8_loader_burst_count : in unsigned(7 downto 0);
        iu29_loader_word_address : in unsigned(28 downto 0);
        iu64_loader_write_data : in unsigned(63 downto 0);
        iu8_loader_byte_enables : in unsigned(7 downto 0);
        o_loader_busy : out std_logic;
        o_loader_read_valid : out std_logic;
        ou64_loader_read_data : out unsigned(63 downto 0);
        i_rotation_write : in std_logic;
        iu29_rotation_word_address : in unsigned(28 downto 0);
        iu64_rotation_data : in unsigned(63 downto 0);
        iu8_rotation_byte_enables : in unsigned(7 downto 0);
        o_rotation_busy : out std_logic;
        i_state_active : in std_logic;
        i_state_read : in std_logic;
        i_state_write : in std_logic;
        iu29_state_word_address : in unsigned(28 downto 0);
        iu64_state_write_data : in unsigned(63 downto 0);
        iu8_state_byte_enables : in unsigned(7 downto 0);
        o_state_busy : out std_logic;
        o_state_read_valid : out std_logic;
        ou64_state_read_data : out unsigned(63 downto 0);
        o_read_idle : out std_logic;
        i_ddr_busy : in std_logic;
        i_ddr_read_valid : in std_logic;
        iu64_ddr_read_data : in unsigned(63 downto 0);
        ou8_ddr_burst_count : out unsigned(7 downto 0);
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_write_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0);
        o_ddr_read : out std_logic;
        o_ddr_write : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_state_ddr_arbiter is
    type t_owner is (STATE_NONE, STATE_LOADER, STATE_SNAPSHOT);
    signal styp_owner : t_owner := STATE_NONE;
    signal su8_read_beats : unsigned(7 downto 0) := (others => '0');
    signal s_loader_block : std_logic;
begin
    s_loader_block <= '1' when i_loader_active = '1' or
        (styp_owner = STATE_LOADER and su8_read_beats /= 0) else '0';
    o_read_idle <= '1' when su8_read_beats = 0 else '0';
    o_loader_read_valid <= i_ddr_read_valid when styp_owner = STATE_LOADER and
        su8_read_beats /= 0 else '0';
    o_state_read_valid <= i_ddr_read_valid when styp_owner = STATE_SNAPSHOT and
        su8_read_beats /= 0 else '0';
    ou64_loader_read_data <= iu64_ddr_read_data;
    ou64_state_read_data <= iu64_ddr_read_data;
    -- Rotation ready must not depend on its write strobe: the queue already
    -- qualifies that strobe with this ready signal.
    o_rotation_busy <= i_ddr_busy or s_loader_block or i_initialize;
    choose : process(all)
    begin
        o_loader_busy <= '1';
        o_state_busy <= '1';
        ou8_ddr_burst_count <= to_unsigned(1, 8);
        ou29_ddr_word_address <= (others => '0');
        ou64_ddr_write_data <= (others => '0');
        ou8_ddr_byte_enables <= (others => '0');
        o_ddr_read <= '0';
        o_ddr_write <= '0';
        if (i_initialize = '0') then
            if (i_loader_active = '1' and su8_read_beats = 0) then
                o_loader_busy <= i_ddr_busy;
                ou8_ddr_burst_count <= iu8_loader_burst_count;
                ou29_ddr_word_address <= iu29_loader_word_address;
                ou64_ddr_write_data <= iu64_loader_write_data;
                ou8_ddr_byte_enables <= iu8_loader_byte_enables;
                o_ddr_read <= i_loader_read and not i_ddr_busy;
                o_ddr_write <= i_loader_write and not i_ddr_busy;
            elsif (s_loader_block = '0') then
                if (i_rotation_write = '1') then
                    ou29_ddr_word_address <= iu29_rotation_word_address;
                    ou64_ddr_write_data <= iu64_rotation_data;
                    ou8_ddr_byte_enables <= iu8_rotation_byte_enables;
                    o_ddr_write <= not i_ddr_busy;
                elsif (i_state_active = '1' and su8_read_beats = 0) then
                    o_state_busy <= i_ddr_busy;
                    ou29_ddr_word_address <= iu29_state_word_address;
                    ou64_ddr_write_data <= iu64_state_write_data;
                    ou8_ddr_byte_enables <= iu8_state_byte_enables;
                    o_ddr_read <= i_state_read and not i_ddr_busy;
                    o_ddr_write <= i_state_write and not i_ddr_busy;
                end if;
            end if;
        end if;
    end process;
    debt : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            assert (not (o_ddr_read = '1' and o_ddr_write = '1'))
                report "DDR client requested read and write together" severity failure;
            assert (o_ddr_write = '0' or ou8_ddr_burst_count = 1)
                report "DDR arbiter supports single-beat writes only" severity failure;
            if (i_ddr_read_valid = '1') then
                assert (su8_read_beats /= 0 and styp_owner /= STATE_NONE)
                    report "Unowned DDR read response" severity failure;
                su8_read_beats <= su8_read_beats - 1;
                if (su8_read_beats = 1) then
                    styp_owner <= STATE_NONE;
                end if;
            end if;
            if (o_ddr_read = '1') then
                assert (su8_read_beats = 0 and ou8_ddr_burst_count /= 0)
                    report "Invalid overlapping DDR read command" severity failure;
                su8_read_beats <= ou8_ddr_burst_count;
                if (i_loader_active = '1') then
                    styp_owner <= STATE_LOADER;
                else
                    styp_owner <= STATE_SNAPSHOT;
                end if;
            end if;
        end if;
    end process;
end architecture;
