library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_sdram_types.all;

entity rom_cache_tb is
end entity;

architecture test of rom_cache_tb is
    component rom_cache_check is
        port (
            i_clk : in std_logic;
            i_invalidate : in std_logic;
            o_idle : out std_logic;
            iu3_requests : in unsigned(2 downto 0);
            ou3_ready : out unsigned(2 downto 0);
            iu81_byte_addresses : in unsigned(80 downto 0);
            ou3_response_valid : out unsigned(2 downto 0);
            ou192_read_data : out unsigned(191 downto 0);
            ou3_backend_requests : out unsigned(2 downto 0);
            iu3_backend_ready : in unsigned(2 downto 0);
            ou81_backend_byte_addresses : out unsigned(80 downto 0);
            iu3_backend_response_valid : in unsigned(2 downto 0);
            iu192_backend_read_data : in unsigned(191 downto 0)
        );
    end component;
    signal s_clk : std_logic := '0';
    signal s_invalidate : std_logic := '0';
    signal s_idle : std_logic;
    signal su3_requests : unsigned(2 downto 0) := "000";
    signal su3_ready, su3_valid, su3_backend_requests, su3_backend_ready : unsigned(2 downto 0);
    signal su3_backend_valid : unsigned(2 downto 0) := "000";
    signal su27_addresses, su27_backend_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su64_data, su64_backend_data : t_sdram_read_data;
    signal su81_backend_addresses : unsigned(80 downto 0);
    signal su192_data : unsigned(191 downto 0);
    signal sint_epoch, sint_fetches, sint_cycle : natural := 0;
    function read_value(vint_address, vint_epoch : natural) return unsigned is
        variable vu64_result : unsigned(63 downto 0);
    begin
        vu64_result := to_unsigned(vint_address, 64) xor x"0123456789ABCDEF";
        if (vint_epoch = 1) then
            vu64_result := not vu64_result;
        end if;
        return vu64_result;
    end function;
