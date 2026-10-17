library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The bus runs on i_clk while the Z80 advances only at enabled, completed
-- transaction boundaries. A request is a one-clock pulse with one reply owed.
entity soundcpu_check is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_pause : in std_logic;
        i_interrupt : in std_logic;
        o_request : out std_logic;
        o_request_write : out std_logic;
        ou16_request_address : out unsigned(15 downto 0);
        ou8_request_data : out unsigned(7 downto 0);
        i_response_valid : in std_logic;
        iu8_response_data : in unsigned(7 downto 0);
        o_paused : out std_logic;
        o_halted : out std_logic
    );
end entity;


architecture evaluation of soundcpu_check is
    signal s_boundary_i_reset : std_logic;
    signal s_boundary_i_enable : std_logic;
    signal s_boundary_i_pause : std_logic;
    signal s_boundary_i_interrupt : std_logic;
    signal s_boundary_o_request : std_logic;
    signal s_boundary_o_request_write : std_logic;
    signal su16_boundary_ou16_request_address : unsigned(15 downto 0);
    signal su8_boundary_ou8_request_data : unsigned(7 downto 0);
    signal s_boundary_i_response_valid : std_logic;
    signal su8_boundary_iu8_response_data : unsigned(7 downto 0);
    signal s_boundary_o_paused : std_logic;
    signal s_boundary_o_halted : std_logic;
begin
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_reset <= i_reset;
            s_boundary_i_enable <= i_enable;
            s_boundary_i_pause <= i_pause;
            s_boundary_i_interrupt <= i_interrupt;
            o_request <= s_boundary_o_request;
            o_request_write <= s_boundary_o_request_write;
            ou16_request_address <= su16_boundary_ou16_request_address;
            ou8_request_data <= su8_boundary_ou8_request_data;
            s_boundary_i_response_valid <= i_response_valid;
            su8_boundary_iu8_response_data <= iu8_response_data;
            o_paused <= s_boundary_o_paused;
            o_halted <= s_boundary_o_halted;
        end if;
    end process;
    sound_cpu : entity work.rabbitpunch_soundcpu
        port map (
            i_clk => i_clk,
            i_reset => s_boundary_i_reset,
            i_enable => s_boundary_i_enable,
            i_pause => s_boundary_i_pause,
            i_interrupt => s_boundary_i_interrupt,
            o_request => s_boundary_o_request,
            o_request_write => s_boundary_o_request_write,
            ou16_request_address => su16_boundary_ou16_request_address,
            ou8_request_data => su8_boundary_ou8_request_data,
            i_response_valid => s_boundary_i_response_valid,
            iu8_response_data => su8_boundary_iu8_response_data,
            o_paused => s_boundary_o_paused,
            o_halted => s_boundary_o_halted
        );
end architecture;
