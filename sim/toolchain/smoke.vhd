library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity smoke_register is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        iu8_data : in unsigned(7 downto 0);
        ou8_data : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of smoke_register is
begin
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_reset = '1' then
                ou8_data <= (others => '0');
            elsif i_enable = '1' then
                ou8_data <= iu8_data;
            end if;
        end if;
    end process;
end architecture;
