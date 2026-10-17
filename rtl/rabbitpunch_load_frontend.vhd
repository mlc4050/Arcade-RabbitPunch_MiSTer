-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- HPS index 0 supplies either byte pulses or an image already staged in DDR.
-- A DDR copy starts after framework reset release, once per ROM transaction.
-- Other indices do not arm loading. The caller keeps gameplay reset on o_error
-- and uses the downstream image-valid/drained status before running the board.
entity rabbitpunch_load_frontend is
    generic (
        GINT_IMAGE_BYTES : positive := CINT_ROM_IMAGE_SIZE
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_framework_reset : in std_logic;
        -- Retry only after the downstream loader has drained a prior image.
        i_start_ready : in std_logic := '1';
        i_host_download : in std_logic;
        iu16_host_index : in unsigned(15 downto 0);
        i_host_write : in std_logic;
        iu27_host_byte_address : in unsigned(26 downto 0);
        iu8_host_data : in unsigned(7 downto 0);
        o_host_wait : out std_logic;
        o_download_active : out std_logic;
        o_done : out std_logic;
        o_error : out std_logic;
        o_ddr_mode : out std_logic;
        o_word_valid : out std_logic;
        i_word_ready : in std_logic;
        ou27_word_byte_address : out unsigned(26 downto 0);
        ou16_word_data : out unsigned(15 downto 0);
        i_ddr_busy : in std_logic;
        ou8_ddr_burst_count : out unsigned(7 downto 0);
        ou29_ddr_word_address : out unsigned(28 downto 0);
        iu64_ddr_read_data : in unsigned(63 downto 0);
        i_ddr_read_valid : in std_logic;
        o_ddr_read : out std_logic;
        ou64_ddr_write_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0);
        o_ddr_write : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_load_frontend is
    type t_state is (STATE_IDLE, STATE_HOST, STATE_WAIT_RELEASE, STATE_DDR_START,
        STATE_DDR_COPY, STATE_BYTE_DRAIN, STATE_ERROR_DRAIN);
    signal styp_state : t_state := STATE_IDLE;
    signal s_host_rom, s_previous_host : std_logic := '0';
    signal s_seen_write, s_word_pending, s_error, s_ddr_mode : std_logic := '0';
    signal s_copy_start, s_copy_active, s_copy_done, s_copy_valid, s_copy_selected : std_logic;
    signal su27_next_byte, su27_word_address : unsigned(26 downto 0) := (others => '0');
    signal su8_low_byte : unsigned(7 downto 0);
    signal su16_word_data : unsigned(15 downto 0);
    signal su27_copy_address : unsigned(26 downto 0);
    signal su16_copy_data : unsigned(15 downto 0);
