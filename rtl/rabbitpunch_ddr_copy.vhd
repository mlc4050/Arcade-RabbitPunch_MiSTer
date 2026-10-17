-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- Load-time only: copy the HPS 0x30000000 window into our ready/valid word stream.
-- Caller owns the DDR port for the complete copy. Cold initialization must not
-- cancel an in-flight DDR read; game reset does not connect to this input.
entity rabbitpunch_ddr_copy is
    generic (
        sint_IMAGE_BYTES : positive := ROM_IMAGE_SIZE
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_start : in std_logic;
        o_active : out std_logic;
        o_done : out std_logic;
        o_word_valid : out std_logic;
        i_word_ready : in std_logic;
        ou27_word_byte_address : out unsigned(26 downto 0);
        ou16_word_data : out unsigned(15 downto 0);
        i_ddr_busy : in std_logic;
        ou8_ddr_burst_count : out unsigned(7 downto 0);
        ou29_ddr_word_address : out unsigned(28 downto 0);
        iu64_ddr_read_data : in unsigned(63 downto 0);
        i_ddr_read_valid : in std_logic;
        o_ddr_read : out std_logic;
        ou64_ddr_write_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0);
        o_ddr_write : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_ddr_copy is
    component rom_loader is
        generic (LENGTH : integer := ROM_IMAGE_SIZE);
        port (
            clk : in std_logic;
            reset : in std_logic;
            start : in std_logic;
            busy : out std_logic;
            needs_adpcma_swap : in std_logic;
            adpcma_base : in unsigned(24 downto 0);
            ddr_req : out std_logic;
            ddr_addr : out unsigned(27 downto 0);
            ddr_busy : in std_logic;
            ddr_valid : in std_logic;
            ddr_rdata : in unsigned(63 downto 0);
            dl_req : out std_logic;
            dl_addr : out unsigned(24 downto 0);
            dl_data : out unsigned(15 downto 0);
            dl_we16 : out std_logic;
            dl_busy : in std_logic
        );
    end component;
    component ddram_phy is
        port (
            clk : in std_logic;
            reset : in std_logic;
            DDRAM_BUSY : in std_logic;
            DDRAM_BURSTCNT : out unsigned(7 downto 0);
            DDRAM_ADDR : out unsigned(28 downto 0);
            DDRAM_DOUT : in unsigned(63 downto 0);
            DDRAM_DOUT_READY : in std_logic;
            DDRAM_RD : out std_logic;
            DDRAM_DIN : out unsigned(63 downto 0);
            DDRAM_BE : out unsigned(7 downto 0);
            DDRAM_WE : out std_logic;
            req : in std_logic;
            we : in std_logic;
            addr : in unsigned(27 downto 0);
            wdata : in unsigned(7 downto 0);
            busy : out std_logic;
            valid : out std_logic;
            rdata : out unsigned(63 downto 0)
        );
    end component;
    signal s_native_active, s_active, s_ddr_request, s_ddr_busy, s_ddr_valid : std_logic;
    signal s_native_word_request, s_native_word_full : std_logic;
    signal s_word_pending, s_previous_active : std_logic := '0';
    signal su28_ddr_address : unsigned(27 downto 0);
    signal su64_ddr_data : unsigned(63 downto 0);
    signal su25_native_word_address : unsigned(24 downto 0);
    signal su16_native_word_data : unsigned(15 downto 0);
begin
    assert (sint_IMAGE_BYTES mod 8 = 0 and sint_IMAGE_BYTES <= ROM_IMAGE_SIZE and sint_IMAGE_BYTES <= 16#2000000#)
        report "DDR copy image must be eight-byte aligned and fit the unchanged donor address width" severity failure;
    s_active <= s_native_active or s_word_pending;
    o_active <= s_active;
    o_word_valid <= s_word_pending;
    copy_engine : rom_loader
        generic map (LENGTH => sint_IMAGE_BYTES)
        port map (
            clk => i_clk,
            reset => i_initialize,
            start => i_start,
            busy => s_native_active,
            needs_adpcma_swap => '0',
            adpcma_base => (others => '0'),
            ddr_req => s_ddr_request,
            ddr_addr => su28_ddr_address,
            ddr_busy => s_ddr_busy or i_ddr_busy,
            ddr_valid => s_ddr_valid,
            ddr_rdata => su64_ddr_data,
            dl_req => s_native_word_request,
            dl_addr => su25_native_word_address,
            dl_data => su16_native_word_data,
            dl_we16 => s_native_word_full,
            dl_busy => s_word_pending
        );
    ddr_transport : ddram_phy
        port map (
            clk => i_clk,
            reset => i_initialize,
            DDRAM_BUSY => i_ddr_busy,
            DDRAM_BURSTCNT => ou8_ddr_burst_count,
            DDRAM_ADDR => ou29_ddr_word_address,
            DDRAM_DOUT => iu64_ddr_read_data,
            DDRAM_DOUT_READY => i_ddr_read_valid,
            DDRAM_RD => o_ddr_read,
            DDRAM_DIN => ou64_ddr_write_data,
            DDRAM_BE => ou8_ddr_byte_enables,
            DDRAM_WE => o_ddr_write,
            req => s_ddr_request,
            we => '0',
            addr => su28_ddr_address,
            wdata => (others => '0'),
            busy => s_ddr_busy,
            valid => s_ddr_valid,
            rdata => su64_ddr_data
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_done <= '0';
            if (i_initialize = '1') then
                s_word_pending <= '0';
                s_previous_active <= '0';
            else
                assert (i_start /= '1' or s_active = '0') report "DDR copy restarted before draining" severity failure;
                s_previous_active <= s_active;
                if (s_previous_active = '1' and s_active = '0') then
                    o_done <= '1';
                end if;
                -- Native dl_busy acknowledges our one-word credit, not downstream
                -- backpressure. A captured word then waits unchanged for ready.
                if (s_word_pending = '1') then
                    if (i_word_ready = '1') then
                        s_word_pending <= '0';
                    end if;
                elsif (s_native_word_request = '1') then
                    assert (s_native_word_full = '1') report "DDR copy emitted a partial word" severity failure;
                    ou27_word_byte_address <= resize(su25_native_word_address, 27);
                    ou16_word_data <= su16_native_word_data;
                    s_word_pending <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;

