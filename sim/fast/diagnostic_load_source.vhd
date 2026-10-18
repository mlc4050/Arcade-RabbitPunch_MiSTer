-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.diagnostic_program.all;

-- Simulation stimulus at the production HPS-signal boundary, with delayed DDR replies.
entity diagnostic_load_source is
    generic (
        GBOOL_DDR_MODE : boolean := false;
        GINT_IMAGE_BYTES : positive := CINT_ROM_IMAGE_SIZE
    );
    port (
        i_clk : in std_logic;
        i_word_ready : in std_logic;
        o_download_active : out std_logic;
        o_word_valid : out std_logic;
        ou27_word_byte_address : out unsigned(26 downto 0);
        ou16_word_data : out unsigned(15 downto 0);
        o_complete : out std_logic := '0'
    );
end entity;

architecture test of diagnostic_load_source is
    type t_host_state is (STATE_INITIALIZE, STATE_START, STATE_DROP_WRITE,
        STATE_WAIT_BYTE, STATE_DDR_HOST, STATE_RELEASE_WAIT, STATE_DRAIN, STATE_COMPLETE);
    signal styp_host_state : t_host_state := STATE_INITIALIZE;
    signal sint_cycles : natural range 0 to 60000000 := 0;
    signal sint_byte : natural range 0 to GINT_IMAGE_BYTES - 1 := 0;
    signal sint_wait : natural range 0 to 32 := 0;
    signal sint_words : natural range 0 to GINT_IMAGE_BYTES / 2 := 0;
    signal sint_reads : natural range 0 to GINT_IMAGE_BYTES / 8 := 0;
    signal s_initialize : std_logic := '1';
    signal s_framework_reset : std_logic := '1';
    signal s_host_download, s_host_write : std_logic := '0';
    signal su27_host_address : unsigned(26 downto 0) := (others => '0');
    signal su8_host_data : unsigned(7 downto 0) := (others => '0');
    signal s_host_wait, s_active, s_done, s_error, s_ddr_mode, s_word_valid : std_logic;
    signal su27_word_address : unsigned(26 downto 0);
    signal su16_word_data : unsigned(15 downto 0);
    signal s_ddr_busy, s_ddr_read, s_ddr_write : std_logic;
    signal s_ddr_valid : std_logic := '0';
    signal su8_burst, su8_bytes : unsigned(7 downto 0);
    signal su29_address : unsigned(28 downto 0);
    signal su64_read_data : unsigned(63 downto 0) := (others => '0');
    signal su64_write_data : unsigned(63 downto 0);
    function image_byte(iint_address : natural) return unsigned is
        variable vu16_word : unsigned(15 downto 0);
    begin
        vu16_word := program_word(iint_address / 2);
        if (iint_address mod 2 = 0) then
            return vu16_word(7 downto 0);
        else
            return vu16_word(15 downto 8);
        end if;
    end function;
