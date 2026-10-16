library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- CPU read/write port plus a read-only video/state inspection port, one clock.
-- RAM contents are deliberately not reset. CPU writes define each byte independently.
entity rabbitpunch_ram16 is
    generic (sint_ADDRESS_BITS : positive := 13);
    port (
        i_clk : in std_logic;
        i_cpu_enable : in std_logic;
        i_cpu_write : in std_logic;
        iux_cpu_address : in unsigned;
        iu2_cpu_bytes : in unsigned(1 downto 0);
        iu16_cpu_data : in unsigned(15 downto 0);
        ou16_cpu_data : out unsigned(15 downto 0);
        i_view_enable : in std_logic;
        iux_view_address : in unsigned;
        ou16_view_data : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_ram16 is
    type ram_t is array (0 to 2**sint_ADDRESS_BITS-1) of unsigned(15 downto 0);
    signal su16_memory : ram_t;
begin
    assert iux_cpu_address'length = sint_ADDRESS_BITS and iux_view_address'length = sint_ADDRESS_BITS
        report "RAM address ports must match sint_ADDRESS_BITS" severity failure;
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_cpu_enable = '1' then
                if i_cpu_write = '1' then
                    if iu2_cpu_bytes(1) = '1' then
                        su16_memory(to_integer(iux_cpu_address))(15 downto 8) <= iu16_cpu_data(15 downto 8);
                    end if;
                    if iu2_cpu_bytes(0) = '1' then
                        su16_memory(to_integer(iux_cpu_address))(7 downto 0) <= iu16_cpu_data(7 downto 0);
                    end if;
                else
                    ou16_cpu_data <= su16_memory(to_integer(iux_cpu_address));
                end if;
            end if;
            if i_view_enable = '1' then
                ou16_view_data <= su16_memory(to_integer(iux_view_address));
            end if;
        end if;
    end process;
end architecture;
