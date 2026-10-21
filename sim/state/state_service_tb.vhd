-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;
use work.state_service_reference.all;

entity state_service_tb is
    generic (
        GINT_CASE_GROUP : natural range 0 to 4 := 0
    );
end entity;

architecture test of state_service_tb is
    type t_bytes is array(0 to CINT_BODY_BYTES - 1) of unsigned(7 downto 0);
    type t_slot is array(0 to CINT_IMAGE_BYTES/8) of unsigned(63 downto 0);
    type t_slots is array(0 to 3) of t_slot;
    function F_BYTE(vint_address : natural) return unsigned is
        variable vint_word, vint_lane : natural;
        variable vu32_word : unsigned(31 downto 0) := (others => '0');
    begin
        if (vint_address < 106496) then
            return to_unsigned((vint_address*17 + 3) mod 256, 8);
        elsif (vint_address < 106592) then
            vint_word := (vint_address - 106496)/4;
            vint_lane := (vint_address - 106496) mod 4;
            case vint_word is
                when 18 => vu32_word := x"000FF7FA";
                when 19 => vu32_word := x"00002000";
                when 20 => vu32_word := x"00000400";
                when others => null;
            end case;
            return vu32_word(8*vint_lane + 7 downto 8*vint_lane);
        end if;
        return x"00";
    end function;
    function F_INITIAL return t_bytes is
        variable vu8_data : t_bytes;
    begin
        for vint_byte in vu8_data'range loop
            vu8_data(vint_byte) := F_BYTE(vint_byte);
        end loop;
        return vu8_data;
    end function;
    signal s_clk : std_logic := '0';
    signal s_initialize : std_logic := '1';
    signal s_save, s_restore, s_cancel, s_reset_completed : std_logic := '0';
    signal s_ready, s_busy, s_finished, s_success, s_restoring, s_incomplete : std_logic;
    signal su2_slot : unsigned(1 downto 0) := (others => '0');
    signal su8_error : unsigned(7 downto 0);
    signal s_machine_ready, s_machine_busy, s_machine_held, s_machine_finished : std_logic := '0';
    signal s_acquire, s_machine_cancel, s_release : std_logic;
    signal su4_machine_error : unsigned(3 downto 0) := (others => '0');
    signal s_apply_begin, s_body_request, s_body_ready, s_body_write, s_body_response : std_logic := '0';
    signal s_body_error, s_commit, s_committed : std_logic := '0';
    signal su18_body_address : unsigned(17 downto 0);
    signal su8_body_write, su8_body_read : unsigned(7 downto 0);
    signal s_ddr_read, s_ddr_write, s_ddr_busy, s_ddr_valid : std_logic := '0';
    signal su29_ddr_address : unsigned(28 downto 0);
    signal su64_ddr_write, su64_ddr_read : unsigned(63 downto 0);
    signal su8_memory : t_bytes := F_INITIAL;
    signal su64_slots : t_slots := (others => (others => (others => '0')));
    signal sint_cycles, sint_acquires, sint_applied : natural := 0;
    signal s_mutate, s_corrupt, s_inject_body_error : std_logic := '0';
