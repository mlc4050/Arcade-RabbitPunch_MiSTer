library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

-- Audio caches and a main-CPU burst client share one external read backend.
-- Image invalidation requires all clients and the external backend drained.
entity rabbitpunch_audio_rom_transport is
    port (
        i_clk : in std_logic;
        i_invalidate : in std_logic;
        o_idle : out std_logic;
        i_program_request : in std_logic;
        o_program_ready : out std_logic;
        iu16_program_address : in unsigned(15 downto 0);
        o_program_response_valid : out std_logic;
        ou8_program_data : out unsigned(7 downto 0);
        i_sample_request : in std_logic;
        iu18_sample_address : in unsigned(17 downto 0);
        o_sample_valid : out std_logic;
        ou8_sample_data : out unsigned(7 downto 0);
        i_main_request : in std_logic;
        o_main_ready : out std_logic;
        iu27_main_byte_address : in unsigned(26 downto 0);
        o_main_response_valid : out std_logic;
        ou64_main_read_data : out unsigned(63 downto 0);
        o_backend_request : out std_logic;
        ou27_backend_byte_address : out unsigned(26 downto 0);
        i_backend_ready : in std_logic;
        i_backend_response_valid : in std_logic;
        iu64_backend_read_data : in unsigned(63 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_audio_rom_transport is
    signal s_front_idle, s_queue_idle : std_logic;
    signal su3_cache_requests, su3_cache_ready, su3_cache_valid : unsigned(2 downto 0);
    signal su27_cache_addresses : t_sdram_addresses;
    signal su64_cache_data : t_sdram_read_data;
    signal su3_queue_requests, su3_queue_ready, su3_queue_valid : unsigned(2 downto 0);
    signal su27_queue_addresses : t_sdram_addresses;
    signal su64_queue_data : t_sdram_read_data;
begin
    o_idle <= s_front_idle and s_queue_idle;
    su3_queue_requests(0) <= i_main_request;
    su3_queue_requests(1) <= su3_cache_requests(0);
    su3_queue_requests(2) <= su3_cache_requests(1);
    su27_queue_addresses(0) <= iu27_main_byte_address;
    su27_queue_addresses(1) <= su27_cache_addresses(0);
    su27_queue_addresses(2) <= su27_cache_addresses(1);
    o_main_ready <= su3_queue_ready(0);
    o_main_response_valid <= su3_queue_valid(0);
    ou64_main_read_data <= su64_queue_data(0);
    su3_cache_ready <= '0' & su3_queue_ready(2 downto 1);
    su3_cache_valid <= '0' & su3_queue_valid(2 downto 1);
    su64_cache_data(0) <= su64_queue_data(1);
    su64_cache_data(1) <= su64_queue_data(2);
    su64_cache_data(2) <= (others => '0');
    frontends : entity work.rabbitpunch_audio_roms
        port map (
            i_clk => i_clk,
            i_invalidate => i_invalidate,
            o_idle => s_front_idle,
            i_program_request => i_program_request,
            o_program_ready => o_program_ready,
            iu16_program_address => iu16_program_address,
            o_program_response_valid => o_program_response_valid,
            ou8_program_data => ou8_program_data,
            i_sample_request => i_sample_request,
            iu18_sample_address => iu18_sample_address,
            o_sample_valid => o_sample_valid,
            ou8_sample_data => ou8_sample_data,
            ou3_backend_requests => su3_cache_requests,
            iu3_backend_ready => su3_cache_ready,
            ou27_backend_byte_addresses => su27_cache_addresses,
            iu3_backend_response_valid => su3_cache_valid,
            iu64_backend_read_data => su64_cache_data
        );
    queue : entity work.rabbitpunch_read_arbiter
        port map (
            i_clk => i_clk,
            i_enable => not i_invalidate,
            o_idle => s_queue_idle,
            iu3_requests => su3_queue_requests,
            ou3_ready => su3_queue_ready,
            iu27_byte_addresses => su27_queue_addresses,
            ou3_response_valid => su3_queue_valid,
            ou64_read_data => su64_queue_data,
            o_backend_request => o_backend_request,
            ou27_backend_byte_address => ou27_backend_byte_address,
            i_backend_ready => i_backend_ready,
            i_backend_response_valid => i_backend_response_valid,
            iu64_backend_read_data => iu64_backend_read_data
        );
end architecture;
