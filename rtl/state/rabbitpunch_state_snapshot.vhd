-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_crc.all;

-- Construct an immutable private image from a held machine. Read its body once
-- for CRC, build the header, then read again into sequential staging. Matching
-- CRCs detect an unstable capture surface. The parent retains the actual CPU
-- holds until its private return/release protocol completes. Accepted body-read
-- debt survives cancellation; no partially constructed image is sealed.
entity rabbitpunch_state_snapshot is
    generic (
        GINT_BODY_BYTES : positive
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        i_rom_identity_valid : in std_logic;
        iu32_abi_signature : in unsigned(31 downto 0);
        iu32_rom_identity : in unsigned(31 downto 0);
        iu32_config_identity : in unsigned(31 downto 0);
        iu192_section_bytes : in unsigned(191 downto 0);
        o_machine_hold_request : out std_logic;
        i_machine_held : in std_logic;
        o_body_request : out std_logic;
        i_body_ready : in std_logic;
        ou18_body_address : out unsigned(17 downto 0);
        i_body_response : in std_logic;
        i_body_error : in std_logic;
        iu8_body_data : in unsigned(7 downto 0);
        o_image_begin : out std_logic;
        o_image_cancel : out std_logic;
        o_image_valid : out std_logic;
        i_image_ready : in std_logic;
        ou8_image_data : out unsigned(7 downto 0);
        o_image_seal : out std_logic;
        o_active : out std_logic;
        o_finished : out std_logic;
        o_success : out std_logic;
        ou4_error : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_snapshot is
    type t_state is (STATE_IDLE, STATE_WAIT_HELD, STATE_CRC_REQUEST, STATE_CRC_WAIT,
        STATE_HEADER_START, STATE_HEADER_WAIT, STATE_HEADER_BYTES, STATE_BODY_REQUEST,
        STATE_BODY_WAIT, STATE_BODY_BYTE, STATE_SEAL, STATE_DRAIN, STATE_FAIL);
    signal styp_state : t_state := STATE_IDLE;
    signal su18_index : unsigned(17 downto 0) := (others => '0');
    signal su6_header_index : unsigned(5 downto 0) := (others => '0');
    signal su32_crc, su32_body_crc : unsigned(31 downto 0) := CU32_CRC_SEED;
    signal su32_abi, su32_rom, su32_config : unsigned(31 downto 0) := (others => '0');
    signal su192_sections : unsigned(191 downto 0) := (others => '0');
    signal su8_body_data : unsigned(7 downto 0) := (others => '0');
    signal su512_header : unsigned(511 downto 0);
    signal su4_error : unsigned(3 downto 0) := (others => '0');
    signal s_header_start, s_header_valid, s_header_error, s_report_abort : std_logic := '0';
    signal s_abort, s_live_changed, s_hold_lost : std_logic;
begin
    assert (GINT_BODY_BYTES mod 8 = 0 and GINT_BODY_BYTES <= 262072)
        report "Invalid snapshot body size" severity failure;
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    o_machine_hold_request <= o_active;
    ou4_error <= su4_error;
    s_live_changed <= '1' when i_rom_identity_valid /= '1' or iu32_rom_identity /= su32_rom or
        iu32_config_identity /= su32_config else '0';
    s_hold_lost <= '1' when styp_state /= STATE_IDLE and styp_state /= STATE_WAIT_HELD and
        styp_state /= STATE_DRAIN and styp_state /= STATE_FAIL and i_machine_held /= '1' else '0';
    s_abort <= '1' when i_initialize = '1' or i_cancel = '1' or
        (styp_state /= STATE_IDLE and styp_state /= STATE_DRAIN and styp_state /= STATE_FAIL and
        (s_live_changed = '1' or s_hold_lost = '1')) else '0';
    o_image_cancel <= '1' when i_initialize = '1' or styp_state = STATE_FAIL or styp_state = STATE_DRAIN else '0';
    o_image_begin <= '1' when styp_state = STATE_IDLE and i_start = '1' and
        i_rom_identity_valid = '1' and s_abort = '0' else '0';
    o_body_request <= '1' when (styp_state = STATE_CRC_REQUEST or styp_state = STATE_BODY_REQUEST) and
        i_body_ready = '1' and s_abort = '0' else '0';
    ou18_body_address <= su18_index;
    o_image_valid <= '1' when (styp_state = STATE_HEADER_BYTES or styp_state = STATE_BODY_BYTE) and
        s_abort = '0' else '0';
    ou8_image_data <= su512_header(8*to_integer(su6_header_index) + 7 downto
        8*to_integer(su6_header_index)) when styp_state = STATE_HEADER_BYTES else su8_body_data;
    o_image_seal <= '1' when styp_state = STATE_SEAL and s_abort = '0' else '0';
    s_header_start <= '1' when styp_state = STATE_HEADER_START and s_abort = '0' else '0';
    header : entity work.rabbitpunch_state_header
        generic map (
            GINT_BODY_BYTES => GINT_BODY_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_header_start,
            i_cancel => s_abort,
            i_rom_identity_valid => '1',
            iu32_abi_signature => su32_abi,
            iu32_rom_identity => su32_rom,
            iu32_config_identity => su32_config,
            iu32_body_crc => su32_body_crc,
            iu192_section_bytes => su192_sections,
            o_busy => open,
            o_valid => s_header_valid,
            o_error => s_header_error,
            ou512_header => su512_header
        );
    construct : process(i_clk)
        variable vu32_crc : unsigned(31 downto 0);
    begin
        if (rising_edge(i_clk)) then
            assert (i_initialize = '1' or i_body_response = '0' or styp_state = STATE_CRC_WAIT or
                styp_state = STATE_BODY_WAIT or styp_state = STATE_DRAIN)
                report "Snapshot received unowned body-read response" severity failure;
            o_finished <= '0';
            o_success <= '0';
            if (s_abort = '1') then
                if (i_initialize = '1') then
                    su4_error <= (others => '0');
                    s_report_abort <= '0';
                else
                    s_report_abort <= '1';
                    if (i_cancel = '1') then
                        su4_error <= to_unsigned(4, 4);
                    elsif (s_live_changed = '1') then
                        su4_error <= to_unsigned(5, 4);
                    else
                        su4_error <= to_unsigned(6, 4);
                    end if;
                end if;
                if ((styp_state = STATE_CRC_WAIT or styp_state = STATE_BODY_WAIT or styp_state = STATE_DRAIN) and
                    i_body_response = '0') then
                    styp_state <= STATE_DRAIN;
                else
                    if (styp_state /= STATE_IDLE and i_initialize = '0') then
                        styp_state <= STATE_FAIL;
                    else
                        styp_state <= STATE_IDLE;
                    end if;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_start = '1') then
                            su4_error <= (others => '0');
                            if (i_rom_identity_valid /= '1') then
                                su4_error <= to_unsigned(1, 4);
                                o_finished <= '1';
                            else
                                su32_abi <= iu32_abi_signature;
                                su32_rom <= iu32_rom_identity;
                                su32_config <= iu32_config_identity;
                                su192_sections <= iu192_section_bytes;
                                su18_index <= (others => '0');
                                su32_crc <= CU32_CRC_SEED;
                                s_report_abort <= '0';
                                styp_state <= STATE_WAIT_HELD;
                            end if;
                        end if;
                    when STATE_WAIT_HELD =>
                        if (i_machine_held = '1') then
                            styp_state <= STATE_CRC_REQUEST;
                        end if;
                    when STATE_CRC_REQUEST =>
                        if (i_body_ready = '1') then
                            styp_state <= STATE_CRC_WAIT;
                        end if;
                    when STATE_CRC_WAIT =>
                        if (i_body_response = '1') then
                            if (i_body_error = '1') then
                                su4_error <= to_unsigned(2, 4);
                                styp_state <= STATE_FAIL;
                            else
                                vu32_crc := F_CRC32_BYTE(su32_crc, iu8_body_data);
                                su32_crc <= vu32_crc;
                                if (su18_index = GINT_BODY_BYTES - 1) then
                                    su32_body_crc <= not vu32_crc;
                                    styp_state <= STATE_HEADER_START;
                                else
                                    su18_index <= su18_index + 1;
                                    styp_state <= STATE_CRC_REQUEST;
                                end if;
                            end if;
                        end if;
                    when STATE_HEADER_START =>
                        styp_state <= STATE_HEADER_WAIT;
                    when STATE_HEADER_WAIT =>
                        if (s_header_error = '1') then
                            su4_error <= to_unsigned(7, 4);
                            styp_state <= STATE_FAIL;
                        elsif (s_header_valid = '1') then
                            su6_header_index <= (others => '0');
                            su18_index <= (others => '0');
                            su32_crc <= CU32_CRC_SEED;
                            styp_state <= STATE_HEADER_BYTES;
                        end if;
                    when STATE_HEADER_BYTES =>
                        if (i_image_ready = '1') then
                            if (su6_header_index = 63) then
                                styp_state <= STATE_BODY_REQUEST;
                            else
                                su6_header_index <= su6_header_index + 1;
                            end if;
                        end if;
                    when STATE_BODY_REQUEST =>
                        if (i_body_ready = '1') then
                            styp_state <= STATE_BODY_WAIT;
                        end if;
                    when STATE_BODY_WAIT =>
                        if (i_body_response = '1') then
                            if (i_body_error = '1') then
                                su4_error <= to_unsigned(2, 4);
                                styp_state <= STATE_FAIL;
                            else
                                su8_body_data <= iu8_body_data;
                                su32_crc <= F_CRC32_BYTE(su32_crc, iu8_body_data);
                                styp_state <= STATE_BODY_BYTE;
                            end if;
                        end if;
                    when STATE_BODY_BYTE =>
                        if (i_image_ready = '1') then
                            if (su18_index = GINT_BODY_BYTES - 1) then
                                if ((not su32_crc) = su32_body_crc) then
                                    styp_state <= STATE_SEAL;
                                else
                                    su4_error <= to_unsigned(3, 4);
                                    styp_state <= STATE_FAIL;
                                end if;
                            else
                                su18_index <= su18_index + 1;
                                styp_state <= STATE_BODY_REQUEST;
                            end if;
                        end if;
                    when STATE_SEAL =>
                        o_finished <= '1';
                        o_success <= '1';
                        styp_state <= STATE_IDLE;
                    when STATE_FAIL =>
                        o_finished <= '1';
                        styp_state <= STATE_IDLE;
                    when STATE_DRAIN =>
                        if (i_body_response = '1') then
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
