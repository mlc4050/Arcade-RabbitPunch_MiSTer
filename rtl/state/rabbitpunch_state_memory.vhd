-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Dense byte image of all five main RAM banks followed by sound RAM. The
-- parent owns both bus muxes and must drain CPU, renderer and ROM debt first.
-- Initialization cancels the session, never an accepted backend transaction.
entity rabbitpunch_state_memory is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_session : in std_logic;
        i_drained : in std_logic;
        o_pause : out std_logic;
        o_idle : out std_logic;
        i_byte_valid : in std_logic;
        o_byte_ready : out std_logic;
        i_byte_write : in std_logic;
        iu17_byte_address : in unsigned(16 downto 0);
        iu8_byte_data : in unsigned(7 downto 0);
        o_byte_response : out std_logic := '0';
        o_byte_error : out std_logic := '0';
        ou8_byte_data : out unsigned(7 downto 0);
        o_main_request : out std_logic := '0';
        o_main_write : out std_logic;
        ou24_main_address : out unsigned(23 downto 0);
        ou16_main_data : out unsigned(15 downto 0);
        ou2_main_bytes : out unsigned(1 downto 0);
        i_main_response : in std_logic;
        iu16_main_data : in unsigned(15 downto 0);
        o_sound_request : out std_logic := '0';
        o_sound_write : out std_logic;
        ou16_sound_address : out unsigned(15 downto 0);
        ou8_sound_data : out unsigned(7 downto 0);
        i_sound_response : in std_logic;
        iu8_sound_data : in unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_memory is
    type t_state is (STATE_IDLE, STATE_MAIN, STATE_SOUND, STATE_DRAIN_MAIN, STATE_DRAIN_SOUND);
    signal styp_state : t_state := STATE_IDLE;
    signal s_ready, s_lower_byte : std_logic := '0';
begin
    o_idle <= '1' when styp_state = STATE_IDLE else '0';
    o_pause <= '1' when i_session = '1' or styp_state /= STATE_IDLE else '0';
    s_ready <= '1' when i_session = '1' and i_drained = '1' and i_initialize = '0' and
        styp_state = STATE_IDLE else '0';
    o_byte_ready <= s_ready;
    transfer : process(i_clk)
        variable vu24_address : unsigned(23 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_main_request <= '0';
            o_sound_request <= '0';
            o_byte_response <= '0';
            o_byte_error <= '0';
            assert (i_main_response /= '1' or styp_state = STATE_MAIN or styp_state = STATE_DRAIN_MAIN)
                report "Unowned main state-memory response" severity failure;
            assert (i_sound_response /= '1' or styp_state = STATE_SOUND or styp_state = STATE_DRAIN_SOUND)
                report "Unowned sound state-memory response" severity failure;
            if (i_initialize = '1' or i_session = '0') then
                case styp_state is
                    when STATE_MAIN | STATE_DRAIN_MAIN =>
                        if (i_main_response = '1') then
                            styp_state <= STATE_IDLE;
                        else
                            styp_state <= STATE_DRAIN_MAIN;
                        end if;
                    when STATE_SOUND | STATE_DRAIN_SOUND =>
                        if (i_sound_response = '1') then
                            styp_state <= STATE_IDLE;
                        else
                            styp_state <= STATE_DRAIN_SOUND;
                        end if;
                    when STATE_IDLE => null;
                end case;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_byte_valid = '1' and s_ready = '1') then
                            s_lower_byte <= iu17_byte_address(0);
                            if (iu17_byte_address >= 106496) then
                                o_byte_response <= '1';
                                o_byte_error <= '1';
                                ou8_byte_data <= (others => '0');
                            elsif (iu17_byte_address >= 104448) then
                                ou16_sound_address <= x"F800" + resize(iu17_byte_address - 104448, 16);
                                ou8_sound_data <= iu8_byte_data;
                                o_sound_write <= i_byte_write;
                                o_sound_request <= '1';
                                styp_state <= STATE_SOUND;
                            else
                                if (iu17_byte_address < 65536) then
                                    vu24_address := to_unsigned(16#040000#, 24) + resize(iu17_byte_address, 24);
                                elsif (iu17_byte_address < 69632) then
                                    vu24_address := to_unsigned(16#060000#, 24) + resize(iu17_byte_address - 65536, 24);
                                elsif (iu17_byte_address < 86016) then
                                    vu24_address := to_unsigned(16#080000#, 24) + resize(iu17_byte_address - 69632, 24);
                                elsif (iu17_byte_address < 88064) then
                                    vu24_address := to_unsigned(16#0A0000#, 24) + resize(iu17_byte_address - 86016, 24);
                                else
                                    vu24_address := to_unsigned(16#0FC000#, 24) + resize(iu17_byte_address - 88064, 24);
                                end if;
                                vu24_address(0) := '0';
                                ou24_main_address <= vu24_address;
                                ou16_main_data <= iu8_byte_data & iu8_byte_data;
                                if (iu17_byte_address(0) = '0') then
                                    ou2_main_bytes <= "10";
                                else
                                    ou2_main_bytes <= "01";
                                end if;
                                o_main_write <= i_byte_write;
                                o_main_request <= '1';
                                styp_state <= STATE_MAIN;
                            end if;
                        end if;
                    when STATE_MAIN =>
                        if (i_main_response = '1') then
                            if (s_lower_byte = '1') then
                                ou8_byte_data <= iu16_main_data(7 downto 0);
                            else
                                ou8_byte_data <= iu16_main_data(15 downto 8);
                            end if;
                            o_byte_response <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_SOUND =>
                        if (i_sound_response = '1') then
                            ou8_byte_data <= iu8_sound_data;
                            o_byte_response <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAIN_MAIN =>
                        if (i_main_response = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAIN_SOUND =>
                        if (i_sound_response = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
