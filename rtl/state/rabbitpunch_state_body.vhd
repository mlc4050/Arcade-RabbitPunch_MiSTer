-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- Byte view of held RAM, architectural CPU banks and sound scan words. Apply
-- writes must cover the entire body in order. Wide T80/board values are staged
-- until final commit; RAM and scan-word writes can already have taken effect,
-- so the application controller must retain its incomplete-machine hold.
entity rabbitpunch_state_body is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_session : in std_logic;
        i_machine_held : in std_logic;
        i_apply_begin : in std_logic;
        i_byte_request : in std_logic;
        o_byte_ready : out std_logic;
        i_byte_write : in std_logic;
        iu18_byte_address : in unsigned(17 downto 0);
        iu8_byte_data : in unsigned(7 downto 0);
        o_byte_response : out std_logic;
        o_byte_error : out std_logic;
        ou8_byte_data : out unsigned(7 downto 0);
        i_commit : in std_logic;
        o_committed : out std_logic;
        o_commit_error : out std_logic;
        o_idle : out std_logic;
        o_memory_request : out std_logic;
        i_memory_ready : in std_logic;
        o_memory_write : out std_logic;
        ou17_memory_address : out unsigned(16 downto 0);
        ou8_memory_data : out unsigned(7 downto 0);
        i_memory_response : in std_logic;
        i_memory_error : in std_logic;
        iu8_memory_data : in unsigned(7 downto 0);
        ou5_m68k_address : out unsigned(4 downto 0);
        iu32_m68k_data : in unsigned(31 downto 0);
        o_m68k_write : out std_logic;
        ou32_m68k_data : out unsigned(31 downto 0);
        iu256_t80_data : in unsigned(255 downto 0);
        ou256_t80_data : out unsigned(255 downto 0);
        o_t80_load : out std_logic;
        iu512_board_data : in unsigned(511 downto 0);
        ou512_board_data : out unsigned(511 downto 0);
        o_board_load : out std_logic;
        ou16_chip_address : out unsigned(15 downto 0);
        iu32_fm_data : in unsigned(31 downto 0);
        iu32_adpcm_data : in unsigned(31 downto 0);
        ou32_chip_data : out unsigned(31 downto 0);
        o_fm_write : out std_logic;
        o_adpcm_write : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_state_body is
    type t_state is (STATE_IDLE, STATE_MEMORY, STATE_SCAN_READ,
        STATE_SCAN_WRITE, STATE_COMMIT);
    signal styp_state : t_state := STATE_IDLE;
    signal su18_address, su18_written : unsigned(17 downto 0) := (others => '0');
    signal su32_word : unsigned(31 downto 0) := (others => '0');
    signal su256_t80 : unsigned(255 downto 0) := (others => '0');
    signal su512_board : unsigned(511 downto 0) := (others => '0');
    signal s_apply, s_failed, s_ready, s_legal, s_write_legal, s_enable : std_logic := '0';
    signal s_memory_canceled : std_logic := '0';
    signal sint_word, sint_lane : natural := 0;
