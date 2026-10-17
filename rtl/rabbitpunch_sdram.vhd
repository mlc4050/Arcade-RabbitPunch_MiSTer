library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

-- One pulse per accepted request, one outstanding request per client. Addresses
-- are bytes; burst reads must start on an eight-byte boundary. Read lane 0 is
-- the lowest-addressed 16-bit word. The controller serves client 0 before 1/2.
-- i_initialize is power-up/reinitialization only; never connect game reset.
-- The physical SDRAM clock is generated separately at the MiSTer top level.
entity rabbitpunch_sdram is
    generic (
        GINT_READ_CAPTURE_ADJUST : natural range 0 to 2 := 0;
        GINT_REFRESH_INTERVAL_CYCLES : positive := 160;
        GINT_POWERUP_WAIT_CYCLES : positive := 6000;
        GINT_INITIALIZE_WAIT_CYCLES : positive := 1024
    );
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        o_initialized : out std_logic;
        iu3_requests : in unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        iu3_writes : in unsigned(2 downto 0);
        iu27_byte_addresses : in t_sdram_addresses;
        iu16_write_data : in t_sdram_write_data;
        iu2_byte_enables : in t_sdram_byte_enables;
        ou3_response_valid : out unsigned(2 downto 0);
        ou64_read_data : out t_sdram_read_data;
        iou16_sdram_data : inout unsigned(15 downto 0);
        ou13_sdram_address : out unsigned(12 downto 0);
        ou2_sdram_bank : out unsigned(1 downto 0);
        ou2_sdram_byte_mask : out unsigned(1 downto 0);
        o_sdram_chip_select : out std_logic;
        o_sdram_write_n : out std_logic;
        o_sdram_row_n : out std_logic;
        o_sdram_column_n : out std_logic;
        o_sdram_clock_enable : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_sdram is
    component sdram is
        generic (RFS_INTERVAL : unsigned(9 downto 0) := to_unsigned(335, 10));
        port (
            SDRAM_DQ : inout unsigned(15 downto 0);
            SDRAM_A : out unsigned(12 downto 0);
            SDRAM_DQML : out std_logic;
            SDRAM_DQMH : out std_logic;
            SDRAM_BA : out unsigned(1 downto 0);
            SDRAM_nCS : out std_logic;
            SDRAM_nWE : out std_logic;
            SDRAM_nRAS : out std_logic;
            SDRAM_nCAS : out std_logic;
            SDRAM_CLK : out std_logic;
            SDRAM_CKE : out std_logic;
            init : in std_logic;
            rd_adj : in unsigned(1 downto 0);
            clk : in std_logic;
            addr0 : in unsigned(26 downto 1);
            wrl0, wrh0 : in std_logic;
            din0 : in unsigned(15 downto 0);
            dout0 : out unsigned(63 downto 0);
            req0 : in std_logic;
            ack0 : out std_logic;
            dbl0 : in std_logic;
            dout0b : out unsigned(63 downto 0);
            addr1 : in unsigned(26 downto 1);
            wrl1, wrh1 : in std_logic;
            din1 : in unsigned(15 downto 0);
            dout1 : out unsigned(63 downto 0);
            req1 : in std_logic;
            ack1 : out std_logic;
            dbl1 : in std_logic;
            dout1b : out unsigned(63 downto 0);
            addr2 : in unsigned(26 downto 1);
            wrl2, wrh2 : in std_logic;
            din2 : in unsigned(15 downto 0);
            dout2 : out unsigned(63 downto 0);
            req2 : in std_logic;
            ack2 : out std_logic;
            dbl2 : in std_logic;
            dout2b : out unsigned(63 downto 0);
            din2x : in unsigned(47 downto 0);
            wrx2 : in unsigned(5 downto 0)
        );
    end component;
    type t_state is (STATE_POWER_WAIT, STATE_INITIALIZE_WAIT, STATE_RUNNING);
    signal styp_state : t_state := STATE_POWER_WAIT;
    signal sint_wait : natural range 0 to GINT_POWERUP_WAIT_CYCLES + GINT_INITIALIZE_WAIT_CYCLES := 0;
    signal su2_read_capture_adjust : unsigned(1 downto 0);
    signal s_vendor_initialize : std_logic := '1';
    signal su3_pending, su3_request_toggle, su3_acknowledge : unsigned(2 downto 0) := (others => '0');
    signal su3_write_low, su3_write_high : unsigned(2 downto 0) := (others => '0');
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su16_write_data : t_sdram_write_data := (others => (others => '0'));
    signal su64_read_data : t_sdram_read_data;
