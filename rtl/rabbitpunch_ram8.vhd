library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library altera_mf;
use altera_mf.altera_mf_components.all;

-- Sound CPU read/write port plus read-only state inspection, one clock.
-- RAM contents are deliberately not reset. CPU writes define each byte.
-- CPU read data is meaningful for reads only; mixed-port same-address collisions
-- have no guaranteed value and must be avoided by sound/state arbitration.
entity rabbitpunch_ram8 is
    generic (sint_ADDRESS_BITS : positive := 11);
    port (
        i_clk : in std_logic;
        i_cpu_enable : in std_logic;
        i_cpu_write : in std_logic;
        iux_cpu_address : in unsigned;
        iu8_cpu_data : in unsigned(7 downto 0);
        ou8_cpu_data : out unsigned(7 downto 0);
        i_view_enable : in std_logic;
        iux_view_address : in unsigned;
        ou8_view_data : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_ram8 is
    subtype t_data is unsigned(7 downto 0);
    signal s_cpu_write_enable : std_logic;
    signal s_cpu_read_enable : std_logic;
begin
    assert iux_cpu_address'length = sint_ADDRESS_BITS and iux_view_address'length = sint_ADDRESS_BITS
        report "RAM address ports must match sint_ADDRESS_BITS" severity failure;
    s_cpu_write_enable <= i_cpu_enable and i_cpu_write;
    s_cpu_read_enable <= i_cpu_enable and not i_cpu_write;

    -- Explicit ports avoid Quartus 17 replicating inferred read/write RAM.
    -- Vendor vector conversions stay inside this unsigned interface boundary.
    physical_ram : altsyncram
        generic map (
            intended_device_family => "Cyclone V",
            operation_mode => "BIDIR_DUAL_PORT",
            ram_block_type => "M10K",
            width_a => 8,
            widthad_a => sint_ADDRESS_BITS,
            numwords_a => 2**sint_ADDRESS_BITS,
            width_b => 8,
            widthad_b => sint_ADDRESS_BITS,
            numwords_b => 2**sint_ADDRESS_BITS,
            width_byteena_a => 1,
            width_byteena_b => 1,
            byte_size => 8,
            address_reg_b => "CLOCK1",
            rdcontrol_reg_b => "CLOCK1",
            indata_reg_b => "CLOCK1",
            wrcontrol_wraddress_reg_b => "CLOCK1",
            byteena_reg_b => "CLOCK1",
            outdata_reg_a => "UNREGISTERED",
            outdata_reg_b => "UNREGISTERED",
            read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
            read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
            read_during_write_mode_mixed_ports => "DONT_CARE",
            power_up_uninitialized => "TRUE"
        )
        port map (
            clock0 => i_clk,
            clock1 => i_clk,
            clocken0 => i_cpu_enable,
            clocken1 => i_view_enable,
            wren_a => s_cpu_write_enable,
            wren_b => '0',
            rden_a => s_cpu_read_enable,
            rden_b => i_view_enable,
            address_a => std_logic_vector(iux_cpu_address),
            address_b => std_logic_vector(iux_view_address),
            data_a => std_logic_vector(iu8_cpu_data),
            data_b => (others => '0'),
            byteena_a => "1",
            byteena_b => (others => '1'),
            t_data(q_a) => ou8_cpu_data,
            t_data(q_b) => ou8_view_data
        );
end architecture;