begin
    o_idle <= '1' when styp_state = STATE_IDLE else '0';
    s_enable <= i_session and i_machine_held and not i_initialize and not i_apply_begin;
    s_legal <= '1' when iu18_byte_address < CINT_BODY_BYTES else '0';
    s_write_legal <= '1' when s_apply = '1' and s_failed = '0' and
        iu18_byte_address = su18_written else '0';
    -- Illegal requests still get a bounded error reply without touching RAM.
    s_ready <= i_memory_ready when iu18_byte_address < CINT_RAM_BYTES and
        s_legal = '1' and (i_byte_write = '0' or s_write_legal = '1') else '1';
    o_byte_ready <= s_enable and s_ready when styp_state = STATE_IDLE and i_commit = '0' else '0';
    o_memory_request <= i_byte_request and o_byte_ready when iu18_byte_address < CINT_RAM_BYTES and
        (i_byte_write = '0' or s_write_legal = '1') else '0';
    o_memory_write <= i_byte_write;
    ou17_memory_address <= iu18_byte_address(16 downto 0);
    ou8_memory_data <= iu8_byte_data;
    -- All register-bank addresses remain stable from request acceptance until
    -- the corresponding scan read/write edge and reply.
    sint_lane <= to_integer(su18_address(1 downto 0));
    sint_word <= to_integer(shift_right(su18_address - CINT_M68K_BASE, 2)) when
        su18_address >= CINT_M68K_BASE and su18_address < CINT_T80_BASE else 0;
    ou5_m68k_address <= to_unsigned(sint_word, 5);
    ou16_chip_address <= resize(shift_right(su18_address - CINT_FM_BASE, 2), 16) when
        su18_address >= CINT_FM_BASE and su18_address < CINT_ADPCM_BASE else
        resize(shift_right(su18_address - CINT_ADPCM_BASE, 2), 16) when
        su18_address >= CINT_ADPCM_BASE else (others => '0');
    ou32_m68k_data <= su32_word;
    ou32_chip_data <= su32_word;
    ou256_t80_data <= su256_t80;
    ou512_board_data <= su512_board;
    o_m68k_write <= '1' when styp_state = STATE_SCAN_WRITE and s_enable = '1' and
        su18_address >= CINT_M68K_BASE and su18_address < CINT_T80_BASE and sint_word /= 16 and sint_word /= 17 and
        sint_word /= 21 and sint_word /= 23 else '0';
    o_fm_write <= '1' when styp_state = STATE_SCAN_WRITE and s_enable = '1' and
        su18_address >= CINT_FM_BASE and su18_address < CINT_ADPCM_BASE else '0';
    o_adpcm_write <= '1' when styp_state = STATE_SCAN_WRITE and s_enable = '1' and
        su18_address >= CINT_ADPCM_BASE else '0';
    o_t80_load <= '1' when styp_state = STATE_COMMIT and s_enable = '1' else '0';
    o_board_load <= o_t80_load;
    byte_access : process(i_clk)
        variable vint_address, vint_offset : natural;
        variable vu32_word : unsigned(31 downto 0);
        variable vu8_data : unsigned(7 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_byte_response <= '0';
            o_byte_error <= '0';
            o_committed <= '0';
            o_commit_error <= '0';
            assert (i_memory_response /= '1' or styp_state = STATE_MEMORY)
                report "Unowned body RAM response" severity failure;
            if (styp_state = STATE_MEMORY and s_enable /= '1') then
                s_memory_canceled <= '1';
            end if;
            if (i_initialize = '1') then
                s_apply <= '0';
                s_failed <= '1';
                -- An accepted RAM transaction still belongs to this adapter.
                if (styp_state /= STATE_MEMORY or i_memory_response = '1') then
                    styp_state <= STATE_IDLE;
                    if (styp_state = STATE_MEMORY or styp_state = STATE_SCAN_READ or
                        styp_state = STATE_SCAN_WRITE) then
                        o_byte_response <= '1';
                        o_byte_error <= '1';
                    elsif (styp_state = STATE_COMMIT) then
                        o_committed <= '1';
                        o_commit_error <= '1';
                    end if;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_apply_begin = '1' and i_session = '1' and i_machine_held = '1') then
                            s_apply <= '1';
                            s_failed <= '0';
                            su18_written <= (others => '0');
                            su32_word <= (others => '0');
                            su256_t80 <= (others => '0');
                            su512_board <= (others => '0');
                        elsif (i_commit = '1') then
                            if (s_enable = '1' and s_apply = '1' and s_failed = '0' and
                                su18_written = CINT_BODY_BYTES) then
                                styp_state <= STATE_COMMIT;
                            else
                                o_committed <= '1';
                                o_commit_error <= '1';
                            end if;
                        elsif (i_byte_request = '1' and o_byte_ready = '1') then
                            su18_address <= iu18_byte_address;
                            vint_address := to_integer(iu18_byte_address);
                            if (s_legal = '0' or (i_byte_write = '1' and s_write_legal = '0')) then
                                o_byte_response <= '1';
                                o_byte_error <= '1';
                                s_failed <= '1';
                            else
                                if (i_byte_write = '1') then
                                    su18_written <= su18_written + 1;
                                end if;
                                if (vint_address < CINT_RAM_BYTES) then
                                    s_memory_canceled <= '0';
                                    styp_state <= STATE_MEMORY;
                                elsif (i_byte_write = '0') then
                                    styp_state <= STATE_SCAN_READ;
                                else
                                    if (vint_address >= CINT_T80_BASE and vint_address < CINT_BOARD_BASE) then
                                        vint_offset := vint_address - CINT_T80_BASE;
                                        su256_t80(8*vint_offset + 7 downto 8*vint_offset) <= iu8_byte_data;
                                    elsif (vint_address >= CINT_BOARD_BASE and vint_address < CINT_FM_BASE) then
                                        vint_offset := vint_address - CINT_BOARD_BASE;
                                        su512_board(8*vint_offset + 7 downto 8*vint_offset) <= iu8_byte_data;
                                    else
                                        vu32_word := su32_word;
                                        vint_offset := to_integer(iu18_byte_address(1 downto 0));
                                        vu32_word(8*vint_offset + 7 downto 8*vint_offset) := iu8_byte_data;
                                        su32_word <= vu32_word;
                                    end if;
                                    if ((vint_address < CINT_T80_BASE or vint_address >= CINT_FM_BASE) and
                                        iu18_byte_address(1 downto 0) = 3) then
                                        styp_state <= STATE_SCAN_WRITE;
                                    else
                                        o_byte_response <= '1';
                                    end if;
                                end if;
                            end if;
                        end if;
                    when STATE_MEMORY =>
                        if (i_memory_response = '1') then
                            o_byte_response <= '1';
                            o_byte_error <= i_memory_error or not s_enable or s_memory_canceled;
                            ou8_byte_data <= iu8_memory_data;
                            if (i_memory_error = '1' or s_enable /= '1' or s_memory_canceled = '1') then
                                s_failed <= '1';
                            end if;
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_SCAN_READ =>
                        vint_address := to_integer(su18_address);
                        vu8_data := (others => '0');
                        if (vint_address < CINT_T80_BASE) then
                            -- Unused donor words can contain uninitialized
                            -- placeholders. The serialized ABI always uses0.
                            if (sint_word /= 16 and sint_word /= 17 and sint_word /= 21 and sint_word /= 23) then
                                vu8_data := iu32_m68k_data(8*sint_lane + 7 downto 8*sint_lane);
                            end if;
                        elsif (vint_address < CINT_BOARD_BASE) then
                            vint_offset := vint_address - CINT_T80_BASE;
                            vu8_data := iu256_t80_data(8*vint_offset + 7 downto 8*vint_offset);
                        elsif (vint_address < CINT_FM_BASE) then
                            vint_offset := vint_address - CINT_BOARD_BASE;
                            vu8_data := iu512_board_data(8*vint_offset + 7 downto 8*vint_offset);
                        elsif (vint_address < CINT_ADPCM_BASE) then
                            if (vint_address < CINT_ADPCM_BASE - 2) then
                                vu8_data := iu32_fm_data(8*sint_lane + 7 downto 8*sint_lane);
                            end if;
                        else
                            vu8_data := iu32_adpcm_data(8*sint_lane + 7 downto 8*sint_lane);
                            if (vint_address = CINT_BODY_BYTES - 1) then
                                vu8_data(7 downto 5) := (others => '0');
                            end if;
                        end if;
                        ou8_byte_data <= vu8_data;
                        o_byte_response <= '1';
                        o_byte_error <= not s_enable;
                        styp_state <= STATE_IDLE;
                    when STATE_SCAN_WRITE =>
                        o_byte_response <= '1';
                        o_byte_error <= not s_enable;
                        if (s_enable /= '1') then
                            s_failed <= '1';
                        end if;
                        styp_state <= STATE_IDLE;
                    when STATE_COMMIT =>
                        o_committed <= '1';
                        o_commit_error <= not s_enable;
                        s_apply <= '0';
                        if (s_enable /= '1') then
                            s_failed <= '1';
                        end if;
                        styp_state <= STATE_IDLE;
                end case;
            end if;
        end if;
    end process;
end architecture;
