-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Place before an acknowledged RAM backend. During capture entry, read the
-- old word before each game write. The last completed write before the GX
-- level-7 acknowledgement is the 68000's PC-low push. Undo it before taking
-- the RAM image. The parent must qualify every possible stack RAM bank and
-- check the journal address against the captured SSP-2 before accepting an
-- image. MMIO must never be marked for a speculative old-word read.
-- Backend requests are pulses; every accepted request must return exactly
-- one response. Initialization cancels the caller, but drains backend debt.
entity rabbitpunch_capture_stack_undo is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_request : in std_logic;
        o_ready : out std_logic;
        i_write : in std_logic;
        i_capture_ram_write : in std_logic;
        iu24_address : in unsigned(23 downto 0);
        iu16_write_data : in unsigned(15 downto 0);
        iu2_bytes : in unsigned(1 downto 0);
        o_response : out std_logic;
        ou16_read_data : out unsigned(15 downto 0);
        i_level7_acknowledge : in std_logic;
        i_discard_journal : in std_logic;
        o_journal_valid : out std_logic;
        ou24_journal_address : out unsigned(23 downto 0);
        o_undo_completed : out std_logic;
        o_undo_error : out std_logic;
        o_idle : out std_logic;
        o_backend_request : out std_logic;
        o_backend_write : out std_logic;
        ou24_backend_address : out unsigned(23 downto 0);
        ou16_backend_data : out unsigned(15 downto 0);
        ou2_backend_bytes : out unsigned(1 downto 0);
        i_backend_response : in std_logic;
        iu16_backend_data : in unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_capture_stack_undo is
    type t_state is (STATE_IDLE, STATE_READ_OLD, STATE_WRITE_GAME,
        STATE_PASS, STATE_UNDO, STATE_DRAIN);
    signal styp_state : t_state := STATE_IDLE;
    signal s_journal_valid, s_acknowledge_seen : std_logic := '0';
    signal su24_address, su24_journal_address : unsigned(23 downto 0) := (others => '0');
    signal su16_write_data, su16_old_data : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes, su2_journal_bytes : unsigned(1 downto 0) := (others => '0');
    signal s_response : std_logic := '0';
    signal su16_read_data : unsigned(15 downto 0) := (others => '0');
begin
    -- Ordinary reads/writes retain the original bus adapter's acknowledgement
    -- edge. An extra reply register here adds real 68000 wait states. Capture
    -- writes keep their separate old-word/read/write transaction sequence.
    o_response <= '0' when i_initialize = '1' else
        i_backend_response when styp_state = STATE_PASS else s_response;
    ou16_read_data <= iu16_backend_data when styp_state = STATE_PASS else su16_read_data;
    o_ready <= '1' when styp_state = STATE_IDLE and i_initialize = '0' and
        i_level7_acknowledge = '0' and i_discard_journal = '0' else '0';
    o_idle <= '1' when styp_state = STATE_IDLE else '0';
    o_journal_valid <= s_journal_valid;
    ou24_journal_address <= su24_journal_address;
    transfer : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_backend_request <= '0';
            s_response <= '0';
            o_undo_completed <= '0';
            o_undo_error <= '0';
            s_acknowledge_seen <= i_level7_acknowledge;
            assert (i_backend_response = '0' or styp_state /= STATE_IDLE)
                report "Unowned capture undo backend response" severity failure;
            if (i_initialize = '1') then
                s_journal_valid <= '0';
                if (styp_state = STATE_IDLE or i_backend_response = '1') then
                    styp_state <= STATE_IDLE;
                else
                    styp_state <= STATE_DRAIN;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (i_discard_journal = '1') then
                            s_journal_valid <= '0';
                        elsif (i_level7_acknowledge = '1' and s_acknowledge_seen = '0') then
                            if (s_journal_valid = '1') then
                                o_backend_request <= '1';
                                o_backend_write <= '1';
                                ou24_backend_address <= su24_journal_address;
                                ou16_backend_data <= su16_old_data;
                                ou2_backend_bytes <= su2_journal_bytes;
                                styp_state <= STATE_UNDO;
                            else
                                o_undo_error <= '1';
                            end if;
                        elsif (i_request = '1' and i_level7_acknowledge = '0') then
                            su24_address <= iu24_address;
                            su16_write_data <= iu16_write_data;
                            su2_bytes <= iu2_bytes;
                            o_backend_request <= '1';
                            ou24_backend_address <= iu24_address;
                            ou16_backend_data <= iu16_write_data;
                            ou2_backend_bytes <= iu2_bytes;
                            if (i_write = '1' and i_capture_ram_write = '1') then
                                -- Read the whole old word; undo uses original lanes.
                                o_backend_write <= '0';
                                ou2_backend_bytes <= "11";
                                styp_state <= STATE_READ_OLD;
                            else
                                o_backend_write <= i_write;
                                styp_state <= STATE_PASS;
                            end if;
                        end if;
                    when STATE_READ_OLD =>
                        if (i_backend_response = '1') then
                            su16_old_data <= iu16_backend_data;
                            su24_journal_address <= su24_address;
                            su2_journal_bytes <= su2_bytes;
                            s_journal_valid <= '0';
                            o_backend_request <= '1';
                            o_backend_write <= '1';
                            ou24_backend_address <= su24_address;
                            ou16_backend_data <= su16_write_data;
                            ou2_backend_bytes <= su2_bytes;
                            styp_state <= STATE_WRITE_GAME;
                        end if;
                    when STATE_WRITE_GAME =>
                        if (i_backend_response = '1') then
                            s_journal_valid <= '1';
                            s_response <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_PASS =>
                        if (i_backend_response = '1') then
                            su16_read_data <= iu16_backend_data;
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_UNDO =>
                        if (i_backend_response = '1') then
                            s_journal_valid <= '0';
                            o_undo_completed <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAIN =>
                        if (i_backend_response = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
                assert (i_level7_acknowledge = '0' or s_acknowledge_seen = '1' or styp_state = STATE_IDLE)
                    report "Capture IACK arrived before RAM transaction completed" severity failure;
            end if;
        end if;
    end process;
end architecture;
