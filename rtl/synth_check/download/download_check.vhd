library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity download_check is
    port (
        i_clk : in std_logic;
        i_download : in std_logic;
        i_word_valid : in std_logic;
        o_word_ready : out std_logic;
        iu27_word_byte_address : in unsigned(26 downto 0);
        iu16_word_data : in unsigned(15 downto 0);
        i_transport_idle : in std_logic;
        i_loader_ready : in std_logic;
        i_loader_response_valid : in std_logic;
        o_loading : out std_logic;
        o_loader_request : out std_logic;
        ou27_loader_byte_address : out unsigned(26 downto 0);
        ou16_loader_data : out unsigned(15 downto 0);
        ou2_loader_bytes : out unsigned(1 downto 0);
        o_game_reset : out std_logic;
        o_image_valid : out std_logic;
        o_error : out std_logic;
        o_done : out std_logic;
        ou27_bytes_loaded : out unsigned(26 downto 0)
    );
end entity;

-- Evaluation-only registered logical interfaces, one clock.
architecture evaluation of download_check is
    signal s_boundary_i_download : std_logic := '0';
    signal s_boundary_i_word_valid : std_logic := '0';
    signal s_boundary_o_word_ready : std_logic := '0';
    signal su27_boundary_iu27_word_byte_address : unsigned(26 downto 0) := (others => '0');
    signal su16_boundary_iu16_word_data : unsigned(15 downto 0) := (others => '0');
    signal s_boundary_i_transport_idle : std_logic := '0';
    signal s_boundary_i_loader_ready : std_logic := '0';
    signal s_boundary_i_loader_response_valid : std_logic := '0';
    signal s_boundary_o_loading : std_logic := '0';
    signal s_boundary_o_loader_request : std_logic := '0';
    signal su27_boundary_ou27_loader_byte_address : unsigned(26 downto 0) := (others => '0');
    signal su16_boundary_ou16_loader_data : unsigned(15 downto 0) := (others => '0');
    signal su2_boundary_ou2_loader_bytes : unsigned(1 downto 0) := (others => '0');
    signal s_boundary_o_game_reset : std_logic := '0';
    signal s_boundary_o_image_valid : std_logic := '0';
    signal s_boundary_o_error : std_logic := '0';
    signal s_boundary_o_done : std_logic := '0';
    signal su27_boundary_ou27_bytes_loaded : unsigned(26 downto 0) := (others => '0');
begin
    boundary : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_download <= i_download;
            s_boundary_i_word_valid <= i_word_valid;
            o_word_ready <= s_boundary_o_word_ready;
            su27_boundary_iu27_word_byte_address <= iu27_word_byte_address;
            su16_boundary_iu16_word_data <= iu16_word_data;
            s_boundary_i_transport_idle <= i_transport_idle;
            s_boundary_i_loader_ready <= i_loader_ready;
            s_boundary_i_loader_response_valid <= i_loader_response_valid;
            o_loading <= s_boundary_o_loading;
            o_loader_request <= s_boundary_o_loader_request;
            ou27_loader_byte_address <= su27_boundary_ou27_loader_byte_address;
            ou16_loader_data <= su16_boundary_ou16_loader_data;
            ou2_loader_bytes <= su2_boundary_ou2_loader_bytes;
            o_game_reset <= s_boundary_o_game_reset;
            o_image_valid <= s_boundary_o_image_valid;
            o_error <= s_boundary_o_error;
            o_done <= s_boundary_o_done;
            ou27_bytes_loaded <= su27_boundary_ou27_bytes_loaded;
        end if;
    end process;
    download : entity work.rabbitpunch_download
        port map (
            i_clk => i_clk,
            i_download => s_boundary_i_download,
            i_word_valid => s_boundary_i_word_valid,
            o_word_ready => s_boundary_o_word_ready,
            iu27_word_byte_address => su27_boundary_iu27_word_byte_address,
            iu16_word_data => su16_boundary_iu16_word_data,
            i_transport_idle => s_boundary_i_transport_idle,
            i_loader_ready => s_boundary_i_loader_ready,
            i_loader_response_valid => s_boundary_i_loader_response_valid,
            o_loading => s_boundary_o_loading,
            o_loader_request => s_boundary_o_loader_request,
            ou27_loader_byte_address => su27_boundary_ou27_loader_byte_address,
            ou16_loader_data => su16_boundary_ou16_loader_data,
            ou2_loader_bytes => su2_boundary_ou2_loader_bytes,
            o_game_reset => s_boundary_o_game_reset,
            o_image_valid => s_boundary_o_image_valid,
            o_error => s_boundary_o_error,
            o_done => s_boundary_o_done,
            ou27_bytes_loaded => su27_boundary_ou27_bytes_loaded
        );
end architecture;