begin
    assert (GINT_IMAGE_BYTES mod 8 = 0) report "Diagnostic image must contain complete DDR beats" severity failure;
    o_download_active <= s_active;
    o_word_valid <= s_word_valid;
    ou27_word_byte_address <= su27_word_address;
    ou16_word_data <= su16_word_data;
    s_ddr_busy <= '1' when sint_cycles < 24 or sint_cycles mod 19 < 5 else '0';
    frontend : entity work.rabbitpunch_load_frontend
        generic map (
            GINT_IMAGE_BYTES => GINT_IMAGE_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => s_initialize,
            i_framework_reset => s_framework_reset,
            i_start_ready => '1',
            i_host_download => s_host_download,
            iu16_host_index => to_unsigned(0, 16),
            i_host_write => s_host_write,
            iu27_host_byte_address => su27_host_address,
            iu8_host_data => su8_host_data,
            o_host_wait => s_host_wait,
            o_download_active => s_active,
            o_done => s_done,
            o_error => s_error,
            o_ddr_mode => s_ddr_mode,
            o_word_valid => s_word_valid,
            i_word_ready => i_word_ready,
            ou27_word_byte_address => su27_word_address,
            ou16_word_data => su16_word_data,
            i_ddr_busy => s_ddr_busy,
            ou8_ddr_burst_count => su8_burst,
            ou29_ddr_word_address => su29_address,
            iu64_ddr_read_data => su64_read_data,
            i_ddr_read_valid => s_ddr_valid,
            o_ddr_read => s_ddr_read,
            ou64_ddr_write_data => su64_write_data,
            ou8_ddr_byte_enables => su8_bytes,
            o_ddr_write => s_ddr_write
        );
    host : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            sint_cycles <= sint_cycles + 1;
            s_host_write <= '0';
            case styp_host_state is
                when STATE_INITIALIZE =>
                    if (sint_cycles = 4) then
                        s_initialize <= '0';
                        styp_host_state <= STATE_START;
                    end if;
                when STATE_START =>
                    s_host_download <= '1';
                    if (GBOOL_DDR_MODE) then
                        styp_host_state <= STATE_DDR_HOST;
                    else
                        su8_host_data <= image_byte(0);
                        s_host_write <= '1';
                        styp_host_state <= STATE_DROP_WRITE;
                    end if;
                when STATE_DROP_WRITE =>
                    if (sint_byte = GINT_IMAGE_BYTES - 1) then
                        s_host_download <= '0';
                        styp_host_state <= STATE_DRAIN;
                    else
                        sint_byte <= sint_byte + 1;
                        styp_host_state <= STATE_WAIT_BYTE;
                    end if;
                when STATE_WAIT_BYTE =>
                    if (s_host_wait = '0') then
                        su27_host_address <= to_unsigned(sint_byte, 27);
                        su8_host_data <= image_byte(sint_byte);
                        s_host_write <= '1';
                        styp_host_state <= STATE_DROP_WRITE;
                    end if;
                when STATE_DDR_HOST =>
                    if (sint_wait = 8) then
                        s_host_download <= '0';
                        sint_wait <= 0;
                        styp_host_state <= STATE_RELEASE_WAIT;
                    else
                        sint_wait <= sint_wait + 1;
                    end if;
                when STATE_RELEASE_WAIT =>
                    assert (s_ddr_read = '0') report "DDR read before framework reset release" severity failure;
                    if (sint_wait = 32) then
                        s_framework_reset <= '0';
                        styp_host_state <= STATE_DRAIN;
                    else
                        sint_wait <= sint_wait + 1;
                    end if;
                when STATE_DRAIN =>
                    if (s_done = '1') then
                        assert (sint_words = GINT_IMAGE_BYTES / 2 and s_active = '0' and s_word_valid = '0')
                            report "Frontend completed before the full image drained" severity failure;
                        if (GBOOL_DDR_MODE) then
                            assert (sint_reads = GINT_IMAGE_BYTES / 8 and s_ddr_mode = '1')
                                report "Full DDR image read count or mode mismatch" severity failure;
                        else
                            assert (sint_reads = 0 and s_ddr_mode = '0')
                                report "Direct byte image unexpectedly copied DDR" severity failure;
                        end if;
                        s_framework_reset <= '0';
                        o_complete <= '1';
                        styp_host_state <= STATE_COMPLETE;
                    end if;
                when STATE_COMPLETE =>
                    assert (s_ddr_read = '0' and s_word_valid = '0' and s_active = '0')
                        report "Frontend repeated traffic after completion" severity failure;
            end case;
        end if;
    end process;
    backend : process(i_clk)
        variable v_pending, v_stalled : boolean := false;
        variable vint_delay : natural range 0 to 33 := 0;
        variable vint_base : natural range 0 to GINT_IMAGE_BYTES / 2 := 0;
        variable vu27_stalled_address : unsigned(26 downto 0);
        variable vu16_stalled_data : unsigned(15 downto 0);
        variable vu64_reply : unsigned(63 downto 0);
    begin
        if (rising_edge(i_clk)) then
            s_ddr_valid <= '0';
            su64_read_data <= x"BAD0BAD1BAD2BAD3";
            assert (s_ddr_write = '0') report "Load-only DDR frontend wrote staging memory" severity failure;
            if (s_initialize = '0') then
                assert (s_error = '0') report "Full image rejected by load frontend" severity failure;
                if (s_ddr_read = '1') then
                    assert (GBOOL_DDR_MODE and s_framework_reset = '0' and s_ddr_busy = '0' and not v_pending)
                        report "Invalid, early or repeated DDR read" severity failure;
                    assert (su8_burst = 1 and su8_bytes = x"FF" and su29_address = to_unsigned(16#6000000# + sint_reads, 29))
                        report "Full-image DDR address, burst or lane mismatch" severity failure;
                    vint_base := sint_reads * 4;
                    vint_delay := 3 + (sint_reads mod 7) * 5;
                    v_pending := true;
                    sint_reads <= sint_reads + 1;
                elsif (v_pending) then
                    if (vint_delay = 0) then
                        for vint_lane in 0 to 3 loop
                            vu64_reply(vint_lane * 16 + 15 downto vint_lane * 16) := program_word(vint_base + vint_lane);
                        end loop;
                        su64_read_data <= vu64_reply;
                        s_ddr_valid <= '1';
                        v_pending := false;
                    else
                        vint_delay := vint_delay - 1;
                    end if;
                end if;
                if (v_stalled) then
                    assert (s_word_valid = '1' and su27_word_address = vu27_stalled_address and su16_word_data = vu16_stalled_data)
                        report "Frontend changed a stalled word" severity failure;
                end if;
                v_stalled := s_word_valid = '1' and i_word_ready = '0';
                vu27_stalled_address := su27_word_address;
                vu16_stalled_data := su16_word_data;
                if (s_word_valid = '1' and i_word_ready = '1') then
                    assert (su27_word_address = sint_words * 2 and su16_word_data = program_word(sint_words))
                        report "Full image word lost, repeated, reordered or byte swapped" severity failure;
                    sint_words <= sint_words + 1;
                end if;
                if (s_done = '1') then
                    assert (not v_pending) report "Frontend completed with DDR read debt" severity failure;
                end if;
            end if;
        end if;
    end process;
end architecture;
