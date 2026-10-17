library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_sdram_types.all;

entity rom_requests_check is
    port (
        i_clk : in std_logic;
        i_sprite_request : in std_logic;
        iu17_sprite_word_address : in unsigned(16 downto 0);
        o_sprite_response_valid : out std_logic;
        ou32_sprite_response_data : out unsigned(31 downto 0);
        i_tile_request : in std_logic;
        iu17_tile_word_address : in unsigned(16 downto 0);
        i_tile_foreground : in std_logic;
        o_tile_response_valid : out std_logic;
        ou32_tile_response_data : out unsigned(31 downto 0);
        i_cpu_request : in std_logic;
        iu18_cpu_byte_address : in unsigned(17 downto 0);
        o_cpu_response_valid : out std_logic;
        ou16_cpu_response_data : out unsigned(15 downto 0);
        o_idle : out std_logic;
        ou3_backend_requests : out unsigned(2 downto 0);
        iu3_backend_ready : in unsigned(2 downto 0);
        ou81_backend_byte_addresses : out unsigned(80 downto 0);
        iu3_backend_response_valid : in unsigned(2 downto 0);
        iu192_backend_read_data : in unsigned(191 downto 0)
    );
end entity;

-- Wire-only flattening for isolated Quartus evaluation and functional netlists.
architecture evaluation of rom_requests_check is
    signal su27_addresses : t_sdram_addresses;
    signal su64_data : t_sdram_read_data;
begin
    ou81_backend_byte_addresses(26 downto 0) <= su27_addresses(0);
    su64_data(0) <= iu192_backend_read_data(63 downto 0);
    ou81_backend_byte_addresses(53 downto 27) <= su27_addresses(1);
    su64_data(1) <= iu192_backend_read_data(127 downto 64);
    ou81_backend_byte_addresses(80 downto 54) <= su27_addresses(2);
    su64_data(2) <= iu192_backend_read_data(191 downto 128);
    requests : entity work.rabbitpunch_rom_requests
        port map (
            i_clk => i_clk,
            i_sprite_request => i_sprite_request,
            iu17_sprite_word_address => iu17_sprite_word_address,
            o_sprite_response_valid => o_sprite_response_valid,
            ou32_sprite_response_data => ou32_sprite_response_data,
            i_tile_request => i_tile_request,
            iu17_tile_word_address => iu17_tile_word_address,
            i_tile_foreground => i_tile_foreground,
            o_tile_response_valid => o_tile_response_valid,
            ou32_tile_response_data => ou32_tile_response_data,
            i_cpu_request => i_cpu_request,
            iu18_cpu_byte_address => iu18_cpu_byte_address,
            o_cpu_response_valid => o_cpu_response_valid,
            ou16_cpu_response_data => ou16_cpu_response_data,
            o_idle => o_idle,
            ou3_backend_requests => ou3_backend_requests,
            iu3_backend_ready => iu3_backend_ready,
            ou27_backend_byte_addresses => su27_addresses,
            iu3_backend_response_valid => iu3_backend_response_valid,
            iu64_backend_read_data => su64_data
        );
end architecture;
