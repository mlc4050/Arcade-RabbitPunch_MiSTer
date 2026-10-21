-- SPDX-License-Identifier: GPL-3.0-or-later
-- Based on JT7759 control logic by Jose Tejada Gomez.
-- Production standalone control; default legacy mode is retained for verification.
-- Legacy mode retains the imported controller's observable behavior;
-- MAME mode changes only the silence counter. Actual game ROMs have no repeats.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rabbitpunch_upd7759_control is
    generic (
        GBOOL_MAME_SILENCE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_control_enable : in std_logic;
        i_decode_enable : in std_logic;
        i_start_n : in std_logic;
        i_chip_select : in std_logic;
        i_standalone_mode : in std_logic;
        i_data_request_n : in std_logic;
        i_write_n : in std_logic;
        iu8_command : in unsigned(7 downto 0);
        ou6_divider : out unsigned(5 downto 0);
        o_busy_n : out std_logic;
        o_decoder_reset : out std_logic;
        ou4_decoder_nibble : out unsigned(3 downto 0);
        o_rom_request : out std_logic;
        ou17_rom_address : out unsigned(16 downto 0);
        iu8_rom_data : in unsigned(7 downto 0);
        i_rom_valid : in std_logic;
        o_fifo_flush : out std_logic;
        ou17_debug_silence_remaining : out unsigned(16 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_upd7759_control is
    type t_state is (STATE_RESET, STATE_IDLE, STATE_SOUND_COUNT, STATE_PLAY,
        STATE_WAIT, STATE_GET_COUNT, STATE_MUTED, STATE_LOAD_ADDRESS,
        STATE_READ_COMMAND, STATE_READ_ADDRESS, STATE_SIGNATURE);
    signal styp_state : t_state := STATE_RESET;
    constant CU32_SIGNATURE : unsigned(31 downto 0) := x"5569A55A";
    signal su8_max_sample : unsigned(7 downto 0);
    signal su4_next_nibble, su4_repeat_count : unsigned(3 downto 0);
    signal su17_silence_count, su17_rom_address, su17_repeat_address : unsigned(16 downto 0);
    signal su9_data_count : unsigned(8 downto 0);
    signal su16_address_latch : unsigned(15 downto 0);
    signal s_previous_write, s_header_seen, s_signature_valid : std_logic;
    signal s_unsupported_repeat : std_logic := '0';
    signal s_pre_request, s_request_gap, s_write, s_write_edge : std_logic;
begin
    s_write <= i_chip_select and (not i_standalone_mode or not i_start_n);
    s_write_edge <= not s_previous_write and s_write;
    assert (s_unsupported_repeat = '0')
        report "Rabbit Punch MAME timing mode does not support repeat packets" severity failure;
    o_busy_n <= '1' when styp_state = STATE_IDLE or styp_state = STATE_RESET else '0';
    o_rom_request <= s_pre_request and not s_request_gap;
    ou17_rom_address <= su17_rom_address;
    ou17_debug_silence_remaining <= su17_silence_count;
    control : process(i_clk, i_reset)
        variable vu17_next_address : unsigned(16 downto 0);
        variable vu2_signature_index : unsigned(1 downto 0);
        variable vint_signature_index : natural range 0 to 3;
    begin
        if (i_reset = '1') then
            su8_max_sample <= (others => '0');
            styp_state <= STATE_RESET;
            s_pre_request <= '0';
            su17_rom_address <= (others => '0');
            ou6_divider <= to_unsigned(16, 6);
            s_previous_write <= '0';
            o_decoder_reset <= '1';
            ou4_decoder_nibble <= (others => '0');
            su17_silence_count <= (others => '0');
            su9_data_count <= (others => '0');
            s_signature_valid <= '0';
            su4_repeat_count <= (others => '1');
            su17_repeat_address <= (others => '0');
            s_header_seen <= '0';
            s_unsupported_repeat <= '0';
            su16_address_latch <= (others => '0');
            s_request_gap <= '0';
            o_fifo_flush <= '0';
        elsif (rising_edge(i_clk)) then
            vu17_next_address := su17_rom_address + 1;
            vu2_signature_index := su17_rom_address(1 downto 0) - 1;
            vint_signature_index := to_integer(vu2_signature_index);
            s_previous_write <= s_write;
            o_fifo_flush <= '0';
            if (s_request_gap = '1') then
                s_request_gap <= '0';
            else
                case styp_state is
                    when STATE_RESET | STATE_WAIT =>
                        if (i_control_enable = '1') then
                            if (i_standalone_mode = '1') then
                                su17_rom_address <= (others => '0');
                                s_pre_request <= '0';
                                o_decoder_reset <= '1';
                            end if;
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_SIGNATURE =>
                        if (i_control_enable = '1') then
                            if (i_standalone_mode = '0') then
                                styp_state <= STATE_READ_ADDRESS;
                                su17_rom_address(0) <= not su17_rom_address(0);
                            elsif (i_rom_valid = '1') then
                                if (iu8_rom_data /= CU32_SIGNATURE(8*vint_signature_index + 7 downto 8*vint_signature_index)) then
                                    s_signature_valid <= '0';
                                    styp_state <= STATE_IDLE;
                                else
                                    if (vu2_signature_index = 3) then
                                        s_signature_valid <= '1';
                                        styp_state <= STATE_IDLE;
                                    end if;
                                    su17_rom_address <= vu17_next_address;
                                end if;
                            end if;
                        end if;
                    when STATE_IDLE =>
                        o_fifo_flush <= '1';
                        if (s_write_edge = '1' and i_data_request_n = '1') then
                            s_pre_request <= '1';
                            s_request_gap <= '1';
                            su17_rom_address <= shift_left(resize(iu8_command, 17) + 2, 1) + 1;
                            styp_state <= STATE_READ_ADDRESS;
                        else
                            s_pre_request <= '0';
                            o_decoder_reset <= '1';
                        end if;
                    when STATE_SOUND_COUNT =>
                        if (i_rom_valid = '1') then
                            su8_max_sample <= iu8_rom_data;
                            su17_rom_address <= vu17_next_address;
                            styp_state <= STATE_SIGNATURE;
                        end if;
                    when STATE_READ_ADDRESS =>
                        if (i_control_enable = '1' and i_rom_valid = '1') then
                            if (su17_rom_address(0) = '1') then
                                su17_rom_address <= vu17_next_address;
                                s_request_gap <= '1';
                                su16_address_latch(7 downto 0) <= iu8_rom_data;
                            else
                                su16_address_latch <= su16_address_latch(7 downto 0) & iu8_rom_data;
                                styp_state <= STATE_LOAD_ADDRESS;
                                s_pre_request <= '0';
                            end if;
                        end if;
                    when STATE_LOAD_ADDRESS =>
                        if (i_control_enable = '1') then
                            su17_rom_address <= shift_left(resize(su16_address_latch, 17), 1) + 1;
                            s_header_seen <= '0';
                            styp_state <= STATE_READ_COMMAND;
                            s_pre_request <= '1';
                            s_request_gap <= '1';
                            su4_repeat_count <= (others => '1');
                            if (i_standalone_mode = '1') then
                                o_fifo_flush <= '1';
                            end if;
                        end if;
                    when STATE_READ_COMMAND =>
                        if (i_control_enable = '1' and i_rom_valid = '1') then
                            su17_rom_address <= vu17_next_address;
                            s_pre_request <= '1';
                            s_request_gap <= '1';
                            if (su4_repeat_count /= 15) then
                                su4_repeat_count <= su4_repeat_count - 1;
                            end if;
                            if (iu8_rom_data /= 0) then
                                s_header_seen <= '1';
                            end if;
                            case to_integer(iu8_rom_data(7 downto 6)) is
                                when 0 =>
                                    if (GBOOL_MAME_SILENCE) then
                                        -- MUTED exits on its zero-count enable,
                                        -- hence load one less than the duration.
                                        su17_silence_count <= shift_left(resize(iu8_rom_data(5 downto 0), 17) + 1, 10) - 1;
                                    else
                                        su17_silence_count <= shift_left(resize(iu8_rom_data(5 downto 0), 17), 7);
                                    end if;
                                    if (iu8_rom_data = 0 and s_header_seen = '1') then
                                        styp_state <= STATE_IDLE;
                                        o_decoder_reset <= '1';
                                    else
                                        styp_state <= STATE_MUTED;
                                    end if;
                                    s_pre_request <= '0';
                                when 1 =>
                                    su9_data_count <= to_unsigned(255, 9);
                                    ou6_divider <= iu8_rom_data(5 downto 0);
                                    styp_state <= STATE_PLAY;
                                when 2 =>
                                    su9_data_count(8) <= '0';
                                    ou6_divider <= iu8_rom_data(5 downto 0);
                                    styp_state <= STATE_GET_COUNT;
                                when 3 =>
                                    if (GBOOL_MAME_SILENCE) then
                                        s_unsupported_repeat <= '1';
                                    end if;
                                    su4_repeat_count <= resize(iu8_rom_data(2 downto 0), 4);
                                    su17_repeat_address <= vu17_next_address;
                                when others =>
                                    null;
                            end case;
                        end if;
                    when STATE_GET_COUNT =>
                        if (i_rom_valid = '1') then
                            su17_rom_address <= vu17_next_address;
                            s_pre_request <= '1';
                            s_request_gap <= '1';
                            su9_data_count <= resize(iu8_rom_data, 9);
                            styp_state <= STATE_PLAY;
                        end if;
                    when STATE_MUTED =>
                        if (i_control_enable = '1') then
                            if (i_decode_enable = '1') then
                                o_decoder_reset <= '1';
                            end if;
                            if (su17_silence_count /= 0) then
                                su17_silence_count <= su17_silence_count - 1;
                            else
                                styp_state <= STATE_READ_COMMAND;
                                s_pre_request <= '1';
                                s_request_gap <= '1';
                            end if;
                        end if;
                    when STATE_PLAY =>
                        if (i_decode_enable = '1') then
                            if (s_pre_request = '1') then
                                if (i_rom_valid = '1') then
                                    ou4_decoder_nibble <= iu8_rom_data(7 downto 4);
                                    su4_next_nibble <= iu8_rom_data(3 downto 0);
                                    o_decoder_reset <= '0';
                                    s_pre_request <= '0';
                                    su9_data_count <= su9_data_count - 1;
                                    if (su9_data_count = 0) then
                                        s_pre_request <= '1';
                                        s_request_gap <= '1';
                                        styp_state <= STATE_READ_COMMAND;
                                    end if;
                                end if;
                            else
                                ou4_decoder_nibble <= su4_next_nibble;
                                su17_rom_address <= vu17_next_address;
                                s_pre_request <= '1';
                                s_request_gap <= '1';
                                su9_data_count <= su9_data_count - 1;
                                if (su9_data_count = 0) then
                                    styp_state <= STATE_READ_COMMAND;
                                end if;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
