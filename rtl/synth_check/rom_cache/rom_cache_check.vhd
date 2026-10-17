library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

entity rom_cache_check is
    port (
        i_clk : in std_logic;
        i_invalidate : in std_logic;
        o_idle : out std_logic;
        iu3_requests : in unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        iu81_byte_addresses : in unsigned(80 downto 0);
        ou3_response_valid : out unsigned(2 downto 0);
        ou192_read_data : out unsigned(191 downto 0);
        ou3_backend_requests : out unsigned(2 downto 0);
        iu3_backend_ready : in unsigned(2 downto 0);
        ou81_backend_byte_addresses : out unsigned(80 downto 0);
        iu3_backend_response_valid : in unsigned(2 downto 0);
        iu192_backend_read_data : in unsigned(191 downto 0)
    );
end entity;

architecture evaluation of rom_cache_check is
    signal su27_iu27_byte_addresses : t_sdram_addresses;
    signal su64_ou64_read_data : t_sdram_read_data;
    signal su27_ou27_backend_byte_addresses : t_sdram_addresses;
    signal su64_iu64_backend_read_data : t_sdram_read_data;
begin
    su27_iu27_byte_addresses(0) <= iu81_byte_addresses(26 downto 0);
    su27_iu27_byte_addresses(1) <= iu81_byte_addresses(53 downto 27);
    su27_iu27_byte_addresses(2) <= iu81_byte_addresses(80 downto 54);
    ou192_read_data(63 downto 0) <= su64_ou64_read_data(0);
    ou192_read_data(127 downto 64) <= su64_ou64_read_data(1);
    ou192_read_data(191 downto 128) <= su64_ou64_read_data(2);
    ou81_backend_byte_addresses(26 downto 0) <= su27_ou27_backend_byte_addresses(0);
    ou81_backend_byte_addresses(53 downto 27) <= su27_ou27_backend_byte_addresses(1);
    ou81_backend_byte_addresses(80 downto 54) <= su27_ou27_backend_byte_addresses(2);
    su64_iu64_backend_read_data(0) <= iu192_backend_read_data(63 downto 0);
    su64_iu64_backend_read_data(1) <= iu192_backend_read_data(127 downto 64);
    su64_iu64_backend_read_data(2) <= iu192_backend_read_data(191 downto 128);
    cache : entity work.rabbitpunch_rom_cache
        port map (
            i_clk => i_clk,
            i_invalidate => i_invalidate,
            o_idle => o_idle,
            iu3_requests => iu3_requests,
            ou3_ready => ou3_ready,
            iu27_byte_addresses => su27_iu27_byte_addresses,
            ou3_response_valid => ou3_response_valid,
            ou64_read_data => su64_ou64_read_data,
            ou3_backend_requests => ou3_backend_requests,
            iu3_backend_ready => iu3_backend_ready,
            ou27_backend_byte_addresses => su27_ou27_backend_byte_addresses,
            iu3_backend_response_valid => iu3_backend_response_valid,
            iu64_backend_read_data => su64_iu64_backend_read_data
        );
end architecture;
