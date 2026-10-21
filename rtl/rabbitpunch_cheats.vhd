-- SPDX-License-Identifier: GPL-3.0-or-later
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MiSTer 16-byte codes: flags/address/compare/value, all big-endian.
-- Only the main CPU read response is overridden. RAM and other masters are raw.
entity rabbitpunch_cheats is
    port (
        i_clk : in std_logic;
        i_clear : in std_logic;
        i_download : in std_logic;
        i_write : in std_logic;
        iu27_byte_address : in unsigned(26 downto 0);
        iu8_byte_data : in unsigned(7 downto 0);
        i_cpu_read : in std_logic;
        iu24_cpu_address : in unsigned(23 downto 0);
        iu16_cpu_data : in unsigned(15 downto 0);
        ou16_cpu_data : out unsigned(15 downto 0);
        o_available : out std_logic;
        o_load_error : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_cheats is
    constant CINT_MAX_CODES : positive := 8;
    type t_code is record
        su24_address : unsigned(23 downto 0);
        su32_compare : unsigned(31 downto 0);
        su32_data : unsigned(31 downto 0);
        su3_size : unsigned(2 downto 0);
        su2_method : unsigned(1 downto 0);
        s_compare : std_logic;
        s_valid : std_logic;
    end record;
    type t_codes is array (0 to CINT_MAX_CODES - 1) of t_code;
    signal styp_codes : t_codes := (others => (
        su24_address => (others => '0'),
        su32_compare => (others => '0'),
        su32_data => (others => '0'),
        su3_size => (others => '0'),
        su2_method => (others => '0'),
        s_compare => '0',
        s_valid => '0'
    ));
    signal su128_payload : unsigned(127 downto 0) := (others => '0');
    signal sint_byte_count : natural range 0 to CINT_MAX_CODES * 16 := 0;
    signal s_previous_download : std_logic := '0';
    signal s_ready : std_logic := '0';
    signal s_error : std_logic := '0';
    signal su24_mapped_address : unsigned(23 downto 0);
begin
    -- The board and MAME globally decode only the low 20 address bits.
    su24_mapped_address <= "0000" & iu24_cpu_address(19 downto 0);
    o_load_error <= s_error;
    process(i_clk)
        variable vu128_payload : unsigned(127 downto 0);
        variable vu32_flags, vu32_address : unsigned(31 downto 0);
        variable vint_count : natural range 0 to CINT_MAX_CODES * 16;
        variable vint_slot : natural range 0 to CINT_MAX_CODES - 1;
        variable v_error : std_logic;
        variable vbool_record_valid : boolean;
    begin
        if (rising_edge(i_clk)) then
            s_previous_download <= i_download;
            if (i_clear = '1') then
                for vint_index in styp_codes'range loop
                    styp_codes(vint_index).s_valid <= '0';
                end loop;
                su128_payload <= (others => '0');
                sint_byte_count <= 0;
                s_previous_download <= '0';
                s_ready <= '0';
                s_error <= '0';
            elsif (i_download = '1') then
                s_ready <= '0';
                vu128_payload := su128_payload;
                vint_count := sint_byte_count;
                v_error := s_error;
                if (s_previous_download = '0') then
                    vu128_payload := (others => '0');
                    vint_count := 0;
                    v_error := '0';
                    for vint_index in styp_codes'range loop
                        styp_codes(vint_index).s_valid <= '0';
                    end loop;
                end if;
                if (i_write = '1') then
                    if (v_error = '0' and vint_count < CINT_MAX_CODES * 16 and iu27_byte_address = to_unsigned(vint_count, 27)) then
                        vu128_payload := vu128_payload(119 downto 0) & iu8_byte_data;
                        if (vint_count mod 16 = 15) then
                            vu32_flags := vu128_payload(127 downto 96);
                            vu32_address := vu128_payload(95 downto 64);
                            vbool_record_valid :=
                                (vu32_flags and not to_unsigned(16#371#, 32)) = 0 and
                                vu32_flags(9 downto 8) /= 3 and
                                vu32_address >= 16#0FC000# and vu32_address <= 16#0FFFFF#;
                            case to_integer(vu32_flags(6 downto 4)) is
                                when 1 =>
                                    null;
                                when 2 =>
                                    vbool_record_valid := vbool_record_valid and vu32_address(0) = '0';
                                when 4 =>
                                    vbool_record_valid := vbool_record_valid and vu32_address(1 downto 0) = 0;
                                when others =>
                                    vbool_record_valid := false;
                            end case;
                            if (vbool_record_valid) then
                                vint_slot := vint_count / 16;
                                styp_codes(vint_slot).su24_address <= vu32_address(23 downto 0);
                                styp_codes(vint_slot).su32_compare <= vu128_payload(63 downto 32);
                                styp_codes(vint_slot).su32_data <= vu128_payload(31 downto 0);
                                styp_codes(vint_slot).su3_size <= vu32_flags(6 downto 4);
                                styp_codes(vint_slot).su2_method <= vu32_flags(9 downto 8);
                                styp_codes(vint_slot).s_compare <= vu32_flags(0);
                                styp_codes(vint_slot).s_valid <= '1';
                            else
                                v_error := '1';
                            end if;
                        end if;
                        vint_count := vint_count + 1;
                    else
                        v_error := '1';
                    end if;
                end if;
                if (v_error = '1') then
                    for vint_index in styp_codes'range loop
                        styp_codes(vint_index).s_valid <= '0';
                    end loop;
                end if;
                su128_payload <= vu128_payload;
                sint_byte_count <= vint_count;
                s_error <= v_error;
            elsif (s_previous_download = '1') then
                -- Main_MiSTer sends two zero bytes for an empty cheat list.
                if (s_error = '0' and (sint_byte_count mod 16 = 0 or
                    (sint_byte_count = 2 and su128_payload(15 downto 0) = 0))) then
                    s_ready <= '1';
                else
                    s_error <= '1';
                    s_ready <= '0';
                    for vint_index in styp_codes'range loop
                        styp_codes(vint_index).s_valid <= '0';
                    end loop;
                end if;
            end if;
        end if;
    end process;

    process(all)
        variable vu16_result, vu16_value, vu16_compare, vu16_mask : unsigned(15 downto 0);
        variable vbool_match : boolean;
    begin
        vu16_result := iu16_cpu_data;
        o_available <= '0';
        for vint_index in styp_codes'range loop
            if (s_ready = '1' and i_download = '0' and i_clear = '0' and styp_codes(vint_index).s_valid = '1') then
                o_available <= '1';
                vu16_mask := (others => '0');
                vu16_value := (others => '0');
                vu16_compare := (others => '0');
                vbool_match := false;
                case to_integer(styp_codes(vint_index).su3_size) is
                    when 1 =>
                        vbool_match := styp_codes(vint_index).su24_address(23 downto 1) = su24_mapped_address(23 downto 1);
                        if (styp_codes(vint_index).su24_address(0) = '0') then
                            vu16_mask := x"FF00";
                            vu16_value(15 downto 8) := styp_codes(vint_index).su32_data(7 downto 0);
                            vu16_compare(15 downto 8) := styp_codes(vint_index).su32_compare(7 downto 0);
                        else
                            vu16_mask := x"00FF";
                            vu16_value(7 downto 0) := styp_codes(vint_index).su32_data(7 downto 0);
                            vu16_compare(7 downto 0) := styp_codes(vint_index).su32_compare(7 downto 0);
                        end if;
                    when 2 =>
                        vbool_match := styp_codes(vint_index).su24_address(23 downto 1) = su24_mapped_address(23 downto 1);
                        vu16_mask := x"FFFF";
                        vu16_value := styp_codes(vint_index).su32_data(15 downto 0);
                        vu16_compare := styp_codes(vint_index).su32_compare(15 downto 0);
                    when 4 =>
                        vbool_match := styp_codes(vint_index).su24_address(23 downto 2) = su24_mapped_address(23 downto 2);
                        vu16_mask := x"FFFF";
                        if (iu24_cpu_address(1) = '0') then
                            vu16_value := styp_codes(vint_index).su32_data(31 downto 16);
                            vu16_compare := styp_codes(vint_index).su32_compare(31 downto 16);
                        else
                            vu16_value := styp_codes(vint_index).su32_data(15 downto 0);
                            vu16_compare := styp_codes(vint_index).su32_compare(15 downto 0);
                        end if;
                    when others =>
                        null;
                end case;
                if (i_cpu_read = '1' and vbool_match and
                    (styp_codes(vint_index).s_compare = '0' or (iu16_cpu_data and vu16_mask) = (vu16_compare and vu16_mask))) then
                    case to_integer(styp_codes(vint_index).su2_method) is
                        when 1 =>
                            vu16_value := vu16_value or iu16_cpu_data;
                        when 2 =>
                            vu16_value := vu16_value and iu16_cpu_data;
                        when others =>
                            null;
                    end case;
                    -- Later codes win on overlapping lanes, using the original read value.
                    vu16_result := (vu16_result and not vu16_mask) or (vu16_value and vu16_mask);
                end if;
            end if;
        end loop;
        ou16_cpu_data <= vu16_result;
    end process;
end architecture;
