library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- F400 controls bank bit 0 and the physical active-low reset pin at bit 7.
-- F600 latches a command before producing one start edge on i_clk.
entity adpcm_check is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_control_write : in std_logic;
        i_command_write : in std_logic;
        iu8_write_data : in unsigned(7 downto 0);
        o_busy : out std_logic;
        o_rom_request : out std_logic;
        ou18_rom_address : out unsigned(17 downto 0);
        i_rom_valid : in std_logic;
        iu8_rom_data : in unsigned(7 downto 0);
        ou9_pcm : out unsigned(8 downto 0);
        o_bank : out std_logic;
        o_reset_asserted : out std_logic
    );
end entity;


architecture evaluation of adpcm_check is
    signal s_boundary_i_reset : std_logic;
    signal s_boundary_i_enable : std_logic;
    signal s_boundary_i_control_write : std_logic;
    signal s_boundary_i_command_write : std_logic;
    signal su8_boundary_iu8_write_data : unsigned(7 downto 0);
    signal s_boundary_o_busy : std_logic;
    signal s_boundary_o_rom_request : std_logic;
    signal su18_boundary_ou18_rom_address : unsigned(17 downto 0);
    signal s_boundary_i_rom_valid : std_logic;
    signal su8_boundary_iu8_rom_data : unsigned(7 downto 0);
    signal su9_boundary_ou9_pcm : unsigned(8 downto 0);
    signal s_boundary_o_bank : std_logic;
    signal s_boundary_o_reset_asserted : std_logic;
begin
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_reset <= i_reset;
            s_boundary_i_enable <= i_enable;
            s_boundary_i_control_write <= i_control_write;
            s_boundary_i_command_write <= i_command_write;
            su8_boundary_iu8_write_data <= iu8_write_data;
            o_busy <= s_boundary_o_busy;
            o_rom_request <= s_boundary_o_rom_request;
            ou18_rom_address <= su18_boundary_ou18_rom_address;
            s_boundary_i_rom_valid <= i_rom_valid;
            su8_boundary_iu8_rom_data <= iu8_rom_data;
            ou9_pcm <= su9_boundary_ou9_pcm;
            o_bank <= s_boundary_o_bank;
            o_reset_asserted <= s_boundary_o_reset_asserted;
        end if;
    end process;
    adpcm : entity work.rabbitpunch_adpcm
        port map (
            i_clk => i_clk,
            i_reset => s_boundary_i_reset,
            i_enable => s_boundary_i_enable,
            i_control_write => s_boundary_i_control_write,
            i_command_write => s_boundary_i_command_write,
            iu8_write_data => su8_boundary_iu8_write_data,
            o_busy => s_boundary_o_busy,
            o_rom_request => s_boundary_o_rom_request,
            ou18_rom_address => su18_boundary_ou18_rom_address,
            i_rom_valid => s_boundary_i_rom_valid,
            iu8_rom_data => su8_boundary_iu8_rom_data,
            ou9_pcm => su9_boundary_ou9_pcm,
            o_bank => s_boundary_o_bank,
            o_reset_asserted => s_boundary_o_reset_asserted
        );
end architecture;
