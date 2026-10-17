library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

-- Three independently queued read clients share one burst backend. Requests
-- pulse only when ready; one response is owed per accepted client request.
entity rabbitpunch_read_arbiter is
    port (
        i_clk : in std_logic;
        i_enable : in std_logic;
        o_idle : out std_logic;
        iu3_requests : in unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        iu27_byte_addresses : in t_sdram_addresses;
        ou3_response_valid : out unsigned(2 downto 0);
        ou64_read_data : out t_sdram_read_data;
        o_backend_request : out std_logic;
        ou27_backend_byte_address : out unsigned(26 downto 0);
        i_backend_ready : in std_logic;
        i_backend_response_valid : in std_logic;
        iu64_backend_read_data : in unsigned(63 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_read_arbiter is
    type t_state is (STATE_IDLE, STATE_WAITING);
    signal styp_state : t_state := STATE_IDLE;
    signal su3_pending : unsigned(2 downto 0) := "000";
    signal su27_addresses : t_sdram_addresses;
    signal sint_next, sint_selected, sint_owner : natural range 0 to 2 := 0;
    signal s_selected_valid, s_backend_request : std_logic;
begin
    ou3_ready <= not su3_pending when i_enable = '1' else "000";
    o_idle <= '1' when su3_pending = "000" and styp_state = STATE_IDLE else '0';
    s_backend_request <= '1' when styp_state = STATE_IDLE and s_selected_valid = '1' and i_backend_ready = '1' else '0';
    o_backend_request <= s_backend_request;
    ou27_backend_byte_address <= su27_addresses(sint_selected);
    select_client : process(all)
        variable vint_candidate : natural range 0 to 4;
        variable v_found : boolean;
    begin
        sint_selected <= sint_next;
        s_selected_valid <= '0';
        v_found := false;
        for vint_offset in 0 to 2 loop
            vint_candidate := sint_next + vint_offset;
            if (vint_candidate >= 3) then
                vint_candidate := vint_candidate - 3;
            end if;
            if (not v_found and su3_pending(vint_candidate) = '1') then
                sint_selected <= vint_candidate;
                s_selected_valid <= '1';
                v_found := true;
            end if;
        end loop;
    end process;
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            ou3_response_valid <= "000";
            for vint_client in 0 to 2 loop
                if (iu3_requests(vint_client) = '1') then
                    assert (su3_pending(vint_client) = '0' and i_enable = '1')
                        report "Read arbiter request without ready" severity failure;
                    assert (iu27_byte_addresses(vint_client)(2 downto 0) = "000")
                        report "Read arbiter requires aligned burst addresses" severity failure;
                    su3_pending(vint_client) <= '1';
                    su27_addresses(vint_client) <= iu27_byte_addresses(vint_client);
                end if;
            end loop;
            if (i_backend_response_valid = '1') then
                assert (styp_state = STATE_WAITING) report "Read arbiter unexpected backend response" severity failure;
            end if;
            case styp_state is
                when STATE_IDLE =>
                    if (s_backend_request = '1') then
                        sint_owner <= sint_selected;
                        styp_state <= STATE_WAITING;
                    end if;
                when STATE_WAITING =>
                    if (i_backend_response_valid = '1') then
                        ou64_read_data(sint_owner) <= iu64_backend_read_data;
                        ou3_response_valid(sint_owner) <= '1';
                        su3_pending(sint_owner) <= '0';
                        if (sint_owner = 2) then
                            sint_next <= 0;
                        else
                            sint_next <= sint_owner + 1;
                        end if;
                        styp_state <= STATE_IDLE;
                    end if;
            end case;
        end if;
    end process;
end architecture;
