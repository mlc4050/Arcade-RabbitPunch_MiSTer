-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Protocol-test architecture only: deterministic boot bytes and sound work
-- RAM, with16-clock replies for RAM transactions. Selected explicitly by the
-- test's last-analyzed architecture, never included in production files.qip.
-- This qualifies the surrounding owner's debt handling, not the real RAM bus.
architecture delayed_state_test of rabbitpunch_sound_bus is
    type t_bytes is array(natural range <>) of unsigned(7 downto 0);
    constant CU8_BOOT : t_bytes := (
        x"F3", x"31", x"00", x"00", x"ED", x"56",
        x"3E", x"3C", x"ED", x"47", x"3E", x"80", x"ED", x"4F",
        x"01", x"22", x"33", x"11", x"44", x"55", x"21", x"66", x"77",
        x"DD", x"21", x"88", x"99", x"FD", x"21", x"AA", x"BB", x"AF",
        x"08", x"D9", x"AF", x"01", x"DD", x"EE", x"11", x"34", x"12",
        x"21", x"78", x"56", x"D9", x"08", x"C3", x"40", x"00"
    );
    signal su8_ram : t_bytes(0 to 2047) := (others => (others => '0'));
    signal s_pending : std_logic := '0';
begin
    o_idle <= '1' when s_pending = '0' and o_response_valid = '0' and i_request = '0' else '0';
    o_rom_request <= '0';
    ou16_rom_address <= (others => '0');
    o_ym_write <= '0';
    o_ym_data_register <= '0';
    ou8_ym_write_data <= (others => '0');
    o_command_read <= '0';
    o_adpcm_control_write <= '0';
    o_adpcm_command_write <= '0';
    ou8_adpcm_data <= (others => '0');
    ou8_view_data <= (others => '0');
    backend : process(i_clk)
        variable vint_delay : natural := 0;
        variable vu8_reply : unsigned(7 downto 0);
    begin
        if (rising_edge(i_clk)) then
            o_response_valid <= '0';
            if (s_pending = '1') then
                if (vint_delay = 0) then
                    ou8_response_data <= vu8_reply;
                    o_response_valid <= '1';
                    s_pending <= '0';
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
            if (i_request = '1') then
                assert (s_pending = '0') report "Owner allowed overlapping delayed sound transactions" severity failure;
                s_pending <= '1';
                if (iu16_request_address >= x"F800") then
                    vu8_reply := su8_ram(to_integer(iu16_request_address(10 downto 0)));
                    if (i_request_write = '1') then
                        su8_ram(to_integer(iu16_request_address(10 downto 0))) <= iu8_request_data;
                    end if;
                    vint_delay := 16;
                else
                    if (iu16_request_address < CU8_BOOT'length) then
                        vu8_reply := CU8_BOOT(to_integer(iu16_request_address));
                    else
                        assert (iu16_request_address = 64 or iu16_request_address = 65)
                            report "Reset/capture corrupted test CPU boot" severity failure;
                        vu8_reply := x"76";
                    end if;
                    vint_delay := 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
