-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- Publish a complete validated private image. Both byte-RAM and DDR read
-- ownership must retire before completion, even if one side fails first.
-- Success is the final DDR control-word acceptance, not host/SD acknowledgement.
entity rabbitpunch_state_publish is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        i_image_valid : in std_logic;
        iu2_slot : in unsigned(1 downto 0);
        o_image_read : out std_logic;
        ou18_image_address : out unsigned(17 downto 0);
        i_image_response : in std_logic;
        i_image_error : in std_logic;
        iu8_image_data : in unsigned(7 downto 0);
        o_ddr_read : out std_logic;
        o_ddr_write : out std_logic;
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_write_data : out unsigned(63 downto 0);
        i_ddr_busy : in std_logic;
        i_ddr_read_valid : in std_logic;
        iu64_ddr_read_data : in unsigned(63 downto 0);
        o_active : out std_logic;
        o_finished : out std_logic;
        o_success : out std_logic;
        ou3_error : out unsigned(2 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_publish is
    type t_state is (STATE_IDLE, STATE_START, STATE_RUNNING, STATE_RESULT, STATE_DRAIN);
    signal styp_state : t_state := STATE_IDLE;
    signal su2_slot : unsigned(1 downto 0) := (others => '0');
    signal su3_error, su3_stream_error : unsigned(2 downto 0) := (others => '0');
    signal s_start, s_cancel, s_word_valid, s_word_ready, s_stream_active, s_writer_active : std_logic;
    signal s_stream_success, s_writer_success, s_writer_error : std_logic;
    signal s_stream_done, s_writer_done : std_logic := '0';
    signal su64_data : unsigned(63 downto 0);
begin
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    ou3_error <= su3_error;
    s_start <= '1' when styp_state = STATE_START and i_initialize = '0' and
        i_cancel = '0' and i_image_valid = '1' else '0';
    s_cancel <= '1' when i_initialize = '1' or i_cancel = '1' or i_image_valid /= '1' or
        (styp_state = STATE_RUNNING and (su3_stream_error /= 0 or s_writer_error = '1')) else '0';
    image_words : entity work.rabbitpunch_state_image_words
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            i_image_valid => i_image_valid,
            o_image_read => o_image_read,
            ou18_image_address => ou18_image_address,
            i_image_response => i_image_response,
            i_image_error => i_image_error,
            iu8_image_data => iu8_image_data,
            o_word_valid => s_word_valid,
            i_word_ready => s_word_ready,
            ou64_word_data => su64_data,
            o_active => s_stream_active,
            o_finished => open,
            o_success => s_stream_success,
            ou3_error => su3_stream_error
        );
    slot_writer : entity work.rabbitpunch_state_slot_writer
        generic map (
            GINT_PAYLOAD_BYTES => CINT_IMAGE_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_start,
            i_cancel => s_cancel,
            iu2_slot => su2_slot,
            i_payload_valid => s_word_valid,
            o_payload_ready => s_word_ready,
            iu64_payload_data => su64_data,
            o_active => s_writer_active,
            o_finished => open,
            o_success => s_writer_success,
            o_error => s_writer_error,
            o_ddr_read => o_ddr_read,
            o_ddr_write => o_ddr_write,
            ou29_ddr_word_address => ou29_ddr_word_address,
            ou64_ddr_write_data => ou64_ddr_write_data,
            i_ddr_busy => i_ddr_busy,
            i_ddr_read_valid => i_ddr_read_valid,
            iu64_ddr_read_data => iu64_ddr_read_data
        );
    publish_image : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_success <= '0';
            if (i_initialize = '1') then
                su3_error <= (others => '0');
                s_stream_done <= '0';
                s_writer_done <= '0';
                styp_state <= STATE_DRAIN;
            else
                if (s_stream_success = '1') then
                    s_stream_done <= '1';
                end if;
                if (s_writer_success = '1') then
                    s_writer_done <= '1';
                end if;
                if ((styp_state = STATE_START or styp_state = STATE_RUNNING or styp_state = STATE_RESULT) and
                    su3_error = 0) then
                    if (i_cancel = '1') then
                        su3_error <= to_unsigned(2, 3);
                    elsif (i_image_valid /= '1') then
                        su3_error <= to_unsigned(1, 3);
                    elsif (styp_state = STATE_RUNNING and su3_stream_error /= 0) then
                        su3_error <= to_unsigned(3, 3);
                    elsif (styp_state = STATE_RUNNING and s_writer_error = '1') then
                        su3_error <= to_unsigned(4, 3);
                    end if;
                end if;
                case styp_state is
                    when STATE_IDLE =>
                        if (i_start = '1') then
                            s_stream_done <= '0';
                            s_writer_done <= '0';
                            su3_error <= (others => '0');
                            if (i_image_valid /= '1' or i_cancel = '1') then
                                o_finished <= '1';
                                if (i_cancel = '1') then
                                    su3_error <= to_unsigned(2, 3);
                                else
                                    su3_error <= to_unsigned(1, 3);
                                end if;
                            else
                                su2_slot <= iu2_slot;
                                styp_state <= STATE_START;
                            end if;
                        end if;
                    when STATE_START =>
                        styp_state <= STATE_RUNNING;
                    when STATE_RUNNING =>
                        if (s_stream_active = '0' and s_writer_active = '0') then
                            styp_state <= STATE_RESULT;
                        end if;
                    when STATE_RESULT =>
                        o_finished <= '1';
                        if (su3_error = 0 and i_cancel = '0' and i_image_valid = '1' and
                            s_stream_done = '1' and s_writer_done = '1') then
                            o_success <= '1';
                        end if;
                        styp_state <= STATE_IDLE;
                    when STATE_DRAIN =>
                        if (s_stream_active = '0' and s_writer_active = '0') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
