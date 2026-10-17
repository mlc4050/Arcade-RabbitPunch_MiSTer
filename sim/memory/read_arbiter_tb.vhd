library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;
use std.env.all;

entity read_arbiter_tb is
end entity;

architecture test of read_arbiter_tb is
    function reply(vu27_address : unsigned(26 downto 0)) return unsigned is
    begin
        return resize(vu27_address, 64) xor x"ABCDEF0012345678";
    end function;
    signal s_clk : std_logic := '0';
    signal s_enable : std_logic := '1';
    signal s_idle, s_backend_request, s_backend_ready, s_backend_response : std_logic := '0';
    signal su3_requests : unsigned(2 downto 0) := "000";
    signal su3_ready, su3_valid : unsigned(2 downto 0);
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su27_backend_address : unsigned(26 downto 0);
    signal su64_data : t_sdram_read_data;
    signal su64_backend_data : unsigned(63 downto 0);
    signal sint_grants, sint_replies : natural := 0;
    signal sint_grant_offset : natural range 0 to 2 := 0;
    type t_counts is array (0 to 2) of natural;
    signal sint_client_replies : t_counts := (others => 0);
    signal s_check_round_robin : std_logic := '1';
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_read_arbiter
        port map (
            i_clk => s_clk,
            i_enable => s_enable,
            o_idle => s_idle,
            iu3_requests => su3_requests,
            ou3_ready => su3_ready,
            iu27_byte_addresses => su27_addresses,
            ou3_response_valid => su3_valid,
            ou64_read_data => su64_data,
            o_backend_request => s_backend_request,
            ou27_backend_byte_address => su27_backend_address,
            i_backend_ready => s_backend_ready,
            i_backend_response_valid => s_backend_response,
            iu64_backend_read_data => su64_backend_data
        );
    backend : process(s_clk)
        variable v_busy : boolean := false;
        variable vint_delay, vint_clock, vint_client : natural := 0;
        variable vu27_address : unsigned(26 downto 0);
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            s_backend_response <= '0';
            s_backend_ready <= '0';
            if (v_busy) then
                if (vint_delay = 0) then
                    s_backend_response <= '1';
                    su64_backend_data <= reply(vu27_address);
                    v_busy := false;
                else
                    vint_delay := vint_delay - 1;
                end if;
            elsif (vint_clock mod 7 >= 3) then
                s_backend_ready <= '1';
            end if;
            if (s_backend_request = '1') then
                assert (not v_busy and s_backend_ready = '1') report "Read arbiter backend overlap/backpressure failure" severity failure;
                vu27_address := su27_backend_address;
                vint_client := to_integer(vu27_address(5 downto 3));
                if (s_check_round_robin = '1') then
                    assert (vint_client = (sint_grants + sint_grant_offset) mod 3) report "Read arbiter lost round-robin fairness" severity failure;
                end if;
                sint_grants <= sint_grants + 1;
                vint_delay := 3 + (sint_grants mod 5) * 17;
                v_busy := true;
                s_backend_ready <= '0';
            end if;
        end if;
    end process;
    monitor : process(s_clk)
        variable v_expected : t_sdram_read_data;
        variable vu3_pending : unsigned(2 downto 0) := "000";
        variable vint_count : natural;
    begin
        if (rising_edge(s_clk)) then
            vint_count := 0;
            for vint_client in 0 to 2 loop
                if (su3_valid(vint_client) = '1') then
                    assert (vu3_pending(vint_client) = '1' and su64_data(vint_client) = v_expected(vint_client))
                        report "Read arbiter response data/ownership mismatch" severity failure;
                    vu3_pending(vint_client) := '0';
                    vint_count := vint_count + 1;
                    sint_client_replies(vint_client) <= sint_client_replies(vint_client) + 1;
                end if;
                if (su3_requests(vint_client) = '1') then
                    assert (su3_ready(vint_client) = '1' and vu3_pending(vint_client) = '0')
                        report "Read arbiter client issued without credit" severity failure;
                    vu3_pending(vint_client) := '1';
                    v_expected(vint_client) := reply(su27_addresses(vint_client));
                end if;
            end loop;
            assert (vint_count <= 1) report "Read arbiter duplicated a shared response" severity failure;
            sint_replies <= sint_replies + vint_count;
        end if;
    end process;
    stimulus : process
        variable v_turns : t_counts := (others => 0);
        procedure send_batch(constant vint_batch : natural; constant vu3_clients : unsigned(2 downto 0)) is
        begin
            wait until falling_edge(s_clk);
            for vint_client in 0 to 2 loop
                assert (vu3_clients(vint_client) = '0' or su3_ready(vint_client) = '1')
                    report "Read arbiter did not restore client ready" severity failure;
                su27_addresses(vint_client) <= to_unsigned(vint_batch * 64 + vint_client * 8, 27);
            end loop;
            su3_requests <= vu3_clients;
            wait until falling_edge(s_clk);
            su3_requests <= "000";
            su27_addresses <= (others => (others => '1'));
        end procedure;
    begin
        wait for 100 ns;
        for vint_batch in 0 to 39 loop
            send_batch(vint_batch, "111");
            wait until s_idle = '1' for 10 us;
            assert (s_idle = '1') report "Read arbiter failed to drain queued clients" severity failure;
            wait until falling_edge(s_clk);
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_grants = 120 and sint_replies = 120) report "Read arbiter lost simultaneous clients" severity failure;
        s_check_round_robin <= '0';
        send_batch(41, "101");
        s_enable <= '0';
        wait until falling_edge(s_clk);
        assert (su3_ready = "000") report "Read arbiter disable did not close acceptance" severity failure;
        wait until s_idle = '1' for 10 us;
        assert (s_idle = '1') report "Read arbiter disable canceled pending transactions" severity failure;
        wait until falling_edge(s_clk);
        s_enable <= '1';
        wait until falling_edge(s_clk);
        send_batch(42, "010");
        wait until s_idle = '1' for 10 us;
        wait until falling_edge(s_clk);
        wait until falling_edge(s_clk);
        assert (s_idle = '1' and sint_grants = 123 and sint_replies = 123)
            report "Read arbiter disable/re-enable recovery failed" severity failure;
        sint_grant_offset <= 2;
        s_check_round_robin <= '1';
        for vint_cycle in 1 to 10000 loop
            wait until falling_edge(s_clk);
            exit when sint_replies >= 183;
            su3_requests <= su3_ready;
            for vint_client in 0 to 2 loop
                su27_addresses(vint_client) <= to_unsigned((43 + v_turns(vint_client)) * 64 + vint_client * 8, 27);
                if (su3_ready(vint_client) = '1') then
                    v_turns(vint_client) := v_turns(vint_client) + 1;
                end if;
            end loop;
        end loop;
        su3_requests <= "000";
        s_check_round_robin <= '0';
        if (s_idle /= '1') then
            wait until s_idle = '1' for 10 us;
        end if;
        wait until falling_edge(s_clk);
        wait until falling_edge(s_clk);
        assert (s_idle = '1' and sint_replies >= 183 and sint_grants = sint_replies)
            report "Read arbiter continuous-credit traffic did not drain" severity failure;
        for vint_client in 0 to 2 loop
            assert (sint_client_replies(vint_client) >= 61)
                report "Read arbiter starved a continuously requesting client" severity failure;
        end loop;
        report "READ_ARBITER_PASS replies=" & integer'image(sint_replies) &
            " simultaneous_clients=3 fairness=checked continuous_credit=checked backpressure=checked disable_drain=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 500 us;
        assert false report "Read arbiter timeout" severity failure;
    end process;
end architecture;
