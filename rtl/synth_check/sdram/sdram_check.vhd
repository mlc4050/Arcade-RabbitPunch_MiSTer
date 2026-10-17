library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;

entity sdram_check is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        o_initialized : out std_logic;
        iu3_requests : in unsigned(2 downto 0);
        ou3_ready : out unsigned(2 downto 0);
        iu3_writes : in unsigned(2 downto 0);
        iu81_byte_addresses : in unsigned(80 downto 0);
        iu48_write_data : in unsigned(47 downto 0);
        iu6_byte_enables : in unsigned(5 downto 0);
        ou3_response_valid : out unsigned(2 downto 0);
        ou192_read_data : out unsigned(191 downto 0);
        iou16_sdram_data : inout unsigned(15 downto 0);
        ou13_sdram_address : out unsigned(12 downto 0);
        ou2_sdram_bank : out unsigned(1 downto 0);
        ou2_sdram_byte_mask : out unsigned(1 downto 0);
        o_sdram_chip_select : out std_logic;
        o_sdram_write_n : out std_logic;
        o_sdram_row_n : out std_logic;
        o_sdram_column_n : out std_logic;
        o_sdram_clock_enable : out std_logic
    );
end entity;

-- Synthesis-only registered tester boundary; no production latency changes.
architecture evaluation of sdram_check is
    signal s_boundary_i_initialize : std_logic;
    signal s_boundary_o_initialized : std_logic;
    signal su3_boundary_iu3_requests : unsigned(2 downto 0);
    signal su3_boundary_ou3_ready : unsigned(2 downto 0);
    signal su3_boundary_iu3_writes : unsigned(2 downto 0);
    signal su81_boundary_iu81_byte_addresses : unsigned(80 downto 0);
    signal su48_boundary_iu48_write_data : unsigned(47 downto 0);
    signal su6_boundary_iu6_byte_enables : unsigned(5 downto 0);
    signal su3_boundary_ou3_response_valid : unsigned(2 downto 0);
    signal su192_boundary_ou192_read_data : unsigned(191 downto 0);
    signal su13_boundary_ou13_sdram_address : unsigned(12 downto 0);
    signal su2_boundary_ou2_sdram_bank : unsigned(1 downto 0);
    signal su2_boundary_ou2_sdram_byte_mask : unsigned(1 downto 0);
    signal s_boundary_o_sdram_chip_select : std_logic;
    signal s_boundary_o_sdram_write_n : std_logic;
    signal s_boundary_o_sdram_row_n : std_logic;
    signal s_boundary_o_sdram_column_n : std_logic;
    signal s_boundary_o_sdram_clock_enable : std_logic;
    signal su27_addresses : t_sdram_addresses;
    signal su16_data : t_sdram_write_data;
    signal su2_bytes : t_sdram_byte_enables;
    signal su64_data : t_sdram_read_data;
begin
    su27_addresses(0) <= su81_boundary_iu81_byte_addresses(26 downto 0);
    su16_data(0) <= su48_boundary_iu48_write_data(15 downto 0);
    su2_bytes(0) <= su6_boundary_iu6_byte_enables(1 downto 0);
    su192_boundary_ou192_read_data(63 downto 0) <= su64_data(0);
    su27_addresses(1) <= su81_boundary_iu81_byte_addresses(53 downto 27);
    su16_data(1) <= su48_boundary_iu48_write_data(31 downto 16);
    su2_bytes(1) <= su6_boundary_iu6_byte_enables(3 downto 2);
    su192_boundary_ou192_read_data(127 downto 64) <= su64_data(1);
    su27_addresses(2) <= su81_boundary_iu81_byte_addresses(80 downto 54);
    su16_data(2) <= su48_boundary_iu48_write_data(47 downto 32);
    su2_bytes(2) <= su6_boundary_iu6_byte_enables(5 downto 4);
    su192_boundary_ou192_read_data(191 downto 128) <= su64_data(2);
    ou13_sdram_address <= su13_boundary_ou13_sdram_address;
    ou2_sdram_bank <= su2_boundary_ou2_sdram_bank;
    ou2_sdram_byte_mask <= su2_boundary_ou2_sdram_byte_mask;
    o_sdram_chip_select <= s_boundary_o_sdram_chip_select;
    o_sdram_write_n <= s_boundary_o_sdram_write_n;
    o_sdram_row_n <= s_boundary_o_sdram_row_n;
    o_sdram_column_n <= s_boundary_o_sdram_column_n;
    o_sdram_clock_enable <= s_boundary_o_sdram_clock_enable;
    memory_transport : entity work.rabbitpunch_sdram
        port map (
            i_clk => i_clk,
            i_initialize => s_boundary_i_initialize,
            o_initialized => s_boundary_o_initialized,
            iu3_requests => su3_boundary_iu3_requests,
            ou3_ready => su3_boundary_ou3_ready,
            iu3_writes => su3_boundary_iu3_writes,
            iu27_byte_addresses => su27_addresses,
            iu16_write_data => su16_data,
            iu2_byte_enables => su2_bytes,
            ou3_response_valid => su3_boundary_ou3_response_valid,
            ou64_read_data => su64_data,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => su13_boundary_ou13_sdram_address,
            ou2_sdram_bank => su2_boundary_ou2_sdram_bank,
            ou2_sdram_byte_mask => su2_boundary_ou2_sdram_byte_mask,
            o_sdram_chip_select => s_boundary_o_sdram_chip_select,
            o_sdram_write_n => s_boundary_o_sdram_write_n,
            o_sdram_row_n => s_boundary_o_sdram_row_n,
            o_sdram_column_n => s_boundary_o_sdram_column_n,
            o_sdram_clock_enable => s_boundary_o_sdram_clock_enable
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            s_boundary_i_initialize <= i_initialize;
            o_initialized <= s_boundary_o_initialized;
            su3_boundary_iu3_requests <= iu3_requests;
            ou3_ready <= su3_boundary_ou3_ready;
            su3_boundary_iu3_writes <= iu3_writes;
            su81_boundary_iu81_byte_addresses <= iu81_byte_addresses;
            su48_boundary_iu48_write_data <= iu48_write_data;
            su6_boundary_iu6_byte_enables <= iu6_byte_enables;
            ou3_response_valid <= su3_boundary_ou3_response_valid;
            ou192_read_data <= su192_boundary_ou192_read_data;
        end if;
    end process;
end architecture;