begin
    s_clk <= not s_clk after 5 ns;
    s_body_ready <= '1' when sint_cycles mod 7 /= 0 else '0';
    s_ddr_busy <= '1' when sint_cycles mod 11 < 3 else '0';
    service : entity work.rabbitpunch_state_service
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_game_reset_completed => s_reset_completed,
            i_save => s_save,
            i_restore => s_restore,
            i_cancel => s_cancel,
            iu2_slot => su2_slot,
            i_rom_identity_valid => '1',
            iu32_abi_signature => x"11223344",
            iu32_rom_identity => x"55667788",
            iu32_config_identity => x"99AABBCC",
            o_ready => s_ready,
            o_busy => s_busy,
            o_finished => s_finished,
            o_success => s_success,
            o_restoring => s_restoring,
            o_incomplete => s_incomplete,
            ou8_error => su8_error,
            i_machine_ready => s_machine_ready,
            i_machine_busy => s_machine_busy,
            i_machine_held => s_machine_held,
            i_machine_finished => s_machine_finished,
            iu4_machine_error => su4_machine_error,
            o_machine_acquire => s_acquire,
            o_machine_cancel => s_machine_cancel,
            o_machine_release => s_release,
            o_body_apply_begin => s_apply_begin,
            o_body_request => s_body_request,
            i_body_ready => s_body_ready,
            o_body_write => s_body_write,
            ou18_body_address => su18_body_address,
            ou8_body_data => su8_body_write,
            i_body_response => s_body_response,
            i_body_error => s_body_error,
            iu8_body_data => su8_body_read,
            o_body_commit => s_commit,
            i_body_committed => s_committed,
            i_body_commit_error => '0',
            o_ddr_read => s_ddr_read,
            o_ddr_write => s_ddr_write,
            ou29_ddr_word_address => su29_ddr_address,
            ou64_ddr_write_data => su64_ddr_write,
            i_ddr_busy => s_ddr_busy,
            i_ddr_read_valid => s_ddr_valid,
            iu64_ddr_read_data => su64_ddr_read
        );
    machine_model : process(s_clk)
        variable vint_acquire_delay, vint_return_delay : natural := 0;
        variable v_unsafe_reported : boolean := false;
    begin
        if (rising_edge(s_clk)) then
            s_machine_finished <= '0';
            if (s_initialize = '1') then
                s_machine_held <= '0';
                s_machine_busy <= '0';
                s_machine_ready <= '1';
                su4_machine_error <= (others => '0');
                vint_acquire_delay := 0;
                vint_return_delay := 0;
                v_unsafe_reported := false;
            elsif (s_acquire = '1' and s_machine_ready = '1') then
                s_machine_ready <= '0';
                s_machine_busy <= '1';
                vint_acquire_delay := 5;
                sint_acquires <= sint_acquires + 1;
                su4_machine_error <= (others => '0');
            elsif (vint_acquire_delay > 0) then
                vint_acquire_delay := vint_acquire_delay - 1;
                if (vint_acquire_delay = 0) then
                    s_machine_held <= '1';
                end if;
            elsif (vint_return_delay > 0) then
                vint_return_delay := vint_return_delay - 1;
                if (vint_return_delay = 0) then
                    s_machine_held <= '0';
                    s_machine_busy <= '0';
                    s_machine_ready <= '1';
                    s_machine_finished <= '1';
                    su4_machine_error <= (others => '0');
                    v_unsafe_reported := false;
                end if;
            elsif (s_machine_held = '1' and (s_release = '1' or s_machine_cancel = '1')) then
                if (s_incomplete = '1') then
                    if (not v_unsafe_reported) then
                        su4_machine_error <= to_unsigned(6, 4);
                        s_machine_finished <= '1';
                        v_unsafe_reported := true;
                    end if;
                else
                    vint_return_delay := 7;
                end if;
            end if;
        end if;
    end process;
    body_model : process(s_clk)
        variable vint_delay, vint_commit_delay, vint_address, vint_written : natural := 0;
        variable v_write, v_fail : boolean := false;
        variable vu8_data : unsigned(7 downto 0);
    begin
        if (rising_edge(s_clk)) then
            sint_cycles <= sint_cycles + 1;
            s_body_response <= '0';
            s_body_error <= '0';
            s_committed <= '0';
            if (s_mutate = '1') then
                for vint_byte in 0 to 106495 loop
                    su8_memory(vint_byte) <= F_BYTE(vint_byte) xor x"A5";
                end loop;
            end if;
            if (vint_delay > 0) then
                vint_delay := vint_delay - 1;
                if (vint_delay = 0) then
                    s_body_response <= '1';
                    if (v_write) then
                        su8_memory(vint_address) <= vu8_data;
                        sint_applied <= sint_applied + 1;
                    else
                        su8_body_read <= su8_memory(vint_address);
                    end if;
                    if (v_fail) then
                        s_body_error <= '1';
                    end if;
                end if;
            elsif (s_body_request = '1' and s_body_ready = '1') then
                assert (s_machine_held = '1') report "Body access before actual machine lease" severity failure;
                vint_address := to_integer(su18_body_address);
                assert (vint_address < CINT_BODY_BYTES) severity failure;
                v_write := s_body_write = '1';
                v_fail := v_write and s_inject_body_error = '1' and vint_address = 100;
                vu8_data := su8_body_write;
                vint_delay := 6;
                if (v_write) then
                    assert (vint_address = vint_written) report "Unordered full-image application" severity failure;
                    vint_written := vint_written + 1;
                end if;
            end if;
            if (s_apply_begin = '1') then
                assert (vint_delay = 0 and s_machine_held = '1') severity failure;
                vint_written := 0;
            end if;
            if (vint_commit_delay > 0) then
                vint_commit_delay := vint_commit_delay - 1;
                if (vint_commit_delay = 0) then
                    s_committed <= '1';
                end if;
            elsif (s_commit = '1') then
                assert (vint_written = CINT_BODY_BYTES and vint_delay = 0) severity failure;
                vint_commit_delay := 4;
            end if;
        end if;
    end process;
    ddr_model : process(s_clk)
        variable vint_delay, vint_slot, vint_word : natural := 0;
        variable vu64_data : unsigned(63 downto 0);
        variable vint_address, vint_request_slot, vint_request_word : natural;
    begin
        if (rising_edge(s_clk)) then
            s_ddr_valid <= '0';
            if (s_corrupt = '1') then
                su64_slots(0)(200) <= su64_slots(0)(200) xor to_unsigned(1, 64);
            end if;
            if (vint_delay > 0) then
                vint_delay := vint_delay - 1;
                if (vint_delay = 0) then
                    su64_ddr_read <= vu64_data;
                    s_ddr_valid <= '1';
                end if;
            end if;
            if ((s_ddr_read = '1' or s_ddr_write = '1') and s_ddr_busy = '0') then
                assert (not (s_ddr_read = '1' and s_ddr_write = '1')) severity failure;
                vint_address := to_integer(su29_ddr_address) - 16#07C00000#;
                vint_request_slot := vint_address/32768;
                vint_request_word := vint_address mod 32768;
                assert (vint_request_slot < 4 and vint_request_word <= CINT_IMAGE_BYTES/8) severity failure;
                if (s_ddr_write = '1') then
                    assert (s_machine_held = '0') report "Save published before machine return" severity failure;
                    su64_slots(vint_request_slot)(vint_request_word) <= su64_ddr_write;
                else
                    assert (vint_delay = 0) report "DDR read credit overlapped" severity failure;
                    vint_slot := vint_request_slot;
                    vint_word := vint_request_word;
                    vu64_data := su64_slots(vint_slot)(vint_word);
                    vint_delay := 7;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_acquires_before : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure request(v_restore : boolean; vint_slot : natural := 0) is
        begin
            report "SERVICE_REQUEST restore=" & boolean'image(v_restore) & " slot=" & integer'image(vint_slot);
            assert (s_ready = '1') report "State service did not admit request" severity failure;
            su2_slot <= to_unsigned(vint_slot, 2);
            if (v_restore) then
                s_restore <= '1';
            else
                s_save <= '1';
            end if;
            cycles;
            s_restore <= '0';
            s_save <= '0';
        end procedure;
        procedure completion(v_success : boolean) is
        begin
            if (s_finished /= '1') then
                wait until s_finished = '1' for 100 ms;
            end if;
            assert (s_finished = '1' and (s_success = '1') = v_success)
                report "Wrong service completion error=" & to_hstring(su8_error) severity failure;
            report "SERVICE_COMPLETION success=" & boolean'image(v_success) & " error=" & to_hstring(su8_error);
            cycles(3);
            assert (s_busy = '0') severity failure;
        end procedure;
        procedure check_body is
        begin
            for vint_byte in su8_memory'range loop
                assert (su8_memory(vint_byte) = F_BYTE(vint_byte))
                    report "Complete restored body differs byte=" & integer'image(vint_byte) severity failure;
            end loop;
        end procedure;
    begin
        cycles(10);
        s_initialize <= '0';
        cycles(4);
        request(false);
        if (GINT_CASE_GROUP = 4) then
            wait until s_body_request = '1' and s_body_ready = '1';
            cycles(2);
            s_cancel <= '1';
            cycles;
            s_cancel <= '0';
            completion(false);
            check_body;
            assert (sint_applied = 0 and s_machine_held = '0' and su64_slots(0)(0) = 0)
                report "Canceled snapshot published or kept the machine held" severity failure;
            report "STATE_SERVICE_PASS group4 canceled snapshot body credit and FAIL cleanup";
            stop;
            wait;
        end if;
        completion(true);
        assert (su64_slots(0)(0)(63 downto 32) = CINT_IMAGE_BYTES/4 and
            su64_slots(0)(0)(31 downto 0) = 1 and
            su64_slots(0)(3)(63 downto 32) = CU32_EXPECTED_BODY_CRC)
            report "Published size/counter or independent zlib body CRC differs" severity failure;
        if (GINT_CASE_GROUP = 2) then
            s_mutate <= '1';
            cycles;
            s_mutate <= '0';
            s_inject_body_error <= '1';
            request(true);
            completion(false);
            assert (s_incomplete = '1' and s_machine_held = '1') report "Partial restore escaped its machine hold" severity failure;
            s_inject_body_error <= '0';
            request(true);
            completion(true);
            check_body;
            assert (s_incomplete = '0' and s_machine_held = '0') severity failure;
            report "STATE_SERVICE_PASS group2 partial apply hold/full retry";
            stop;
            wait;
        elsif (GINT_CASE_GROUP = 3) then
            request(true);
            wait until s_ddr_read = '1' and s_ddr_busy = '0';
            cycles(2);
            s_cancel <= '1';
            cycles;
            s_cancel <= '0';
            completion(false);
            check_body;
            assert (sint_applied = 0 and sint_acquires = 1) severity failure;
            report "STATE_SERVICE_PASS group3 canceled accepted DDR debt";
            stop;
            wait;
        end if;
        s_mutate <= '1';
        cycles;
        s_mutate <= '0';
        request(true);
        completion(true);
        check_body;
        assert (s_incomplete = '0' and s_machine_held = '0') severity failure;
        request(false);
        completion(true);
        assert (su64_slots(0)(0)(31 downto 0) = 2) report "Repeated save counter did not increment" severity failure;
        s_corrupt <= '1';
        cycles;
        s_corrupt <= '0';
        vint_acquires_before := sint_acquires;
        request(true);
        completion(false);
        assert (sint_acquires = vint_acquires_before and sint_applied = CINT_BODY_BYTES)
            report "Corrupt restore acquired or wrote machine" severity failure;
        check_body;
        if (GINT_CASE_GROUP = 1) then
            report "STATE_SERVICE_PASS group1 full image save/restore,independent CRC,repeated counter,corrupt preflight";
            stop;
            wait;
        end if;
        request(false);
        completion(true);
        s_mutate <= '1';
        cycles;
        s_mutate <= '0';
        s_inject_body_error <= '1';
        request(true);
        completion(false);
        assert (s_incomplete = '1' and s_machine_held = '1') report "Partial restore escaped its machine hold" severity failure;
        s_inject_body_error <= '0';
        request(true);
        completion(true);
        check_body;
        assert (s_incomplete = '0' and s_machine_held = '0') severity failure;
        request(true);
        wait until s_ddr_read = '1' and s_ddr_busy = '0';
        cycles(2);
        s_cancel <= '1';
        cycles;
        s_cancel <= '0';
        completion(false);
        check_body;
        report "STATE_SERVICE_PASS full immutable save/restore, independent CRC, counter update, corrupt preflight, partial apply hold/full retry, canceled DDR debt";
        stop;
        wait;
    end process;
    watchdog : process
    begin
        wait for 600 ms;
        assert (false) report "State service integration timed out" severity failure;
        wait;
    end process;
end architecture;
