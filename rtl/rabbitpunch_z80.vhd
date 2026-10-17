library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Active-high board interface around the unchanged synchronous T80se.
-- CLKEN advances the CPU on i_clk. Vendor vector conversions stay here.
entity rabbitpunch_z80 is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_wait : in std_logic;
        i_interrupt : in std_logic;
        i_non_maskable_interrupt : in std_logic;
        i_bus_request : in std_logic;
        iu8_read_data : in unsigned(7 downto 0);
        ou16_address : out unsigned(15 downto 0);
        ou8_write_data : out unsigned(7 downto 0);
        o_opcode_fetch : out std_logic;
        o_memory_request : out std_logic;
        o_io_request : out std_logic;
        o_read : out std_logic;
        o_write : out std_logic;
        o_refresh : out std_logic;
        o_halted : out std_logic;
        o_bus_grant : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_z80 is
    subtype t_address is unsigned(15 downto 0);
    subtype t_data is unsigned(7 downto 0);
    signal s_opcode_n, s_memory_n, s_io_n, s_read_n, s_write_n, s_refresh_n, s_halted_n, s_bus_grant_n : std_logic;
begin
    o_opcode_fetch <= not s_opcode_n;
    o_memory_request <= not s_memory_n;
    o_io_request <= not s_io_n;
    o_read <= not s_read_n;
    o_write <= not s_write_n;
    o_refresh <= not s_refresh_n;
    o_halted <= not s_halted_n;
    o_bus_grant <= not s_bus_grant_n;
    cpu : entity work.T80se
        generic map (
            Mode => 0,
            T2Write => 0,
            IOWait => 1
        )
        port map (
            RESET_n => not i_reset,
            CLK_n => i_clk,
            CLKEN => i_enable,
            WAIT_n => not i_wait,
            INT_n => not i_interrupt,
            NMI_n => not i_non_maskable_interrupt,
            BUSRQ_n => not i_bus_request,
            M1_n => s_opcode_n,
            MREQ_n => s_memory_n,
            IORQ_n => s_io_n,
            RD_n => s_read_n,
            WR_n => s_write_n,
            RFSH_n => s_refresh_n,
            HALT_n => s_halted_n,
            BUSAK_n => s_bus_grant_n,
            t_address(A) => ou16_address,
            DI => std_logic_vector(iu8_read_data),
            t_data(DO) => ou8_write_data
        );
end architecture;
