library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rabbitpunch_sdram_types is
    type t_sdram_addresses is array (0 to 2) of unsigned(26 downto 0);
    type t_sdram_write_data is array (0 to 2) of unsigned(15 downto 0);
    type t_sdram_byte_enables is array (0 to 2) of unsigned(1 downto 0);
    type t_sdram_read_data is array (0 to 2) of unsigned(63 downto 0);
end package;
