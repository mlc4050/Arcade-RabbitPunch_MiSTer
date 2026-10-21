-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- Present the immutable validated byte RAM as the slot writer's little-endian
-- 64-bit stream. Accepted reads retain ownership through cancel/reset; a held
-- output word remains stable for any DDR backpressure interval.
entity rabbitpunch_state_image_words is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_cancel : in std_logic;
        i_image_valid : in std_logic;
        o_image_read : out std_logic;
        ou18_image_address : out unsigned(17 downto 0);
        i_image_response : in std_logic;
        i_image_error : in std_logic;
        iu8_image_data : in unsigned(7 downto 0);
        o_word_valid : out std_logic;
        i_word_ready : in std_logic;
        ou64_word_data : out unsigned(63 downto 0);
        o_active : out std_logic;
        o_finished : out std_logic;
        o_success : out std_logic;
        ou3_error : out unsigned(2 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_image_words is
    type t_state is (STATE_IDLE, STATE_READ, STATE_WAIT, STATE_WORD, STATE_FAIL, STATE_DRAIN);
    signal styp_state : t_state := STATE_IDLE;
    signal su18_address : unsigned(17 downto 0) := (others => '0');
    signal su64_data : unsigned(63 downto 0) := (others => '0');
    signal su3_error : unsigned(2 downto 0) := (others => '0');
    signal s_abort, s_report_abort : std_logic := '0';
begin
    o_active <= '0' when styp_state = STATE_IDLE else '1';
    s_abort <= '1' when i_initialize = '1' or ((styp_state = STATE_READ or
        styp_state = STATE_WAIT or styp_state = STATE_WORD) and
        (i_cancel = '1' or i_image_valid /= '1')) else '0';
    o_image_read <= '1' when styp_state = STATE_READ and s_abort = '0' else '0';
    ou18_image_address <= su18_address;
    o_word_valid <= '1' when styp_state = STATE_WORD and s_abort = '0' else '0';
    ou64_word_data <= su64_data;
    ou3_error <= su3_error;
    stream_words : process(i_clk)
        variable vint_lane : natural range 0 to 7;
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_success <= '0';
            assert (i_image_response /= '1' or styp_state = STATE_WAIT or styp_state = STATE_DRAIN)
                report "Image word stream received unowned reply" severity failure;
            if (s_abort = '1') then
                if (i_initialize = '1') then
                    su3_error <= (others => '0');
                    s_report_abort <= '0';
                else
                    s_report_abort <= '1';
                    if (i_cancel = '1') then
                        su3_error <= to_unsigned(2, 3);
                    else
                        su3_error <= to_unsigned(1, 3);
                    end if;
                end if;
                if ((styp_state = STATE_WAIT or styp_state = STATE_DRAIN) and i_image_response /= '1') then
                    styp_state <= STATE_DRAIN;
                elsif (i_initialize = '1') then
                    styp_state <= STATE_IDLE;
                else
                    styp_state <= STATE_FAIL;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_start = '1') then
                            su3_error <= (others => '0');
                            s_report_abort <= '0';
                            if (i_image_valid /= '1') then
                                su3_error <= to_unsigned(1, 3);
                                o_finished <= '1';
                            else
                                su18_address <= (others => '0');
                                su64_data <= (others => '0');
                                styp_state <= STATE_READ;
                            end if;
                        end if;
                    when STATE_READ =>
                        styp_state <= STATE_WAIT;
                    when STATE_WAIT =>
                        if (i_image_response = '1') then
                            if (i_image_error = '1') then
                                su3_error <= to_unsigned(3, 3);
                                styp_state <= STATE_FAIL;
                            else
                                vint_lane := to_integer(su18_address(2 downto 0));
                                su64_data(8*vint_lane + 7 downto 8*vint_lane) <= iu8_image_data;
                                if (vint_lane = 7) then
                                    styp_state <= STATE_WORD;
                                else
                                    su18_address <= su18_address + 1;
                                    styp_state <= STATE_READ;
                                end if;
                            end if;
                        end if;
                    when STATE_WORD =>
                        if (i_word_ready = '1') then
                            if (su18_address = CINT_IMAGE_BYTES - 1) then
                                o_finished <= '1';
                                o_success <= '1';
                                styp_state <= STATE_IDLE;
                            else
                                su18_address <= su18_address + 1;
                                styp_state <= STATE_READ;
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
