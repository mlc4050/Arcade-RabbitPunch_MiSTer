library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Naming/type boundary around the unchanged Z80-mode T80se core.
-- All _n signals are active low. Vendor vector conversions stay at this boundary.
entity rabbitpunch_t80 is
    port (
        i_clk : in std_logic;
        i_reset_n : in std_logic;
        i_clock_enable : in std_logic;
        i_wait_n : in std_logic;
        i_interrupt_n : in std_logic;
        i_nonmaskable_interrupt_n : in std_logic;
        i_bus_request_n : in std_logic;
        o_opcode_fetch_n : out std_logic;
        o_memory_request_n : out std_logic;
        o_io_request_n : out std_logic;
        o_read_n : out std_logic;
        o_write_n : out std_logic;
        o_refresh_n : out std_logic;
        o_halted_n : out std_logic;
        o_bus_acknowledge_n : out std_logic;
        ou16_address : out unsigned(15 downto 0);
        iu8_read_data : in unsigned(7 downto 0);
        ou8_write_data : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_t80 is
    subtype address_t is unsigned(15 downto 0);
    subtype data_t is unsigned(7 downto 0);
begin
    cpu : entity work.T80se
        generic map (
            Mode => 0, -- Z80 instruction set.
            T2Write => 0, -- Assert writes in T3.
            IOWait => 1 -- Standard I/O cycle.
        )
        port map (
            CLK_n => i_clk, -- Vendor name notwithstanding, this is a rising-edge clock.
            RESET_n => i_reset_n,
            CLKEN => i_clock_enable,
            WAIT_n => i_wait_n,
            INT_n => i_interrupt_n,
            NMI_n => i_nonmaskable_interrupt_n,
            BUSRQ_n => i_bus_request_n,
            M1_n => o_opcode_fetch_n, -- Also asserted during interrupt acknowledge.
            MREQ_n => o_memory_request_n,
            IORQ_n => o_io_request_n,
            RD_n => o_read_n,
            WR_n => o_write_n,
            RFSH_n => o_refresh_n,
            HALT_n => o_halted_n,
            BUSAK_n => o_bus_acknowledge_n,
            address_t(A) => ou16_address,
            DI => std_logic_vector(iu8_read_data),
            data_t(DO) => ou8_write_data
        );
end architecture;