begin
    -- rd_adj also changes the donor's state-wrap point. Initialization counts
    -- the unadjusted final state, so only runtime reads may select another edge.
    su2_read_capture_adjust <= to_unsigned(GINT_READ_CAPTURE_ADJUST, 2)
        when styp_state = STATE_RUNNING and i_initialize = '0' else "00";
    assert (GINT_REFRESH_INTERVAL_CYCLES <= 1023) report "Refresh interval exceeds donor counter" severity failure;
    o_initialized <= '1' when styp_state = STATE_RUNNING and i_initialize = '0' else '0';
    ou3_ready <= not su3_pending when styp_state = STATE_RUNNING and i_initialize = '0' else "000";

    memory_controller : sdram
        generic map (
            RFS_INTERVAL => to_unsigned(GINT_REFRESH_INTERVAL_CYCLES, 10)
        )
        port map (
            SDRAM_DQ => iou16_sdram_data,
            SDRAM_A => ou13_sdram_address,
            SDRAM_DQML => ou2_sdram_byte_mask(0),
            SDRAM_DQMH => ou2_sdram_byte_mask(1),
            SDRAM_BA => ou2_sdram_bank,
            SDRAM_nCS => o_sdram_chip_select,
            SDRAM_nWE => o_sdram_write_n,
            SDRAM_nRAS => o_sdram_row_n,
            SDRAM_nCAS => o_sdram_column_n,
            SDRAM_CLK => open,
            SDRAM_CKE => o_sdram_clock_enable,
            init => s_vendor_initialize,
            rd_adj => su2_read_capture_adjust,
            clk => i_clk,
            addr0 => su27_addresses(0)(26 downto 1),
            wrl0 => su3_write_low(0),
            wrh0 => su3_write_high(0),
            din0 => su16_write_data(0),
            dout0 => su64_read_data(0),
            req0 => su3_request_toggle(0),
            ack0 => su3_acknowledge(0),
            dbl0 => '0',
            dout0b => open,
            addr1 => su27_addresses(1)(26 downto 1),
            wrl1 => su3_write_low(1),
            wrh1 => su3_write_high(1),
            din1 => su16_write_data(1),
            dout1 => su64_read_data(1),
            req1 => su3_request_toggle(1),
            ack1 => su3_acknowledge(1),
            dbl1 => '0',
            dout1b => open,
            addr2 => su27_addresses(2)(26 downto 1),
            wrl2 => su3_write_low(2),
            wrh2 => su3_write_high(2),
            din2 => su16_write_data(2),
            dout2 => su64_read_data(2),
            req2 => su3_request_toggle(2),
            ack2 => su3_acknowledge(2),
            dbl2 => '0',
            dout2b => open,
            din2x => (others => '0'),
            wrx2 => (others => '0')
        );

    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            ou3_response_valid <= (others => '0');
            if (i_initialize = '1') then
                assert (su3_pending = "000") report "Reinitialization must drain requests first" severity failure;
                styp_state <= STATE_POWER_WAIT;
                sint_wait <= 0;
                s_vendor_initialize <= '1';
            else
                case styp_state is
                    when STATE_POWER_WAIT =>
                        if (sint_wait = GINT_POWERUP_WAIT_CYCLES - 1) then
                            sint_wait <= 0;
                            s_vendor_initialize <= '0';
                            styp_state <= STATE_INITIALIZE_WAIT;
                        else
                            sint_wait <= sint_wait + 1;
                        end if;
                    when STATE_INITIALIZE_WAIT =>
                        if (sint_wait = GINT_INITIALIZE_WAIT_CYCLES - 1) then
                            styp_state <= STATE_RUNNING;
                            sint_wait <= 0;
                        else
                            sint_wait <= sint_wait + 1;
                        end if;
                    when STATE_RUNNING =>
                        null;
                end case;
            end if;
            for vint_client in 0 to 2 loop
                if (su3_pending(vint_client) = '1') then
                    assert (iu3_requests(vint_client) = '0') report "Client requested while not ready" severity failure;
                    if (su3_acknowledge(vint_client) = su3_request_toggle(vint_client)) then
                        -- All vendor ports share one data register: capture now.
                        ou64_read_data(vint_client) <= su64_read_data(vint_client);
                        ou3_response_valid(vint_client) <= '1';
                        su3_pending(vint_client) <= '0';
                    end if;
                elsif (iu3_requests(vint_client) = '1' and styp_state = STATE_RUNNING and i_initialize = '0') then
                    assert (iu27_byte_addresses(vint_client)(0) = '0') report "Unaligned SDRAM word write" severity failure;
                    if (iu3_writes(vint_client) = '0') then
                        assert (iu27_byte_addresses(vint_client)(2 downto 0) = "000") report "Unaligned SDRAM burst read" severity failure;
                    end if;
                    su27_addresses(vint_client) <= iu27_byte_addresses(vint_client);
                    su16_write_data(vint_client) <= iu16_write_data(vint_client);
                    su3_write_low(vint_client) <= iu3_writes(vint_client) and iu2_byte_enables(vint_client)(0);
                    su3_write_high(vint_client) <= iu3_writes(vint_client) and iu2_byte_enables(vint_client)(1);
                    su3_request_toggle(vint_client) <= not su3_request_toggle(vint_client);
                    su3_pending(vint_client) <= '1';
                end if;
            end loop;
        end if;
    end process;
end architecture;

