library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_sdram_types.all;

entity sdram_tb is
end entity;

architecture test of sdram_tb is
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
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_initialized : std_logic;
    signal su3_requests, su3_writes : unsigned(2 downto 0) := "000";
    signal su3_ready, su3_valid : unsigned(2 downto 0);
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su16_data : t_sdram_write_data := (others => (others => '0'));
    signal su2_bytes : t_sdram_byte_enables := (others => "11");
    signal su64_data : t_sdram_read_data;
    signal su16_dq : unsigned(15 downto 0);
    signal su13_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_refreshes : natural := 0;
    signal sint_max_refresh_gap : natural := 0;
    type t_bases is array (natural range <>) of natural;
    constant BASES : t_bases := (0, 16#1000#, 16#50000#, 16#D0000#, 16#150000#,
        16#200000#, 16#1000000#, 16#2000000#, 16#4000000#, 16#7FFFFF8#);
    type t_expected is array (0 to BASES'length * 4 - 1) of unsigned(15 downto 0);
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_sdram
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            o_initialized => s_initialized,
            iu3_requests => su3_requests,
            ou3_ready => su3_ready,
            iu3_writes => su3_writes,
            iu27_byte_addresses => su27_addresses,
            iu16_write_data => su16_data,
            iu2_byte_enables => su2_bytes,
            ou3_response_valid => su3_valid,
            ou64_read_data => su64_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_chip,
            o_sdram_write_n => s_write_n,
            o_sdram_row_n => s_row_n,
            o_sdram_column_n => s_column_n,
            o_sdram_clock_enable => s_cke
        );
    chip : sdram_chip_model_wide
        port map (
            clk => s_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_chip,
            SDRAM_nWE => s_write_n,
            SDRAM_nRAS => s_row_n,
            SDRAM_nCAS => s_column_n
        );

    -- The donor alternates refresh commands between the two physical chips.
    -- A 375-cycle gap at 48 MHz is the 7.8125 us nominal limit, per chip.
    process(s_clk)
        type t_counts is array (0 to 1) of natural;
        variable vint_last : t_counts := (others => 0);
        variable vint_cycle, vint_chip, vint_gap : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            vint_cycle := vint_cycle + 1;
            if (s_initialized = '1' and s_row_n = '0' and s_column_n = '0' and s_write_n = '1') then
                vint_chip := 0;
                if (s_chip = '1') then
                    vint_chip := 1;
                end if;
                if (vint_last(vint_chip) /= 0) then
                    vint_gap := vint_cycle - vint_last(vint_chip);
                    assert (vint_gap <= 375) report "Refresh interval exceeded under traffic" severity failure;
                    if (vint_gap > sint_max_refresh_gap) then
                        sint_max_refresh_gap <= vint_gap;
                    end if;
                end if;
                vint_last(vint_chip) := vint_cycle;
                sint_refreshes <= sint_refreshes + 1;
            end if;
        end if;
    end process;

    process
        variable vu16_expected : t_expected;
        variable vu64_expected, vu64_saved : unsigned(63 downto 0);
        variable vu64_captured : t_sdram_read_data;
        variable vu3_seen : unsigned(2 downto 0);
        variable vint_checks, vint_transactions : natural := 0;
        variable vint_base, vint_client : natural;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure transact(
            constant vint_port : natural;
            constant vint_address : natural;
            constant v_write : std_logic;
            constant vu16_value : unsigned(15 downto 0);
            constant vu2_bytes : unsigned(1 downto 0);
            variable vu64_result : out unsigned(63 downto 0)) is
            variable v_done : boolean := false;
        begin
            assert (su3_ready(vint_port) = '1') report "Test issued request to busy port" severity failure;
            su27_addresses(vint_port) <= to_unsigned(vint_address, 27);
            su16_data(vint_port) <= vu16_value;
            su2_bytes(vint_port) <= vu2_bytes;
            su3_writes(vint_port) <= v_write;
            su3_requests(vint_port) <= '1';
            tick;
            su3_requests(vint_port) <= '0';
            -- The accepted transaction must not depend on subsequently changed pins.
            su27_addresses(vint_port) <= (others => '1');
            su16_data(vint_port) <= not vu16_value;
            for vint_wait in 0 to 300 loop
                tick;
                if (su3_valid(vint_port) = '1') then
                    vu64_result := su64_data(vint_port);
                    v_done := true;
                    exit;
                end if;
            end loop;
            assert (v_done) report "SDRAM transaction stalled" severity failure;
            vint_transactions := vint_transactions + 1;
            tick;
            assert (su3_valid(vint_port) = '0') report "Duplicate SDRAM response" severity failure;
        end procedure;
    begin
        for vint_wait in 0 to 4 loop
            tick;
        end loop;
        s_initialize <= '0';
        while (s_initialized /= '1') loop
            assert (su3_ready = "000") report "Client ready before initialization" severity failure;
            tick;
        end loop;
        for vint_group in BASES'range loop
            for vint_word in 0 to 3 loop
                vu16_expected(vint_group * 4 + vint_word) := to_unsigned(16#8100# + vint_group * 32 + vint_word * 7, 16);
                transact((vint_group + vint_word) mod 3, BASES(vint_group) + vint_word * 2,
                    '1', vu16_expected(vint_group * 4 + vint_word), "11", vu64_saved);
            end loop;
        end loop;
        -- Single writes must mask all following burst beats on every port. Adjacent words
        -- initialized above catch accidental modification of any of those beats.
        for vint_group in BASES'range loop
            transact(vint_group mod 3, BASES(vint_group) + 2, '1', x"003C", "01", vu64_saved);
            transact((vint_group + 1) mod 3, BASES(vint_group) + 2, '1', x"C700", "10", vu64_saved);
            vu16_expected(vint_group * 4 + 1) := x"C73C";
        end loop;
        for vint_round in 0 to 29 loop
            for vint_port in 0 to 2 loop
                vint_base := (vint_round + vint_port * 3) mod BASES'length;
                su27_addresses(vint_port) <= to_unsigned(BASES(vint_base), 27);
                su3_writes(vint_port) <= '0';
            end loop;
            su3_requests <= "111";
            tick;
            su3_requests <= "000";
            su27_addresses <= (others => (others => '1'));
            vu3_seen := "000";
            for vint_wait in 0 to 300 loop
                tick;
                for vint_port in 0 to 2 loop
                    if (vu3_seen(vint_port) = '1') then
                        assert (su64_data(vint_port) = vu64_captured(vint_port)) report "Other client overwrote captured response" severity failure;
                    end if;
                    if (su3_valid(vint_port) = '1') then
                        assert (vu3_seen(vint_port) = '0') report "Repeated response during contention" severity failure;
                        vint_base := (vint_round + vint_port * 3) mod BASES'length;
                        for vint_word in 0 to 3 loop
                            vu64_expected(vint_word * 16 + 15 downto vint_word * 16) := vu16_expected(vint_base * 4 + vint_word);
                        end loop;
                        assert (su64_data(vint_port) = vu64_expected)
                            report "Burst data/address/byte lane mismatch, port " & integer'image(vint_port) &
                                " base " & integer'image(BASES(vint_base)) & " got " & to_hstring(su64_data(vint_port)) &
                                " expected " & to_hstring(vu64_expected) severity failure;
                        vu64_captured(vint_port) := su64_data(vint_port);
                        vu3_seen(vint_port) := '1';
                        vint_checks := vint_checks + 4;
                    end if;
                end loop;
                exit when vu3_seen = "111";
            end loop;
            assert (vu3_seen = "111") report "Lost simultaneous request" severity failure;
            tick;
        end loop;
        vu64_saved := su64_data(0);
        for vint_wait in 0 to 2500 loop
            tick;
            assert (su3_valid = "000") report "Idle duplicate response" severity failure;
            assert (su64_data(0) = vu64_saved) report "Captured response changed while idle" severity failure;
        end loop;
        assert (sint_refreshes > 20) report "Missing refresh command coverage" severity failure;
        report "SDRAM_PASS checked_words=" & integer'image(vint_checks) &
            " writes=" & integer'image(vint_transactions) &
            " refresh_commands=" & integer'image(sint_refreshes) &
            " max_refresh_gap=" & integer'image(sint_max_refresh_gap);
        finish;
        wait;
    end process;
    process
    begin
        wait for 2 ms;
        assert false report "SDRAM test timeout" severity failure;
    end process;
end architecture;

