-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- Read-only legality pass over BODY bytes in the sealed private image. Run
-- alongside framing/identity/CRC preflight, before any machine-state write.
entity rabbitpunch_state_semantics is
    generic (
        GINT_HORIZONTAL_TOTAL : positive := 432;
        GINT_VERTICAL_TOTAL : positive := 256
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        i_abort : in std_logic;
        i_byte_valid : in std_logic;
        o_byte_ready : out std_logic;
        iu8_byte_data : in unsigned(7 downto 0);
        i_finish : in std_logic;
        o_active : out std_logic;
        o_finished : out std_logic;
        o_valid : out std_logic;
        ou4_error : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_semantics is
    signal s_active, s_valid : std_logic := '0';
    signal su18_count : unsigned(17 downto 0) := (others => '0');
    signal su32_word : unsigned(31 downto 0) := (others => '0');
    signal su256_t80 : unsigned(255 downto 0) := (others => '0');
    signal su512_board : unsigned(511 downto 0) := (others => '0');
    signal su4_error : unsigned(3 downto 0) := (others => '0');
begin
    assert (GINT_HORIZONTAL_TOTAL <= 512 and GINT_VERTICAL_TOTAL <= 512)
        report "Saved beam fields are nine bits each" severity failure;
    o_active <= s_active;
    o_valid <= s_valid;
    ou4_error <= su4_error;
    o_byte_ready <= s_active and not i_initialize and not i_start and not i_abort;
    validate : process(i_clk)
        variable vu18_count : unsigned(17 downto 0);
        variable vu32_word : unsigned(31 downto 0);
        variable vu256_t80 : unsigned(255 downto 0);
        variable vu512_board : unsigned(511 downto 0);
        variable vu4_error : unsigned(3 downto 0);
        variable vint_offset, vint_lane, vint_word : natural;
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            if (i_initialize = '1') then
                s_active <= '0';
                s_valid <= '0';
                su4_error <= (others => '0');
            elsif (i_abort = '1') then
                o_finished <= s_active;
                s_active <= '0';
                s_valid <= '0';
                su4_error <= to_unsigned(6, 4);
            elsif (i_start = '1') then
                assert (s_active = '0') report "Body semantics restarted while active" severity failure;
                s_active <= '1';
                s_valid <= '0';
                su18_count <= (others => '0');
                su32_word <= (others => '0');
                su256_t80 <= (others => '0');
                su512_board <= (others => '0');
                su4_error <= (others => '0');
            elsif (s_active = '1') then
                vu18_count := su18_count;
                vu4_error := su4_error;
                if (i_byte_valid = '1') then
                    vint_offset := to_integer(su18_count);
                    if (vint_offset >= CINT_BODY_BYTES) then
                        if (vu4_error = 0) then
                            vu4_error := to_unsigned(8, 4);
                        end if;
                    else
                        if (vint_offset >= CINT_M68K_BASE and vint_offset < CINT_T80_BASE) then
                            vint_lane := (vint_offset - CINT_M68K_BASE) mod 4;
                            vint_word := (vint_offset - CINT_M68K_BASE)/4;
                            vu32_word := su32_word;
                            vu32_word(8*vint_lane + 7 downto 8*vint_lane) := iu8_byte_data;
                            su32_word <= vu32_word;
                            if (vint_lane = 3 and not F_M68K_WORD_VALID(vint_word, vu32_word) and vu4_error = 0) then
                                vu4_error := to_unsigned(2, 4);
                            end if;
                        elsif (vint_offset >= CINT_T80_BASE and vint_offset < CINT_BOARD_BASE) then
                            vint_lane := vint_offset - CINT_T80_BASE;
                            vu256_t80 := su256_t80;
                            vu256_t80(8*vint_lane + 7 downto 8*vint_lane) := iu8_byte_data;
                            su256_t80 <= vu256_t80;
                            if (vint_lane = 31 and not F_T80_VALID(vu256_t80) and vu4_error = 0) then
                                vu4_error := to_unsigned(3, 4);
                            end if;
                        elsif (vint_offset >= CINT_BOARD_BASE and vint_offset < CINT_FM_BASE) then
                            vint_lane := vint_offset - CINT_BOARD_BASE;
                            vu512_board := su512_board;
                            vu512_board(8*vint_lane + 7 downto 8*vint_lane) := iu8_byte_data;
                            su512_board <= vu512_board;
                            if (vint_lane = 63 and not F_BOARD_VALID(vu512_board,
                                GINT_HORIZONTAL_TOTAL, GINT_VERTICAL_TOTAL) and vu4_error = 0) then
                                vu4_error := to_unsigned(4, 4);
                            end if;
                        elsif (vint_offset >= CINT_ADPCM_BASE - 2 and vint_offset < CINT_ADPCM_BASE and
                            iu8_byte_data /= 0 and vu4_error = 0) then
                            -- JT51's126 words have only4016 meaningful bits.
                            vu4_error := to_unsigned(5, 4);
                        elsif (vint_offset = CINT_BODY_BYTES - 1 and
                            iu8_byte_data(7 downto 5) /= 0 and vu4_error = 0) then
                            -- Corrected JT7759 has189 meaningful scan bits.
                            vu4_error := to_unsigned(9, 4);
                        end if;
                        vu18_count := vu18_count + 1;
                    end if;
                end if;
                if (i_finish = '1') then
                    s_active <= '0';
                    o_finished <= '1';
                    if (vu18_count /= CINT_BODY_BYTES and vu4_error = 0) then
                        vu4_error := to_unsigned(7, 4);
                    end if;
                    if (vu4_error = 0) then
                        s_valid <= '1';
                    end if;
                end if;
                su18_count <= vu18_count;
                su4_error <= vu4_error;
            end if;
        end if;
    end process;
end architecture;
