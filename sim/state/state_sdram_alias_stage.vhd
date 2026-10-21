-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

-- Six transparent stages plus the real adapter reproduce the game's seven
-- inout associations. No data is sampled or driven in a transparent stage.
entity state_sdram_alias_stage is
    generic (
        GINT_REMAINING : natural := 5
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        o_initialized : out std_logic;
        iu3_requests : in unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        iu3_writes : in unsigned(2 downto 0);
        iu27_addresses : in t_sdram_addresses;
        iu16_data : in t_sdram_write_data;
        iu2_bytes : in t_sdram_byte_enables;
        ou3_valid : out unsigned(2 downto 0);
        ou64_data : out t_sdram_read_data;
        iou16_sdram_data : inout unsigned(15 downto 0);
        ou13_sdram_address : out unsigned(12 downto 0);
        ou2_sdram_bank : out unsigned(1 downto 0);
        ou2_sdram_mask : out unsigned(1 downto 0);
        o_sdram_cs : out std_logic;
        o_sdram_we : out std_logic;
        o_sdram_ras : out std_logic;
        o_sdram_cas : out std_logic;
        o_sdram_cke : out std_logic
    );
end entity;

architecture test of state_sdram_alias_stage is
begin
    leaf : if GINT_REMAINING = 0 generate
        controller : entity work.rabbitpunch_sdram
            generic map (
                GINT_READ_CAPTURE_ADJUST => 1
            )
            port map (
                i_clk => i_clk,
                i_initialize => i_initialize,
                o_initialized => o_initialized,
                iu3_requests => iu3_requests,
                ou3_ready => ou3_ready,
                iu3_writes => iu3_writes,
                iu27_byte_addresses => iu27_addresses,
                iu16_write_data => iu16_data,
                iu2_byte_enables => iu2_bytes,
                ou3_response_valid => ou3_valid,
                ou64_read_data => ou64_data,
                iou16_sdram_data => iou16_sdram_data,
                ou13_sdram_address => ou13_sdram_address,
                ou2_sdram_bank => ou2_sdram_bank,
                ou2_sdram_byte_mask => ou2_sdram_mask,
                o_sdram_chip_select => o_sdram_cs,
                o_sdram_write_n => o_sdram_we,
                o_sdram_row_n => o_sdram_ras,
                o_sdram_column_n => o_sdram_cas,
                o_sdram_clock_enable => o_sdram_cke
            );
    end generate;
    nested : if GINT_REMAINING > 0 generate
        child : entity work.state_sdram_alias_stage
            generic map (
                GINT_REMAINING => GINT_REMAINING - 1
            )
            port map (
                i_clk => i_clk,
                i_initialize => i_initialize,
                o_initialized => o_initialized,
                iu3_requests => iu3_requests,
                ou3_ready => ou3_ready,
                iu3_writes => iu3_writes,
                iu27_addresses => iu27_addresses,
                iu16_data => iu16_data,
                iu2_bytes => iu2_bytes,
                ou3_valid => ou3_valid,
                ou64_data => ou64_data,
                iou16_sdram_data => iou16_sdram_data,
                ou13_sdram_address => ou13_sdram_address,
                ou2_sdram_bank => ou2_sdram_bank,
                ou2_sdram_mask => ou2_sdram_mask,
                o_sdram_cs => o_sdram_cs,
                o_sdram_we => o_sdram_we,
                o_sdram_ras => o_sdram_ras,
                o_sdram_cas => o_sdram_cas,
                o_sdram_cke => o_sdram_cke
            );
    end generate;
end architecture;
