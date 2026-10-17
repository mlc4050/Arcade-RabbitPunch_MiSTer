library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

-- Audio caches and a main-CPU burst client share one external read backend.
-- Image invalidation requires all clients and the external backend drained.
entity audio_rom_transport_check is
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


architecture evaluation of audio_rom_transport_check is
    signal s_boundary_i_invalidate : std_logic;
    signal s_boundary_o_idle : std_logic;
    signal s_boundary_i_program_request : std_logic;
    signal s_boundary_o_program_ready : std_logic;
    signal su16_boundary_iu16_program_address : unsigned(15 downto 0);
    signal s_boundary_o_program_response_valid : std_logic;
    signal su8_boundary_ou8_program_data : unsigned(7 downto 0);
    signal s_boundary_i_sample_request : std_logic;
    signal su18_boundary_iu18_sample_address : unsigned(17 downto 0);
    signal s_boundary_o_sample_valid : std_logic;
    signal su8_boundary_ou8_sample_data : unsigned(7 downto 0);
    signal s_boundary_i_main_request : std_logic;
    signal s_boundary_o_main_ready : std_logic;
    signal su27_boundary_iu27_main_byte_address : unsigned(26 downto 0);
    signal s_boundary_o_main_response_valid : std_logic;
    signal su64_boundary_ou64_main_read_data : unsigned(63 downto 0);
    signal s_boundary_o_backend_request : std_logic;
    signal su27_boundary_ou27_backend_byte_address : unsigned(26 downto 0);
    signal s_boundary_i_backend_ready : std_logic;
    signal s_boundary_i_backend_response_valid : std_logic;
    signal su64_boundary_iu64_backend_read_data : unsigned(63 downto 0);
begin
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_invalidate <= i_invalidate;
            o_idle <= s_boundary_o_idle;
            s_boundary_i_program_request <= i_program_request;
            o_program_ready <= s_boundary_o_program_ready;
            su16_boundary_iu16_program_address <= iu16_program_address;
            o_program_response_valid <= s_boundary_o_program_response_valid;
            ou8_program_data <= su8_boundary_ou8_program_data;
            s_boundary_i_sample_request <= i_sample_request;
            su18_boundary_iu18_sample_address <= iu18_sample_address;
            o_sample_valid <= s_boundary_o_sample_valid;
            ou8_sample_data <= su8_boundary_ou8_sample_data;
            s_boundary_i_main_request <= i_main_request;
            o_main_ready <= s_boundary_o_main_ready;
            su27_boundary_iu27_main_byte_address <= iu27_main_byte_address;
            o_main_response_valid <= s_boundary_o_main_response_valid;
            ou64_main_read_data <= su64_boundary_ou64_main_read_data;
            o_backend_request <= s_boundary_o_backend_request;
            ou27_backend_byte_address <= su27_boundary_ou27_backend_byte_address;
            s_boundary_i_backend_ready <= i_backend_ready;
            s_boundary_i_backend_response_valid <= i_backend_response_valid;
            su64_boundary_iu64_backend_read_data <= iu64_backend_read_data;
        end if;
    end process;
    audio_rom_transport : entity work.rabbitpunch_audio_rom_transport
        port map (
            i_clk => i_clk,
            i_invalidate => s_boundary_i_invalidate,
            o_idle => s_boundary_o_idle,
            i_program_request => s_boundary_i_program_request,
            o_program_ready => s_boundary_o_program_ready,
            iu16_program_address => su16_boundary_iu16_program_address,
            o_program_response_valid => s_boundary_o_program_response_valid,
            ou8_program_data => su8_boundary_ou8_program_data,
            i_sample_request => s_boundary_i_sample_request,
            iu18_sample_address => su18_boundary_iu18_sample_address,
            o_sample_valid => s_boundary_o_sample_valid,
            ou8_sample_data => su8_boundary_ou8_sample_data,
            i_main_request => s_boundary_i_main_request,
            o_main_ready => s_boundary_o_main_ready,
            iu27_main_byte_address => su27_boundary_iu27_main_byte_address,
            o_main_response_valid => s_boundary_o_main_response_valid,
            ou64_main_read_data => su64_boundary_ou64_main_read_data,
            o_backend_request => s_boundary_o_backend_request,
            ou27_backend_byte_address => su27_boundary_ou27_backend_byte_address,
            i_backend_ready => s_boundary_i_backend_ready,
            i_backend_response_valid => s_boundary_i_backend_response_valid,
            iu64_backend_read_data => su64_boundary_iu64_backend_read_data
        );
end architecture;
