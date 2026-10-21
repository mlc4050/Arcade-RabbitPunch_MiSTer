-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

entity state_sdram_alias_eval is
    port (
        i_clk : in std_logic;
        i_chip_clk : in std_logic;
        i_initialize : in std_logic;
        o_initialized : out std_logic;
        o_complete : out std_logic;
        ou32_clock : out unsigned(31 downto 0);
        ou3_requests : out unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        ou3_valid : out unsigned(2 downto 0);
        ou3_reads : out unsigned(2 downto 0);
        ou64_data0 : out unsigned(63 downto 0);
        ou64_data1 : out unsigned(63 downto 0);
        ou64_data2 : out unsigned(63 downto 0);
        ou22_command : out unsigned(21 downto 0)
    );
end entity;

architecture test of state_sdram_alias_eval is
    component sdram_chip_model_wide is
        port (
            clk : in std_logic;
            SDRAM_DQ : inout unsigned(15 downto 0);
            SDRAM_A : in unsigned(12 downto 0);
            SDRAM_BA : in unsigned(1 downto 0);
            SDRAM_nCS : in std_logic;
            SDRAM_nWE : in std_logic;
            SDRAM_nRAS : in std_logic;
            SDRAM_nCAS : in std_logic
        );
    end component;
    type t_state is (STATE_INITIALIZE, STATE_WRITE_ISSUE, STATE_WRITE_WAIT,
        STATE_READ_ISSUE, STATE_READ_WAIT, STATE_DONE);
    signal styp_state : t_state := STATE_INITIALIZE;
    signal su3_requests, su3_writes : unsigned(2 downto 0) := (others => '0');
    signal su3_seen : unsigned(2 downto 0) := (others => '0');
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su16_data : t_sdram_write_data := (others => (others => '0'));
    signal su2_bytes : t_sdram_byte_enables := (others => "11");
    signal su64_data : t_sdram_read_data;
    signal su16_dq : unsigned(15 downto 0);
    signal su13_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_cs, s_we, s_ras, s_cas, s_cke : std_logic;
    signal sint_word : natural range 0 to 255 := 0;
    signal sint_burst : natural range 0 to 63 := 0;
    function F_PATTERN(vint_burst : natural) return unsigned is
    begin
        case vint_burst mod 4 is
            when 0 => return unsigned'(x"CAFEBABE76543210");
            when 1 => return unsigned'(x"0123456789ABCDEF");
            when 2 => return unsigned'(x"0F0F55AA33CCCC33");
            when others => return unsigned'(x"80800100FEFF7F7E");
        end case;
    end function;
begin
    o_complete <= '1' when styp_state = STATE_DONE else '0';
    ou3_requests <= su3_requests;
    ou3_reads <= ou3_valid when styp_state = STATE_READ_WAIT else "000";
    ou64_data0 <= su64_data(0);
    ou64_data1 <= su64_data(1);
    ou64_data2 <= su64_data(2);
    -- Row/column/bank are not operands of NOP, refresh or burst termination.
    -- Keep DQM and command/select/clock-enable visible on every clock: DQM
    -- can still mask later write-burst beats while the command itself is NOP.
    observe_command : process(all)
        variable vu13_address : unsigned(12 downto 0);
        variable vu2_bank : unsigned(1 downto 0);
        variable vu3_command : unsigned(2 downto 0);
    begin
        vu13_address := (others => '0');
        vu2_bank := (others => '0');
        vu3_command := s_ras & s_cas & s_we;
        if (vu3_command = "011" or vu3_command = "101" or vu3_command = "100" or
            vu3_command = "010" or vu3_command = "000") then
            vu13_address := su13_address;
            vu2_bank := su2_bank;
        end if;
        ou22_command <= vu13_address & vu2_bank & su2_mask & s_cs & s_we & s_ras & s_cas & s_cke;
    end process;
    chain : entity work.state_sdram_alias_stage
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            o_initialized => o_initialized,
            iu3_requests => su3_requests,
            ou3_ready => ou3_ready,
            iu3_writes => su3_writes,
            iu27_addresses => su27_addresses,
            iu16_data => su16_data,
            iu2_bytes => su2_bytes,
            ou3_valid => ou3_valid,
            ou64_data => su64_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_mask => su2_mask,
            o_sdram_cs => s_cs,
            o_sdram_we => s_we,
            o_sdram_ras => s_ras,
            o_sdram_cas => s_cas,
            o_sdram_cke => s_cke
        );
    chip : sdram_chip_model_wide
        port map (
            clk => i_chip_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_cs,
            SDRAM_nWE => s_we,
            SDRAM_nRAS => s_ras,
            SDRAM_nCAS => s_cas
        );
    sequence_requests : process(i_clk)
        variable vu64_pattern : unsigned(63 downto 0);
        variable vu3_seen : unsigned(2 downto 0);
        variable vint_group : natural;
    begin
        if (rising_edge(i_clk)) then
            su3_requests <= (others => '0');
            if (i_initialize = '1') then
                styp_state <= STATE_INITIALIZE;
                ou32_clock <= (others => '0');
                sint_word <= 0;
                sint_burst <= 0;
                su3_writes <= (others => '0');
                su3_seen <= (others => '0');
            else
                ou32_clock <= ou32_clock + 1;
                case styp_state is
                    when STATE_INITIALIZE =>
                        if (o_initialized = '1') then
                            styp_state <= STATE_WRITE_ISSUE;
                        end if;
                    when STATE_WRITE_ISSUE =>
                        if (ou3_ready(2) = '1') then
                            vu64_pattern := F_PATTERN(sint_word / 4);
                            su27_addresses(2) <= to_unsigned(sint_word * 2, 27);
                            su16_data(2) <= vu64_pattern((sint_word mod 4) * 16 + 15 downto (sint_word mod 4) * 16);
                            su3_writes(2) <= '1';
                            su3_requests(2) <= '1';
                            styp_state <= STATE_WRITE_WAIT;
                        end if;
                    when STATE_WRITE_WAIT =>
                        if (ou3_valid(2) = '1') then
                            if (sint_word = 255) then
                                styp_state <= STATE_READ_ISSUE;
                            else
                                sint_word <= sint_word + 1;
                                styp_state <= STATE_WRITE_ISSUE;
                            end if;
                        end if;
                    when STATE_READ_ISSUE =>
                        if (ou3_ready = "111") then
                            su3_writes <= (others => '0');
                            su3_seen <= (others => '0');
                            for vint_port in 0 to 2 loop
                                vint_group := (sint_burst + vint_port) mod 64;
                                su27_addresses(vint_port) <= to_unsigned(vint_group * 8, 27);
                            end loop;
                            su3_requests <= "111";
                            styp_state <= STATE_READ_WAIT;
                        end if;
                    when STATE_READ_WAIT =>
                        vu3_seen := su3_seen;
                        for vint_port in 0 to 2 loop
                            if (ou3_valid(vint_port) = '1') then
                                assert (su3_seen(vint_port) = '0') report "Duplicate read response" severity failure;
                                assert (su64_data(vint_port) = F_PATTERN(sint_burst + vint_port))
                                    report "Seven-stage DQ readback differs" severity failure;
                                vu3_seen(vint_port) := '1';
                            end if;
                        end loop;
                        su3_seen <= vu3_seen;
                        if (vu3_seen = "111") then
                            if (sint_burst = 63) then
                                styp_state <= STATE_DONE;
                            else
                                sint_burst <= sint_burst + 1;
                                styp_state <= STATE_READ_ISSUE;
                            end if;
                        end if;
                    when STATE_DONE =>
                        null;
                end case;
            end if;
        end if;
    end process;
end architecture;
