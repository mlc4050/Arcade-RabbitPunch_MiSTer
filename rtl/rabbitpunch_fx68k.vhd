library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Naming-only boundary around the unchanged fx68k implementation.
-- All _n ports are active low. Address bit zero is supplied by the byte strobes.
entity rabbitpunch_fx68k is
    port (
        i_clk, i_external_reset, i_powerup_reset : in std_logic;
        i_enable_phase1, i_enable_phase2, i_run : in std_logic;
        o_read, o_address_strobe_n : out std_logic;
        o_upper_byte_strobe_n, o_lower_byte_strobe_n : out std_logic;
        ou23_word_address : out unsigned(23 downto 1);
        ou16_write_data : out unsigned(15 downto 0);
        iu16_read_data : in unsigned(15 downto 0);
        i_transfer_acknowledge_n, i_peripheral_transfer_n, i_bus_error_n : in std_logic;
        i_bus_request_n, i_bus_grant_acknowledge_n : in std_logic;
        iu3_interrupt_level_n : in unsigned(2 downto 0);
        ou3_function_code : out unsigned(2 downto 0);
        o_peripheral_clock, o_peripheral_address_valid_n : out std_logic;
        o_bus_grant_n, o_external_reset_out_n, o_halted_out_n : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_fx68k is
    -- These names belong to the vendor module. Keep the translation here.
    component fx68k is
        port (
            clk, HALTn, extReset, pwrUp, enPhi1, enPhi2 : in std_logic;
            eRWn, ASn, LDSn, UDSn, E, VMAn, FC0, FC1, FC2, BGn,
            oRESETn, oHALTEDn : out std_logic;
            DTACKn, VPAn, BERRn, BRn, BGACKn, IPL0n, IPL1n, IPL2n : in std_logic;
            iEdb : in unsigned(15 downto 0);
            oEdb : out unsigned(15 downto 0);
            eab : out unsigned(23 downto 1)
        );
    end component;
begin
    cpu : fx68k port map (
        clk => i_clk,
        HALTn => i_run, -- fx68k single-step control: high permits execution.
        extReset => i_external_reset,
        pwrUp => i_powerup_reset,
        enPhi1 => i_enable_phase1,
        enPhi2 => i_enable_phase2,
        eRWn => o_read, -- High reads memory; low writes memory.
        ASn => o_address_strobe_n,
        LDSn => o_lower_byte_strobe_n,
        UDSn => o_upper_byte_strobe_n,
        E => o_peripheral_clock, -- Motorola 6800 peripheral bus clock.
        VMAn => o_peripheral_address_valid_n, -- 6800 peripheral cycle qualifier.
        FC0 => ou3_function_code(0), -- CPU address space / interrupt-acknowledge code.
        FC1 => ou3_function_code(1),
        FC2 => ou3_function_code(2),
        BGn => o_bus_grant_n, -- Grants the bus to an external DMA master.
        oRESETn => o_external_reset_out_n, -- RESET instruction's peripheral reset.
        oHALTEDn => o_halted_out_n, -- CPU reports a halted execution state.
        DTACKn => i_transfer_acknowledge_n,
        VPAn => i_peripheral_transfer_n, -- Selects 6800 transfer or interrupt autovector.
        BERRn => i_bus_error_n,
        BRn => i_bus_request_n,
        BGACKn => i_bus_grant_acknowledge_n,
        IPL0n => iu3_interrupt_level_n(0),
        IPL1n => iu3_interrupt_level_n(1),
        IPL2n => iu3_interrupt_level_n(2),
        iEdb => iu16_read_data,
        oEdb => ou16_write_data,
        eab => ou23_word_address
    );
end architecture;
