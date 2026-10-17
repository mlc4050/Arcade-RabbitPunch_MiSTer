-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

entity memory_powerup_tb is
    generic (EVALUATION_BOUNDARY : boolean := false);
end entity;

architecture test of memory_powerup_tb is
    -- Component binding permits the same stimulus against RTL and Quartus .vo.
    component rabbitpunch_memory is
        port (
            i_clk : in std_logic;
            i_request : in std_logic;
            i_request_write : in std_logic;
            iu24_request_address : in unsigned(23 downto 0);
            iu16_request_data : in unsigned(15 downto 0);
            iu2_request_bytes : in unsigned(1 downto 0);
            o_request_supported : out std_logic;
            o_response_valid : out std_logic;
            ou16_response_data : out unsigned(15 downto 0);
            o_rom_request : out std_logic;
            ou18_rom_byte_address : out unsigned(17 downto 0);
            i_rom_response_valid : in std_logic;
            iu16_rom_response_data : in unsigned(15 downto 0);
            i_view_enable : in std_logic;
            iu5_view_target : in target_t;
            iu15_view_word_address : in unsigned(14 downto 0);
            o_view_valid : out std_logic;
            ou16_view_data : out unsigned(15 downto 0)
        );
    end component;
    component memory_check is
        port (
            i_clk : in std_logic;
            i_request : in std_logic;
            i_request_write : in std_logic;
            iu24_request_address : in unsigned(23 downto 0);
            iu16_request_data : in unsigned(15 downto 0);
            iu2_request_bytes : in unsigned(1 downto 0);
            o_request_supported : out std_logic;
            o_response_valid : out std_logic;
            ou16_response_data : out unsigned(15 downto 0);
            o_rom_request : out std_logic;
            ou18_rom_byte_address : out unsigned(17 downto 0);
            i_rom_response_valid : in std_logic;
            iu16_rom_response_data : in unsigned(15 downto 0);
            i_view_enable : in std_logic;
            iu5_view_target : in target_t;
            iu15_view_word_address : in unsigned(14 downto 0);
            o_view_valid : out std_logic;
            ou16_view_data : out unsigned(15 downto 0)
        );
    end component;
    signal s_clk : std_logic := '0';
    signal s_request, s_write, s_view : std_logic := '0';
    signal s_supported, s_response, s_view_valid, s_rom_request : std_logic;
    signal su24_address : unsigned(23 downto 0) := (others => '0');
    signal su16_data : unsigned(15 downto 0) := (others => '0');
    signal su16_response, su16_view_data : unsigned(15 downto 0);
    signal su2_bytes : unsigned(1 downto 0) := "11";
    signal su5_target : target_t := TARGET_NONE;
    signal su15_word : unsigned(14 downto 0) := (others => '0');
    type t_naturals is array (0 to 4) of natural;
    type t_targets is array (0 to 4) of target_t;
    constant C_BASES : t_naturals := (16#40000#, 16#60000#, 16#80000#, 16#A0000#, 16#FC000#);
    constant C_DEPTHS : t_naturals := (32768, 2048, 8192, 1024, 8192);
    constant C_TARGETS : t_targets := (TARGET_BITMAP, TARGET_SPRITES, TARGET_TILES, TARGET_PALETTE, TARGET_WORKRAM);
begin
    s_clk <= not s_clk after 5 ns;
    direct_memory : if (not EVALUATION_BOUNDARY) generate
        dut : rabbitpunch_memory
            port map (
                i_clk => s_clk,
                i_request => s_request,
                i_request_write => s_write,
                iu24_request_address => su24_address,
                iu16_request_data => su16_data,
                iu2_request_bytes => su2_bytes,
                o_request_supported => s_supported,
                o_response_valid => s_response,
                ou16_response_data => su16_response,
                o_rom_request => s_rom_request,
                ou18_rom_byte_address => open,
                i_rom_response_valid => '0',
                iu16_rom_response_data => (others => '0'),
                i_view_enable => s_view,
                iu5_view_target => su5_target,
                iu15_view_word_address => su15_word,
                o_view_valid => s_view_valid,
                ou16_view_data => su16_view_data
            );
    end generate;
    registered_memory : if (EVALUATION_BOUNDARY) generate
        dut : memory_check
            port map (
                i_clk => s_clk,
                i_request => s_request,
                i_request_write => s_write,
                iu24_request_address => su24_address,
                iu16_request_data => su16_data,
                iu2_request_bytes => su2_bytes,
                o_request_supported => s_supported,
                o_response_valid => s_response,
                ou16_response_data => su16_response,
                o_rom_request => s_rom_request,
                ou18_rom_byte_address => open,
                i_rom_response_valid => '0',
                iu16_rom_response_data => (others => '0'),
                i_view_enable => s_view,
                iu5_view_target => su5_target,
                iu15_view_word_address => su15_word,
                o_view_valid => s_view_valid,
                ou16_view_data => su16_view_data
            );
    end generate;
    stimulus : process
        variable vint_checks : natural := 0;
        variable vu16_initial, vu16_expected : unsigned(15 downto 0);
        procedure cpu_access(vint_bank, vint_word : natural; v_write : std_logic;
            vu2_lanes : unsigned(1 downto 0); vu16_data, vu16_expected : unsigned(15 downto 0)) is
            variable vint_age : natural := 0;
        begin
            wait until falling_edge(s_clk);
            s_request <= '1';
            s_write <= v_write;
            su24_address <= to_unsigned(C_BASES(vint_bank) + 2 * vint_word, 24);
            su16_data <= vu16_data;
            su2_bytes <= vu2_lanes;
            wait until falling_edge(s_clk);
            s_request <= '0';
            if (EVALUATION_BOUNDARY) then
                wait until falling_edge(s_clk);
            end if;
            assert (s_supported = '1' and s_rom_request = '0')
                report "RAM address decoded incorrectly" severity failure;
            while (s_response /= '1' and vint_age < 100) loop
                wait until falling_edge(s_clk);
                vint_age := vint_age + 1;
            end loop;
            assert (s_response = '1' and vint_age = 1 + boolean'pos(EVALUATION_BOUNDARY))
                report "Unexpected RAM response latency" severity failure;
            if (v_write = '0') then
                assert (su16_response = vu16_expected)
                    report "CPU data mismatch bank=" & integer'image(vint_bank) &
                        " word=" & integer'image(vint_word) severity failure;
            end if;
            vint_checks := vint_checks + 1;
            wait until falling_edge(s_clk);
            assert (s_response = '0') report "Repeated RAM response" severity failure;
        end procedure;
        procedure view_word(vint_bank, vint_word : natural; vu16_expected : unsigned(15 downto 0)) is
        begin
            wait until falling_edge(s_clk);
            s_view <= '1';
            su5_target <= C_TARGETS(vint_bank);
            su15_word <= to_unsigned(vint_word, 15);
            for vint_cycle in 1 to 1 + 2 * boolean'pos(EVALUATION_BOUNDARY) loop
                wait until falling_edge(s_clk);
            end loop;
            assert (s_view_valid = '1' and su16_view_data = vu16_expected)
                report "View data mismatch bank=" & integer'image(vint_bank) &
                    " word=" & integer'image(vint_word) severity failure;
            vint_checks := vint_checks + 1;
            s_view <= '0';
            for vint_cycle in 1 to 1 + 2 * boolean'pos(EVALUATION_BOUNDARY) loop
                wait until falling_edge(s_clk);
            end loop;
            assert (s_view_valid = '0') report "View valid failed to clear" severity failure;
        end procedure;
    begin
        -- Every word is read through both interfaces before the first write.
        for vint_bank in 0 to 4 loop
            vu16_initial := x"0000";
            if (vint_bank = 0) then
                vu16_initial := x"FFFF";
            end if;
            for vint_word in 0 to C_DEPTHS(vint_bank) - 1 loop
                cpu_access(vint_bank, vint_word, '0', "11", x"0000", vu16_initial);
                view_word(vint_bank, vint_word, vu16_initial);
            end loop;
        end loop;
        -- First, middle and last words exercise both byte lanes in each bank.
        for vint_bank in 0 to 4 loop
            vu16_initial := x"0000";
            if (vint_bank = 0) then
                vu16_initial := x"FFFF";
            end if;
            for vint_sample in 0 to 2 loop
                vu16_expected := vu16_initial;
                vu16_expected(15 downto 8) := x"5C";
                cpu_access(vint_bank, vint_sample * (C_DEPTHS(vint_bank) - 1) / 2,
                    '1', "10", x"5CA7", x"0000");
                cpu_access(vint_bank, vint_sample * (C_DEPTHS(vint_bank) - 1) / 2,
                    '0', "11", x"0000", vu16_expected);
                view_word(vint_bank, vint_sample * (C_DEPTHS(vint_bank) - 1) / 2, vu16_expected);
                cpu_access(vint_bank, vint_sample * (C_DEPTHS(vint_bank) - 1) / 2,
                    '1', "01", x"E139", x"0000");
                cpu_access(vint_bank, vint_sample * (C_DEPTHS(vint_bank) - 1) / 2,
                    '0', "11", x"0000", x"5C39");
                view_word(vint_bank, vint_sample * (C_DEPTHS(vint_bank) - 1) / 2, x"5C39");
                if (vint_sample = 2) then
                    view_word(vint_bank, C_DEPTHS(vint_bank) - 2, vu16_initial);
                else
                    view_word(vint_bank, 1 + vint_sample * (C_DEPTHS(vint_bank) - 1) / 2, vu16_initial);
                end if;
            end loop;
        end loop;
        report "MEMORY_POWERUP_PASS: all 52224 words through CPU and view before writes; checks=" & integer'image(vint_checks);
        std.env.finish;
        wait;
    end process;
end architecture;
