-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity t80_capture_tb is
    generic (
        GINT_INTERRUPT_MODE : natural range 0 to 2 := 1
    );
end entity;

architecture test of t80_capture_tb is
    type t_bytes is array(natural range <>) of unsigned(7 downto 0);
    type t_bus_event is record
        su16_address : unsigned(15 downto 0);
        su8_data : unsigned(7 downto 0);
    end record;
    type t_bus_trace is array(0 to 399) of t_bus_event;
    type t_clock_event is record
        su256_state : unsigned(255 downto 0);
        su16_address : unsigned(15 downto 0);
        su13_control : unsigned(12 downto 0);
        su8_data : unsigned(7 downto 0);
    end record;
    type t_clock_trace is array(0 to 511) of t_clock_event;
    function F_IM_OPCODE return unsigned is
    begin
        if (GINT_INTERRUPT_MODE = 0) then
            return to_unsigned(16#46#, 8);
        elsif (GINT_INTERRUPT_MODE = 1) then
            return to_unsigned(16#56#, 8);
        else
            return to_unsigned(16#5E#, 8);
        end if;
    end function;
    constant CU8_BOOT : t_bytes := (
        x"F3", x"31", x"00", x"00", x"ED", F_IM_OPCODE,
        x"3E", x"3C", x"ED", x"47", x"3E", x"80", x"ED", x"4F",
        x"01", x"22", x"33", x"11", x"44", x"55", x"21", x"66", x"77",
        x"DD", x"21", x"88", x"99", x"FD", x"21", x"AA", x"BB", x"3E", x"11",
        x"08", x"D9", x"3E", x"CC", x"01", x"DD", x"EE", x"11", x"34", x"12",
        x"21", x"78", x"56", x"D9", x"08"
    );
    constant CU8_LOOP : t_bytes := (
        x"FB", x"3C", x"03", x"13", x"23", x"DD", x"23", x"FD", x"23",
        x"32", x"00", x"80", x"ED", x"43", x"02", x"80", x"ED", x"53", x"04", x"80",
        x"22", x"06", x"80", x"DD", x"22", x"08", x"80", x"FD", x"22", x"0A", x"80",
        x"08", x"D9", x"3D", x"0B", x"32", x"10", x"80", x"ED", x"43", x"12", x"80",
        x"D9", x"08", x"ED", x"5F", x"32", x"14", x"80", x"ED", x"57", x"32", x"15", x"80",
        x"C3", x"01", x"01"
    );
    constant CU8_ISR : t_bytes := (x"F5", x"3A", x"00", x"90", x"3C", x"32", x"00", x"90", x"F1", x"FB", x"ED", x"4D");
    constant CU8_HALT : t_bytes := (x"FB", x"76", x"3C", x"32", x"00", x"80", x"C3", x"01", x"02");
    constant CU8_EI : t_bytes := (x"FB", x"32", x"00", x"80", x"76", x"C3", x"04", x"03");
    signal s_clk : std_logic := '0';
    signal s_reset_n : std_logic := '0';
    signal su2_mode, su2_divider, su2_saved_divider : unsigned(1 downto 0) := (others => '0');
    signal su3_wait_phase, su3_saved_wait : unsigned(2 downto 0) := (others => '0');
    signal s_enable, s_wait_n, s_irq, s_force_irq, s_bus_drained : std_logic := '0';
    signal s_fetch_n, s_memory_n, s_io_n, s_read_n, s_write_n, s_refresh_n, s_halted_n : std_logic;
    signal s_request, s_pending, s_held, s_resume, s_state_write, s_clean : std_logic := '0';
    signal s_cancel : std_logic := '0';
    signal su3_machine_cycle, su3_clock_phase : unsigned(2 downto 0);
    signal su16_address, su16_gold_address : unsigned(15 downto 0);
    signal su8_read, su8_write, su8_gold_read, su8_gold_write : unsigned(7 downto 0);
    signal su256_state, su256_load : unsigned(255 downto 0) := (others => '0');
    signal s_gold_fetch_n, s_gold_memory_n, s_gold_io_n, s_gold_read_n, s_gold_write_n, s_gold_refresh_n, s_gold_halted_n : std_logic;
    signal s_compare_original, s_snapshot, s_restore, s_record, s_compare : std_logic := '0';
    signal sint_writes, sint_recorded, sint_compared, sint_irq_writes, sint_original_checks : natural := 0;
    signal su13_control : unsigned(12 downto 0);
    signal su7_control, su7_gold_control : unsigned(6 downto 0);
    signal s_gold_enable : std_logic;
begin
    s_clk <= not s_clk after 5 ns;
    s_enable <= '1' when su2_divider = 0 and s_held = '0' and s_reset_n = '1' else '0';
    s_gold_enable <= s_enable and s_compare_original;
    s_wait_n <= '0' when s_memory_n = '0' and s_read_n = '0' and
        (su3_wait_phase = 1 or su3_wait_phase = 2) else '1';
    su13_control <= s_fetch_n & s_memory_n & s_io_n & s_read_n & s_write_n & s_refresh_n &
        s_halted_n & su3_machine_cycle & su3_clock_phase;
    su7_control <= s_fetch_n & s_memory_n & s_io_n & s_read_n & s_write_n & s_refresh_n & s_halted_n;
    su7_gold_control <= s_gold_fetch_n & s_gold_memory_n & s_gold_io_n & s_gold_read_n &
        s_gold_write_n & s_gold_refresh_n & s_gold_halted_n;
    phase : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_reset_n = '0') then
                su2_divider <= (others => '0');
                su3_wait_phase <= (others => '0');
            elsif (s_restore = '1') then
                su2_divider <= su2_saved_divider;
                su3_wait_phase <= su3_saved_wait;
            elsif (s_held = '0') then
                su2_divider <= su2_divider + 1;
                if (s_enable = '1') then
                    su3_wait_phase <= su3_wait_phase + 1;
                end if;
            end if;
            if (s_snapshot = '1') then
                su2_saved_divider <= su2_divider;
                su3_saved_wait <= su3_wait_phase;
            end if;
        end if;
    end process;
    candidate : entity work.rabbitpunch_t80_capture
        port map (
            i_clk => s_clk,
            i_reset_n => s_reset_n,
            i_clock_enable => s_enable,
            i_wait_n => s_wait_n,
            i_interrupt_n => not s_irq,
            o_opcode_fetch_n => s_fetch_n,
            o_memory_request_n => s_memory_n,
            o_io_request_n => s_io_n,
            o_read_n => s_read_n,
            o_write_n => s_write_n,
            o_refresh_n => s_refresh_n,
            o_halted_n => s_halted_n,
            ou16_address => su16_address,
            iu8_read_data => su8_read,
            ou8_write_data => su8_write,
            i_capture_request => s_request,
            i_cancel => s_cancel,
            i_bus_drained => s_bus_drained,
            o_capture_pending => s_pending,
            o_held => s_held,
            i_resume => s_resume,
            i_state_write => s_state_write,
            iu256_state_data => su256_load,
            ou256_state_data => su256_state,
            o_clean_boundary => s_clean,
            ou3_machine_cycle => su3_machine_cycle,
            ou3_clock_phase => su3_clock_phase
        );
    original : entity work.rabbitpunch_t80
        port map (
            i_clk => s_clk,
            i_reset_n => s_reset_n,
            i_clock_enable => s_gold_enable,
            i_wait_n => s_wait_n,
            i_interrupt_n => not s_irq,
            i_nonmaskable_interrupt_n => '1',
            i_bus_request_n => '1',
            o_opcode_fetch_n => s_gold_fetch_n,
            o_memory_request_n => s_gold_memory_n,
            o_io_request_n => s_gold_io_n,
            o_read_n => s_gold_read_n,
            o_write_n => s_gold_write_n,
            o_refresh_n => s_gold_refresh_n,
            o_halted_n => s_gold_halted_n,
            o_bus_acknowledge_n => open,
            ou16_address => su16_gold_address,
            iu8_read_data => su8_gold_read,
            ou8_write_data => su8_gold_write
        );
    memory : process(s_clk)
        variable vu8_ram, vu8_saved : t_bytes(0 to 65535) := (others => (others => '0'));
        variable vu_bus_trace : t_bus_trace;
        variable v_reset_seen, v_writing, v_irq, v_saved_irq, v_marker, v_saved_marker : boolean := false;
        variable vint_irq_count, vint_saved_irq_count : natural range 0 to 15 := 0;
        variable vint_target : natural;
        variable vu16_write_address : unsigned(15 downto 0);
        variable vu8_write_data : unsigned(7 downto 0);
    begin
        if (rising_edge(s_clk)) then
            if (s_reset_n = '0' and not v_reset_seen) then
                vu8_ram := (others => (others => '0'));
                for vint_byte in CU8_BOOT'range loop
                    vu8_ram(vint_byte) := CU8_BOOT(vint_byte);
                end loop;
                vint_target := 16#100# + 16#100#*to_integer(su2_mode);
                vu8_ram(CU8_BOOT'length) := x"C3";
                vu8_ram(CU8_BOOT'length + 1) := to_unsigned(vint_target mod 256, 8);
                vu8_ram(CU8_BOOT'length + 2) := to_unsigned(vint_target/256, 8);
                for vint_byte in CU8_LOOP'range loop
                    vu8_ram(16#100# + vint_byte) := CU8_LOOP(vint_byte);
                end loop;
                for vint_byte in CU8_HALT'range loop
                    vu8_ram(16#200# + vint_byte) := CU8_HALT(vint_byte);
                end loop;
                for vint_byte in CU8_EI'range loop
                    vu8_ram(16#300# + vint_byte) := CU8_EI(vint_byte);
                end loop;
                for vint_byte in CU8_ISR'range loop
                    vu8_ram(16#38# + vint_byte) := CU8_ISR(vint_byte);
                end loop;
                vu8_ram(16#3CFF#) := x"38";
                vu8_ram(16#3D00#) := x"00";
                v_irq := su2_mode = 2;
                v_marker := false;
                v_writing := false;
                vint_irq_count := 0;
                sint_writes <= 0;
                sint_recorded <= 0;
                sint_compared <= 0;
                sint_irq_writes <= 0;
                v_reset_seen := true;
            elsif (s_reset_n = '1') then
                v_reset_seen := false;
                if (s_force_irq = '1') then
                    v_irq := true;
                end if;
                if (s_fetch_n = '0' and s_io_n = '0') then
                    if (su2_mode = 2) then
                        assert (v_marker) report "Pending IRQ bypassed instruction after EI" severity failure;
                    end if;
                    v_irq := false;
                end if;
                if (s_memory_n = '0' and s_write_n = '0') then
                    v_writing := true;
                    vu16_write_address := su16_address;
                    vu8_write_data := su8_write;
                elsif (v_writing) then
                    v_writing := false;
                    vu8_ram(to_integer(vu16_write_address)) := vu8_write_data;
                    if (vu16_write_address = 16#8000#) then
                        v_marker := true;
                    end if;
                    if (vu16_write_address >= 16#8000# and vu16_write_address <= 16#9000#) then
                        sint_writes <= sint_writes + 1;
                        if (vu16_write_address = 16#9000#) then
                            sint_irq_writes <= sint_irq_writes + 1;
                        end if;
                        if (su2_mode = 0 and vu16_write_address = 16#8015#) then
                            if (vint_irq_count = 15) then
                                vint_irq_count := 0;
                                v_irq := true;
                            else
                                vint_irq_count := vint_irq_count + 1;
                            end if;
                        end if;
                        if (s_record = '1' and sint_recorded < 400) then
                            vu_bus_trace(sint_recorded) := (vu16_write_address, vu8_write_data);
                            sint_recorded <= sint_recorded + 1;
                        end if;
                        if (s_compare = '1' and sint_compared < 1200) then
                            assert (vu_bus_trace(sint_compared mod 400) = t_bus_event'(vu16_write_address, vu8_write_data))
                                report "T80 register/R/WZ continuation differs at write " & integer'image(sint_compared)
                                severity failure;
                            sint_compared <= sint_compared + 1;
                        end if;
                    end if;
                end if;
                if (s_snapshot = '1') then
                    assert (s_held = '1' and not v_writing) severity failure;
                    vu8_saved := vu8_ram;
                    v_saved_irq := v_irq;
                    vint_saved_irq_count := vint_irq_count;
                    v_saved_marker := v_marker;
                end if;
                if (s_restore = '1') then
                    assert (s_held = '1') severity failure;
                    vu8_ram := vu8_saved;
                    v_irq := v_saved_irq;
                    vint_irq_count := vint_saved_irq_count;
                    v_marker := v_saved_marker;
                end if;
            end if;
            if (v_writing) then
                s_bus_drained <= '0';
            else
                s_bus_drained <= '1';
            end if;
            if (v_irq) then
                s_irq <= '1';
            else
                s_irq <= '0';
            end if;
            if (s_fetch_n = '0' and s_io_n = '0') then
                su8_read <= x"FF";
            elsif (not is_x(su16_address)) then
                su8_read <= vu8_ram(to_integer(su16_address));
            end if;
            if (s_gold_fetch_n = '0' and s_gold_io_n = '0') then
                su8_gold_read <= x"FF";
            elsif (not is_x(su16_gold_address)) then
                su8_gold_read <= vu8_ram(to_integer(su16_gold_address));
            end if;
        end if;
    end process;
    original_comparison : process
    begin
        wait until falling_edge(s_clk);
        if (s_compare_original = '1' and s_reset_n = '1') then
            assert (su7_control = su7_gold_control)
                report "State-aware T80 normal bus timing differs from production T80se" severity failure;
            if (s_memory_n = '0' and (s_read_n = '0' or s_write_n = '0' or s_refresh_n = '0')) then
                assert (su16_address = su16_gold_address) report "State-aware T80 normal address differs" severity failure;
            end if;
            if (s_write_n = '0') then
                assert (su8_write = su8_gold_write) report "State-aware T80 normal write differs" severity failure;
            end if;
            sint_original_checks <= sint_original_checks + 1;
        end if;
    end process;
    stimulus : process
        variable vu256_image : unsigned(255 downto 0);
        variable vu_clock_trace : t_clock_trace;
        variable vint_prior : natural;
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait until falling_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure restart(vint_mode : natural) is
        begin
            s_record <= '0';
            s_compare <= '0';
            s_compare_original <= '0';
            s_request <= '0';
            s_cancel <= '0';
            s_resume <= '0';
            s_state_write <= '0';
            s_snapshot <= '0';
            s_restore <= '0';
            s_force_irq <= '0';
            su2_mode <= to_unsigned(vint_mode, 2);
            s_reset_n <= '0';
            cycles(80);
            s_reset_n <= '1';
        end procedure;
        procedure park is
        begin
            s_request <= '1';
            cycles;
            s_request <= '0';
            for vint_wait in 0 to 100000 loop
                cycles;
                exit when (s_held = '1');
            end loop;
            assert (s_held = '1' and s_clean = '1' and s_bus_drained = '1')
                report "T80 did not acquire drained clean fetch" severity failure;
            cycles(2);
        end procedure;
        procedure snapshot is
        begin
            assert (not is_x(su256_state)) report "Unknown T80 state bit" severity failure;
            vu256_image := su256_state;
            s_snapshot <= '1';
            cycles;
            s_snapshot <= '0';
        end procedure;
        procedure resume is
        begin
            s_resume <= '1';
            cycles;
            s_resume <= '0';
            assert (s_held = '0') severity failure;
        end procedure;
        procedure restore is
            variable vu256_probe : unsigned(255 downto 0);
        begin
            vu256_probe := not vu256_image;
            vu256_probe(255 downto 238) := (others => '0');
            s_restore <= '1';
            su256_load <= vu256_probe;
            s_state_write <= '1';
            cycles;
            s_restore <= '0';
            s_state_write <= '0';
            cycles;
            assert (su256_state = vu256_probe) report "T80 image missed a complementary state bit" severity failure;
            s_cancel <= '1';
            cycles;
            s_cancel <= '0';
            assert (s_held = '1') report "Acquisition cancellation released a loaded CPU" severity failure;
            su256_load <= vu256_image;
            s_state_write <= '1';
            cycles;
            s_state_write <= '0';
            cycles;
            assert (su256_state = vu256_image) report "T80 full register/DI image did not reload exactly" severity failure;
        end procedure;
        impure function F_CLOCK_EVENT return t_clock_event is
            variable vu8_data : unsigned(7 downto 0) := (others => '0');
        begin
            if (s_write_n = '0') then
                vu8_data := su8_write;
            end if;
            return (su256_state, su16_address, su13_control, vu8_data);
        end function;
    begin
        restart(0);
        s_compare_original <= '1';
        wait until sint_writes >= 300;
        s_compare_original <= '0';
        wait until s_fetch_n = '0' and s_read_n = '0' and su16_address = 16#120#;
        park;
        snapshot;
        assert (vu256_image(228) = '1' and vu256_image(47) = '1' and
            vu256_image(209 downto 208) = GINT_INTERRUPT_MODE)
            report "T80 fixture missed alternate bank, R high bit or IM: state=" & to_hstring(vu256_image)
            severity failure;
        s_record <= '1';
        resume;
        wait until sint_recorded = 400;
        s_record <= '0';
        for vint_round in 1 to 3 loop
            vint_prior := sint_writes;
            wait until sint_writes >= vint_prior + 1000;
            park;
            restore;
            s_compare <= '1';
            resume;
            wait until sint_compared = 400*vint_round;
            s_compare <= '0';
        end loop;
        assert (sint_irq_writes >= 3 and sint_original_checks > 10000) severity failure;
        wait until s_fetch_n = '0' and s_read_n = '0' and su16_address = 16#105#;
        s_request <= '1';
        cycles;
        s_request <= '0';
        s_cancel <= '1';
        cycles;
        s_cancel <= '0';
        cycles(1000);
        assert (s_held = '0' and s_pending = '0') report "Canceled T80 acquisition later froze CPU" severity failure;
        wait until s_fetch_n = '0' and s_read_n = '0' and su16_address = 16#105#;
        park;
        assert (su256_state(79 downto 64) = 16#107#)
            report "T80 captured inside DD prefix instead of after instruction: PC=" &
            to_hstring(su256_state(79 downto 64)) severity failure;
        resume;
        report "T80_CAPTURE_RUNNING_PASS ordered_writes=1200 R=checked alternate=checked prefix=checked";
        for vint_mode in 1 to 2 loop
            restart(vint_mode);
            if (vint_mode = 1) then
                wait until s_halted_n = '0';
            else
                wait until s_fetch_n = '0' and s_read_n = '0' and su16_address = 16#300#;
            end if;
            park;
            snapshot;
            if (vint_mode = 1) then
                assert (vu256_image(229) = '1') report "HALT not captured" severity failure;
            else
                assert (vu256_image(79 downto 64) = 16#38# and vu256_image(211 downto 210) = 0)
                    report "EI/IRQ capture was not deferred to acknowledged interrupt entry: PC=" &
                    to_hstring(vu256_image(79 downto 64)) & " IFF=" &
                    to_hstring(vu256_image(211 downto 210)) severity failure;
            end if;
            resume;
            for vint_cycle in vu_clock_trace'range loop
                vu_clock_trace(vint_cycle) := F_CLOCK_EVENT;
                cycles;
            end loop;
            for vint_round in 1 to 3 loop
                if (vint_mode = 1) then
                    vint_prior := sint_writes;
                    s_force_irq <= '1';
                    cycles;
                    s_force_irq <= '0';
                    wait until sint_writes >= vint_prior + 2 and s_halted_n = '0';
                end if;
                park;
                restore;
                resume;
                for vint_cycle in vu_clock_trace'range loop
                    assert (F_CLOCK_EVENT = vu_clock_trace(vint_cycle))
                        report "T80 HALT/EI clock continuation differs: mode=" & integer'image(vint_mode) &
                        " cycle=" & integer'image(vint_cycle) severity failure;
                    cycles;
                end loop;
            end loop;
        end loop;
        report "T80_CAPTURE_PASS IM=" & integer'image(GINT_INTERRUPT_MODE) &
            " ordered_writes=1200 halt_clock_checks=1536 pending_EI_clock_checks=1536 normal_original_cycles=" &
            integer'image(sint_original_checks);
        finish;
        wait;
    end process;
    watchdog : process
    begin
        wait for 50 ms;
        assert (false) report "T80 capture test timed out" severity failure;
        wait;
    end process;
end architecture;
