-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- Own the sealed private RAM read port for one complete validation pass. Both
-- framing/identity/CRC and body legality must succeed before application.
-- No interface can write game state. The parent retains this image's lease
-- until application completes; replacing staging invalidates this result.
entity rabbitpunch_state_image_validator is
    generic (
        GINT_HORIZONTAL_TOTAL : positive := 432;
        GINT_VERTICAL_TOTAL : positive := 256
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        i_image_sealed : in std_logic;
        i_rom_identity_valid : in std_logic;
        iu32_abi_signature : in unsigned(31 downto 0);
        iu32_rom_identity : in unsigned(31 downto 0);
        iu32_config_identity : in unsigned(31 downto 0);
        o_image_read : out std_logic;
        ou18_image_address : out unsigned(17 downto 0);
        i_image_response : in std_logic;
        i_image_error : in std_logic;
        iu8_image_data : in unsigned(7 downto 0);
        o_active : out std_logic;
        o_finished : out std_logic;
        o_valid : out std_logic;
        ou6_error : out unsigned(5 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_image_validator is
    type t_state is (STATE_IDLE, STATE_START, STATE_REQUEST, STATE_WAIT, STATE_RESULT, STATE_DRAIN, STATE_FAIL);
    signal styp_state : t_state := STATE_IDLE;
    signal su18_index : unsigned(17 downto 0) := (others => '0');
    signal su32_rom, su32_config : unsigned(31 downto 0) := (others => '0');
    signal s_valid, s_report_abort : std_logic := '0';
    signal su6_error : unsigned(5 downto 0) := (others => '0');
    signal s_abort, s_validate_start, s_validate_abort, s_byte_valid, s_body_byte_valid, s_last_byte : std_logic;
    signal s_frame_valid, s_frame_finished, s_frame_ready, s_body_valid, s_body_finished, s_body_ready : std_logic;
    signal su4_frame_error, su4_body_error : unsigned(3 downto 0);
begin
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    o_valid <= s_valid and i_image_sealed and i_rom_identity_valid when
        iu32_rom_identity = su32_rom and iu32_config_identity = su32_config else '0';
    ou6_error <= su6_error;
    s_abort <= '1' when i_initialize = '1' or i_cancel = '1' or
        (styp_state /= STATE_IDLE and styp_state /= STATE_DRAIN and styp_state /= STATE_FAIL and
        i_image_sealed /= '1') else '0';
    s_validate_start <= '1' when styp_state = STATE_START and s_abort = '0' else '0';
    s_validate_abort <= '1' when s_abort = '1' or styp_state = STATE_FAIL or styp_state = STATE_DRAIN else '0';
    o_image_read <= '1' when styp_state = STATE_REQUEST and s_abort = '0' else '0';
    ou18_image_address <= su18_index;
    s_byte_valid <= '1' when styp_state = STATE_WAIT and i_image_response = '1' and
        i_image_error = '0' and s_abort = '0' else '0';
    s_last_byte <= '1' when s_byte_valid = '1' and su18_index = CINT_IMAGE_BYTES - 1 else '0';
    s_body_byte_valid <= s_byte_valid when su18_index >= 64 else '0';
    framing : entity work.rabbitpunch_state_preflight
        generic map (
            GINT_BODY_BYTES => CINT_BODY_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_validate_start,
            iu32_payload_words => to_unsigned(CINT_IMAGE_BYTES/4, 32),
            iu32_abi_signature => iu32_abi_signature,
            i_rom_identity_valid => i_rom_identity_valid,
            iu32_rom_identity => iu32_rom_identity,
            iu32_config_identity => iu32_config_identity,
            iu192_section_bytes => CU192_SECTION_BYTES,
            i_byte_valid => s_byte_valid,
            o_byte_ready => s_frame_ready,
            iu8_byte_data => iu8_image_data,
            i_finish => s_last_byte,
            i_abort => s_validate_abort,
            o_active => open,
            o_finished => s_frame_finished,
            o_valid => s_frame_valid,
            ou4_error => su4_frame_error
        );
    fields : entity work.rabbitpunch_state_semantics
        generic map (
            GINT_HORIZONTAL_TOTAL => GINT_HORIZONTAL_TOTAL,
            GINT_VERTICAL_TOTAL => GINT_VERTICAL_TOTAL
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_validate_start,
            i_abort => s_validate_abort,
            i_byte_valid => s_body_byte_valid,
            o_byte_ready => s_body_ready,
            iu8_byte_data => iu8_image_data,
            i_finish => s_last_byte,
            o_active => open,
            o_finished => s_body_finished,
            o_valid => s_body_valid,
            ou4_error => su4_body_error
        );
    validate_image : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            assert (i_initialize = '1' or i_image_response = '0' or styp_state = STATE_WAIT or styp_state = STATE_DRAIN)
                report "Image validator received unowned RAM response" severity failure;
            if (i_image_sealed = '0') then
                s_valid <= '0';
            end if;
            if (s_abort = '1') then
                s_valid <= '0';
                if (i_initialize = '1') then
                    su6_error <= (others => '0');
                    s_report_abort <= '0';
                else
                    s_report_abort <= '1';
                    if (i_cancel = '1') then
                        su6_error <= to_unsigned(50, 6);
                    else
                        su6_error <= to_unsigned(48, 6);
                    end if;
                end if;
                if ((styp_state = STATE_WAIT or styp_state = STATE_DRAIN) and i_image_response = '0') then
                    styp_state <= STATE_DRAIN;
                elsif (i_initialize = '1' or styp_state = STATE_IDLE) then
                    styp_state <= STATE_IDLE;
                else
                    styp_state <= STATE_FAIL;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_start = '1') then
                            s_valid <= '0';
                            su6_error <= (others => '0');
                            if (i_image_sealed /= '1') then
                                su6_error <= to_unsigned(48, 6);
                                o_finished <= '1';
                            else
                                su32_rom <= iu32_rom_identity;
                                su32_config <= iu32_config_identity;
                                su18_index <= (others => '0');
                                s_report_abort <= '0';
                                styp_state <= STATE_START;
                            end if;
                        end if;
                    when STATE_START =>
                        styp_state <= STATE_REQUEST;
                    when STATE_REQUEST =>
                        assert (s_frame_ready = '1' and s_body_ready = '1')
                            report "Image validation consumers are not ready" severity failure;
                        styp_state <= STATE_WAIT;
                    when STATE_WAIT =>
                        if (i_image_response = '1') then
                            if (i_image_error = '1') then
                                su6_error <= to_unsigned(49, 6);
                                styp_state <= STATE_FAIL;
                            elsif (su18_index = CINT_IMAGE_BYTES - 1) then
                                styp_state <= STATE_RESULT;
                            else
                                su18_index <= su18_index + 1;
                                styp_state <= STATE_REQUEST;
                            end if;
                        end if;
                    when STATE_RESULT =>
                        if (s_frame_finished = '1' and s_body_finished = '1') then
                            o_finished <= '1';
                            styp_state <= STATE_IDLE;
                            if (s_frame_valid = '0') then
                                su6_error <= to_unsigned(16, 6) + resize(su4_frame_error, 6);
                            elsif (s_body_valid = '0') then
                                su6_error <= to_unsigned(32, 6) + resize(su4_body_error, 6);
                            else
                                s_valid <= '1';
                            end if;
                        end if;
                    when STATE_FAIL =>
                        o_finished <= '1';
                        styp_state <= STATE_IDLE;
                    when STATE_DRAIN =>
                        if (i_image_response = '1') then
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