begin
    s_host_rom <= '1' when i_host_download = '1' and iu16_host_index = 0 else '0';
    o_download_active <= '1' when (s_host_rom = '1' and i_start_ready = '1') or styp_state /= STATE_IDLE else '0';
    s_copy_start <= '1' when styp_state = STATE_DDR_START else '0';
    s_copy_selected <= '1' when styp_state = STATE_DDR_START or styp_state = STATE_DDR_COPY else '0';
    o_error <= s_error;
    o_ddr_mode <= s_ddr_mode;
    -- Include the current write pulse so hps_io cannot queue another byte
    -- before our captured-word backpressure becomes visible.
    o_host_wait <= '1' when iu16_host_index = 0 and (styp_state = STATE_ERROR_DRAIN or (styp_state = STATE_IDLE and i_start_ready = '0')) else
        s_word_pending or i_host_write or s_copy_selected when iu16_host_index = 0 else '0';
    o_word_valid <= s_copy_valid when s_copy_selected = '1' else s_word_pending;
    ou27_word_byte_address <= su27_copy_address when s_copy_selected = '1' else su27_word_address;
    ou16_word_data <= su16_copy_data when s_copy_selected = '1' else su16_word_data;
    ddr_copy : entity work.rabbitpunch_ddr_copy
        generic map (GINT_IMAGE_BYTES => GINT_IMAGE_BYTES)
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_copy_start,
            o_active => s_copy_active,
            o_done => s_copy_done,
            o_word_valid => s_copy_valid,
            i_word_ready => i_word_ready and s_copy_selected,
            ou27_word_byte_address => su27_copy_address,
            ou16_word_data => su16_copy_data,
            i_ddr_busy => i_ddr_busy,
            ou8_ddr_burst_count => ou8_ddr_burst_count,
            ou29_ddr_word_address => ou29_ddr_word_address,
            iu64_ddr_read_data => iu64_ddr_read_data,
            i_ddr_read_valid => i_ddr_read_valid,
            o_ddr_read => o_ddr_read,
            ou64_ddr_write_data => ou64_ddr_write_data,
            ou8_ddr_byte_enables => ou8_ddr_byte_enables,
            o_ddr_write => o_ddr_write
        );
    process(i_clk)
        variable v_start : boolean;
        variable vu27_count : unsigned(26 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_done <= '0';
            if (i_initialize = '1') then
                styp_state <= STATE_IDLE;
                s_previous_host <= '0';
                s_seen_write <= '0';
                s_word_pending <= '0';
                s_error <= '0';
                s_ddr_mode <= '0';
                su27_next_byte <= (others => '0');
            else
                s_previous_host <= s_host_rom;
                v_start := styp_state = STATE_IDLE and s_host_rom = '1' and i_start_ready = '1';
                vu27_count := su27_next_byte;
                if (s_word_pending = '1' and i_word_ready = '1') then
                    s_word_pending <= '0';
                end if;
                case styp_state is
                    when STATE_IDLE =>
                        if (v_start) then
                            s_seen_write <= '0';
                            s_error <= '0';
                            s_ddr_mode <= '0';
                            vu27_count := (others => '0');
                            su27_next_byte <= (others => '0');
                            styp_state <= STATE_HOST;
                        end if;
                    when STATE_HOST =>
                        if (s_host_rom = '0') then
                            if (s_seen_write = '0') then
                                s_ddr_mode <= '1';
                                styp_state <= STATE_WAIT_RELEASE;
                            elsif (su27_next_byte = GINT_IMAGE_BYTES and su27_next_byte(0) = '0') then
                                styp_state <= STATE_BYTE_DRAIN;
                            else
                                s_error <= '1';
                                styp_state <= STATE_ERROR_DRAIN;
                            end if;
                        end if;
                    when STATE_WAIT_RELEASE =>
                        if (s_error = '1') then
                            styp_state <= STATE_ERROR_DRAIN;
                        elsif (i_framework_reset = '0' and s_host_rom = '0') then
                            styp_state <= STATE_DDR_START;
                        end if;
                    when STATE_DDR_START =>
                        styp_state <= STATE_DDR_COPY;
                    when STATE_DDR_COPY =>
                        if (s_copy_done = '1') then
                            if (s_error = '1' or s_host_rom = '1') then
                                styp_state <= STATE_ERROR_DRAIN;
                            else
                                styp_state <= STATE_IDLE;
                                o_done <= '1';
                            end if;
                        end if;
                    when STATE_BYTE_DRAIN =>
                        if (s_word_pending = '0') then
                            styp_state <= STATE_IDLE;
                            o_done <= '1';
                        end if;
                    when STATE_ERROR_DRAIN =>
                        if (s_host_rom = '0' and s_word_pending = '0' and s_copy_active = '0') then
                            styp_state <= STATE_IDLE;
                            o_done <= '1';
                        end if;
                end case;
                -- The first byte is allowed on the same edge as download rises.
                if ((styp_state = STATE_HOST or v_start) and s_host_rom = '1' and i_host_write = '1') then
                    s_seen_write <= '1';
                    if (s_word_pending = '1' or iu27_host_byte_address /= vu27_count or vu27_count >= GINT_IMAGE_BYTES) then
                        s_error <= '1';
                        styp_state <= STATE_ERROR_DRAIN;
                    else
                        if (vu27_count(0) = '0') then
                            su8_low_byte <= iu8_host_data;
                        else
                            su27_word_address <= vu27_count - 1;
                            su16_word_data <= iu8_host_data & su8_low_byte;
                            s_word_pending <= '1';
                        end if;
                        su27_next_byte <= vu27_count + 1;
                    end if;
                end if;
                -- Only one host ROM transaction may own a copy at a time.
                -- Drain the old copy on overlap and leave the caller in error
                -- reset until a fresh transaction recovers.
                if (s_host_rom = '1' and s_previous_host = '0' and not v_start and styp_state /= STATE_IDLE) then
                    s_error <= '1';
                    if (styp_state = STATE_WAIT_RELEASE or styp_state = STATE_BYTE_DRAIN) then
                        styp_state <= STATE_ERROR_DRAIN;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
