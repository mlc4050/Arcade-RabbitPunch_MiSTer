library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

-- One read-only eight-byte entry per client. This stores fetched ROM bytes,
-- never rendered pixels. Invalidate only after all requesters are drained,
-- before changing the downloaded ROM image. Game reset need not invalidate.
entity rabbitpunch_rom_cache is
    port (
        i_clk : in std_logic;
        i_invalidate : in std_logic;
        o_idle : out std_logic;
        iu3_requests : in unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        iu27_byte_addresses : in t_sdram_addresses;
        ou3_response_valid : out unsigned(2 downto 0);
        ou64_read_data : out t_sdram_read_data;
        ou3_backend_requests : out unsigned(2 downto 0);
        iu3_backend_ready : in unsigned(2 downto 0);
        ou27_backend_byte_addresses : out t_sdram_addresses;
        iu3_backend_response_valid : in unsigned(2 downto 0);
        iu64_backend_read_data : in t_sdram_read_data
    );
end entity;

architecture rtl of rabbitpunch_rom_cache is
    type t_state is (STATE_IDLE, STATE_REQUEST, STATE_RESPONSE);
    type t_states is array (0 to 2) of t_state;
    signal styp_states : t_states := (others => STATE_IDLE);
    signal su3_cache_valid, su3_busy : unsigned(2 downto 0) := "000";
    signal su27_tags, su27_requested_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su64_cache_data : t_sdram_read_data;
begin
    o_idle <= '1' when su3_busy = "000" else '0';
    ou27_backend_byte_addresses <= su27_requested_addresses;
    clients : for gint_client in 0 to 2 generate
        su3_busy(gint_client) <= '0' when styp_states(gint_client) = STATE_IDLE else '1';
        ou3_ready(gint_client) <= '1' when styp_states(gint_client) = STATE_IDLE and i_invalidate = '0' else '0';
        ou3_backend_requests(gint_client) <= '1' when styp_states(gint_client) = STATE_REQUEST and
            iu3_backend_ready(gint_client) = '1' else '0';
    end generate;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            ou3_response_valid <= "000";
            if (i_invalidate = '1') then
                assert (su3_busy = "000") report "ROM cache must drain before invalidation" severity failure;
                assert (iu3_requests = "000") report "ROM cache requested during invalidation" severity failure;
                su3_cache_valid <= "000";
            else
                for vint_client in 0 to 2 loop
                    assert (iu3_requests(vint_client) = '0' or styp_states(vint_client) = STATE_IDLE)
                        report "ROM cache request while busy" severity failure;
                    if (iu3_backend_response_valid(vint_client) = '1') then
                        assert (styp_states(vint_client) = STATE_RESPONSE) report "Unexpected ROM cache backend reply" severity failure;
                    end if;
                    case styp_states(vint_client) is
                        when STATE_IDLE =>
                            if (iu3_requests(vint_client) = '1') then
                                assert (iu27_byte_addresses(vint_client)(2 downto 0) = "000") report "ROM cache requires aligned bursts" severity failure;
                                if (su3_cache_valid(vint_client) = '1' and su27_tags(vint_client) = iu27_byte_addresses(vint_client)) then
                                    ou64_read_data(vint_client) <= su64_cache_data(vint_client);
                                    ou3_response_valid(vint_client) <= '1';
                                else
                                    su27_requested_addresses(vint_client) <= iu27_byte_addresses(vint_client);
                                    styp_states(vint_client) <= STATE_REQUEST;
                                end if;
                            end if;
                        when STATE_REQUEST =>
                            if (iu3_backend_ready(vint_client) = '1') then
                                styp_states(vint_client) <= STATE_RESPONSE;
                            end if;
                        when STATE_RESPONSE =>
                            if (iu3_backend_response_valid(vint_client) = '1') then
                                su27_tags(vint_client) <= su27_requested_addresses(vint_client);
                                su64_cache_data(vint_client) <= iu64_backend_read_data(vint_client);
                                su3_cache_valid(vint_client) <= '1';
                                ou64_read_data(vint_client) <= iu64_backend_read_data(vint_client);
                                ou3_response_valid(vint_client) <= '1';
                                styp_states(vint_client) <= STATE_IDLE;
                            end if;
                    end case;
                end loop;
            end if;
        end if;
    end process;
end architecture;
