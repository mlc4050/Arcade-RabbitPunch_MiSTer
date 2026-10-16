library ieee;
use ieee.std_logic_1164.all;

entity smoke_register is
    port (clk, reset, enable : in std_logic;
          data_in : in std_logic_vector(7 downto 0);
          data_out : out std_logic_vector(7 downto 0));
end entity;

architecture rtl of smoke_register is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                data_out <= (others => '0');
            elsif enable = '1' then
                data_out <= data_in;
            end if;
        end if;
    end process;
end architecture;