begin
    s_clk <= not s_clk after 10 ns;
    dut : rom_cache_check
        port map (
            i_clk => s_clk,
            i_invalidate => s_invalidate,
            o_idle => s_idle,
            iu3_requests => su3_requests,
            ou3_ready => su3_ready,
            iu81_byte_addresses => su27_addresses(2) & su27_addresses(1) & su27_addresses(0),
            ou3_response_valid => su3_valid,
            ou192_read_data => su192_data,
            ou3_backend_requests => su3_backend_requests,
            iu3_backend_ready => su3_backend_ready,
            ou81_backend_byte_addresses => su81_backend_addresses,
            iu3_backend_response_valid => su3_backend_valid,
            iu192_backend_read_data => su64_backend_data(2) & su64_backend_data(1) & su64_backend_data(0)
        );
    lanes : for gint_client in 0 to 2 generate
        su64_data(gint_client) <= su192_data(gint_client * 64 + 63 downto gint_client * 64);
        su27_backend_addresses(gint_client) <= su81_backend_addresses(gint_client * 27 + 26 downto gint_client * 27);
    end generate;
    su3_backend_ready(0) <= '1' when sint_cycle mod 7 < 3 else '0';
    su3_backend_ready(1) <= '1' when sint_cycle mod 11 < 2 else '0';
    su3_backend_ready(2) <= '1' when sint_cycle mod 5 < 2 else '0';
    process(s_clk)
        type t_counts is array (0 to 2) of natural;
        variable vint_delay : t_counts := (others => 0);
        variable vu3_pending : unsigned(2 downto 0) := "000";
        variable vu64_return : t_sdram_read_data;
        variable vint_fetches : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            sint_cycle <= sint_cycle + 1;
            su3_backend_valid <= "000";
            for vint_client in 0 to 2 loop
                if (vu3_pending(vint_client) = '1') then
                    if (vint_delay(vint_client) = 0) then
                        su64_backend_data(vint_client) <= vu64_return(vint_client);
                        su3_backend_valid(vint_client) <= '1';
                        vu3_pending(vint_client) := '0';
                    else
                        vint_delay(vint_client) := vint_delay(vint_client) - 1;
                    end if;
                elsif (su3_backend_requests(vint_client) = '1' and su3_backend_ready(vint_client) = '1') then
                    vint_delay(vint_client) := vint_client * 5;
                    vu64_return(vint_client) := read_value(to_integer(su27_backend_addresses(vint_client)), sint_epoch);
                    vu3_pending(vint_client) := '1';
                    vint_fetches := vint_fetches + 1;
                end if;
            end loop;
            sint_fetches <= vint_fetches;
        end if;
    end process;
    process
        variable vu3_seen : unsigned(2 downto 0);
        variable vu27_expected : t_sdram_addresses;
        variable vint_checks, vint_prior_fetches : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure read_all(vint_delta : natural; v_mixed : boolean := false) is
        begin
            assert (su3_ready = "111") report "Cache not idle before test request" severity failure;
            for vint_client in 0 to 2 loop
                vu27_expected(vint_client) := to_unsigned(16#50000# + vint_client * 16#80000# + vint_delta, 27);
                if (v_mixed and vint_client /= 0) then
                    vu27_expected(vint_client) := vu27_expected(vint_client) - 8;
                end if;
                su27_addresses(vint_client) <= vu27_expected(vint_client);
            end loop;
            su3_requests <= "111";
            tick;
            su3_requests <= "000";
            su27_addresses <= (others => (others => '1'));
            vu3_seen := "000";
            for vint_wait in 0 to 100 loop
                -- A hit can reply at the accepting edge, before another tick.
                for vint_client in 0 to 2 loop
                    if (su3_valid(vint_client) = '1') then
                        assert (vu3_seen(vint_client) = '0' and su64_data(vint_client) = read_value(to_integer(vu27_expected(vint_client)), sint_epoch))
                            report "Cache returned stale or wrong address data" severity failure;
                        vu3_seen(vint_client) := '1';
                        vint_checks := vint_checks + 1;
                    end if;
                end loop;
                exit when vu3_seen = "111";
                tick;
            end loop;
            assert (vu3_seen = "111" and s_idle = '1') report "Cache request lost" severity failure;
            tick;
        end procedure;
    begin
        tick;
        for vint_group in 0 to 15 loop
            vint_prior_fetches := sint_fetches;
            read_all(vint_group * 8);
            assert (sint_fetches = vint_prior_fetches + 3) report "Cache miss fetch count mismatch" severity failure;
            vint_prior_fetches := sint_fetches;
            for vint_hit in 0 to 7 loop
                read_all(vint_group * 8);
            end loop;
            assert (sint_fetches = vint_prior_fetches) report "Cache hit accessed SDRAM" severity failure;
        end loop;
        -- A slow miss on one port must coexist with hits on the other two.
        vint_prior_fetches := sint_fetches;
        read_all(16 * 8, true);
        assert (sint_fetches = vint_prior_fetches + 1) report "Mixed hit/miss isolation failed" severity failure;
        vint_prior_fetches := sint_fetches;
        read_all(16 * 8);
        assert (sint_fetches = vint_prior_fetches + 2) report "Independent cache tags aliased" severity failure;
        s_invalidate <= '1';
        sint_epoch <= 1;
        tick;
        s_invalidate <= '0';
        tick;
        vint_prior_fetches := sint_fetches;
        read_all(16 * 8);
        assert (sint_fetches = vint_prior_fetches + 3) report "Invalidation failed to refetch" severity failure;
        read_all(16 * 8);
        for vint_wait in 0 to 100 loop
            tick;
            assert (su3_valid = "000" and su3_backend_requests = "000") report "Cache emitted idle traffic" severity failure;
        end loop;
        report "ROM_CACHE_PASS replies=" & integer'image(vint_checks) & " backend_fetches=" & integer'image(sint_fetches);
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "ROM cache test timeout" severity failure;
    end process;
end architecture;
