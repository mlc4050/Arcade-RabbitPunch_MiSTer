library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_sdram_types.all;
use work.rabbitpunch_layout.all;
use std.env.all;

entity audio_sdram_tb is
end entity;

architecture test of audio_sdram_tb is
    component sdram_chip_model_wide is
        port (
            clk : in std_logic;
            SDRAM_DQ : inout unsigned(15 downto 0);
            SDRAM_A : in unsigned(12 downto 0);
            SDRAM_BA : in unsigned(1 downto 0);
            SDRAM_nCS : in std_logic;
            SDRAM_nWE : in std_logic;
            SDRAM_nRAS : in std_logic;
            SDRAM_nCAS : in std_logic
        );
    end component;
    type t_program is array (0 to 255) of unsigned(7 downto 0);
    constant PROGRAM : t_program := (
        0 => x"31", 1 => x"FF", 2 => x"FF", 3 => x"3E", 4 => x"14",
        5 => x"32", 6 => x"00", 7 => x"F0", 8 => x"AF", 9 => x"32",
        10 => x"01", 11 => x"F0", 12 => x"3A", 13 => x"01", 14 => x"F0",
        15 => x"E6", 16 => x"80", 17 => x"FE", 18 => x"80",
        19 => x"C2", 20 => x"FF", 21 => x"00", 22 => x"ED", 23 => x"56",
        24 => x"FB", 25 => x"76", 26 => x"C3", 27 => x"19", 28 => x"00",
        16#38# => x"3A", 16#39# => x"00", 16#3A# => x"F2",
        16#3B# => x"32", 16#3C# => x"00", 16#3D# => x"F8",
        16#3E# => x"E6", 16#3F# => x"01", 16#40# => x"F6", 16#41# => x"80",
        16#42# => x"32", 16#43# => x"00", 16#44# => x"F4", 16#45# => x"AF",
        16#46# => x"32", 16#47# => x"00", 16#48# => x"F6", 16#49# => x"FB",
        16#4A# => x"ED", 16#4B# => x"4D", 255 => x"76", others => x"00");
    function burst_pattern(vint_address : natural) return unsigned is
        variable vu64_data : unsigned(63 downto 0);
        variable vu27_address, vu27_folded : unsigned(26 downto 0);
    begin
        for vint_byte in 0 to 7 loop
            vu27_address := to_unsigned(vint_address + vint_byte, 27);
            vu27_folded := vu27_address xor shift_right(vu27_address, 8) xor shift_right(vu27_address, 16);
            vu64_data(vint_byte*8+7 downto vint_byte*8) := vu27_folded(7 downto 0);
        end loop;
        return vu64_data;
    end function;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_pause, s_paused, s_send, s_pending, s_ack : std_logic := '0';
    signal s_enable, s_half_enable, s_rom_request, s_rom_reply, s_rom_ready : std_logic := '0';
    signal s_view, s_debug_request, s_debug_write, s_sample : std_logic := '0';
    signal su16_rom_address, su16_debug_address : unsigned(15 downto 0);
    signal su8_rom_data, su8_debug_data, su8_view_data : unsigned(7 downto 0);
    signal su8_command : unsigned(7 downto 0) := x"42";
    signal s_adpcm_enable, s_adpcm_rom_request, s_adpcm_rom_valid, s_adpcm_busy : std_logic := '0';
    signal su18_adpcm_rom_address : unsigned(17 downto 0);
    signal su8_adpcm_rom_data : unsigned(7 downto 0);
    signal su9_adpcm_pcm : unsigned(8 downto 0);
    signal sint_adpcm_divider : natural range 0 to 74 := 0;
    signal s_initialize : std_logic := '1';
    signal s_initialized, s_transport_idle : std_logic;
    signal s_invalidate : std_logic := '0';
    signal s_backend_request : std_logic;
    signal su27_backend_address : unsigned(26 downto 0);
    signal s_main_request, s_main_ready, s_main_valid : std_logic := '0';
    signal su27_main_address : unsigned(26 downto 0) := (others => '0');
    signal su64_main_data : unsigned(63 downto 0);
    signal s_main_run, s_traffic_run : std_logic := '0';
    signal su2_traffic_requests : unsigned(1 downto 0) := "00";
    signal su3_sdram_requests, su3_sdram_ready, su3_sdram_valid : unsigned(2 downto 0);
    signal su27_priority_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su27_sdram_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su64_sdram_data : t_sdram_read_data;
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip_select, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_main_reads, sint_priority_reads : natural := 0;
    signal sint_max_program_cycles, sint_max_sample_cycles : natural := 0;
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_acks, sint_writes, sint_samples : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_adpcm_enable <= '1' when sint_adpcm_divider = 74 else '0';
    s_half_enable <= '1' when sint_divider = 23 else '0';
    process(s_clk)
        variable v_previous_sample : std_logic := '0';
    begin
        if (rising_edge(s_clk)) then
            if (sint_adpcm_divider = 74) then
                sint_adpcm_divider <= 0;
            else
                sint_adpcm_divider <= sint_adpcm_divider + 1;
            end if;
            if (sint_divider = 23) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            if (s_ack = '1') then
                s_pending <= '0';
                sint_acks <= sint_acks + 1;
            end if;
            if (s_send = '1') then
                assert (s_pending = '0') report "Synthetic main board overwrote a pending command" severity failure;
                s_pending <= '1';
            end if;
            if (s_debug_request = '1' and s_debug_write = '1' and su16_debug_address = x"F800") then
                assert (su8_debug_data = su8_command) report "Sound interrupt handler stored wrong command" severity failure;
                sint_writes <= sint_writes + 1;
            end if;
            if (s_sample = '1' and v_previous_sample = '0') then
                sint_samples <= sint_samples + 1;
            end if;
            v_previous_sample := s_sample;
        end if;
    end process;
    board : entity work.rabbitpunch_audio
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_cpu_enable => s_enable,
            i_ym_enable => s_enable,
            i_ym_half_enable => s_half_enable,
            i_adpcm_enable => s_adpcm_enable,
            i_pause => s_pause,
            o_paused => s_paused,
            iu8_command => su8_command,
            i_command_pending => s_pending,
            o_command_read => s_ack,
            o_rom_request => s_rom_request,
            ou16_rom_address => su16_rom_address,
            i_rom_ready => s_rom_ready,
            i_rom_response_valid => s_rom_reply,
            iu8_rom_response_data => su8_rom_data,
            o_adpcm_rom_request => s_adpcm_rom_request,
            ou18_adpcm_rom_address => su18_adpcm_rom_address,
            i_adpcm_rom_valid => s_adpcm_rom_valid,
            iu8_adpcm_rom_data => su8_adpcm_rom_data,
            ou9_adpcm_pcm => su9_adpcm_pcm,
            o_adpcm_busy => s_adpcm_busy,
            ou16_left_pcm => open,
            ou16_right_pcm => open,
            o_sample_marker => s_sample,
            i_view_enable => s_view,
            iu11_view_address => to_unsigned(0, 11),
            ou8_view_data => su8_view_data,
            o_debug_request => s_debug_request,
            o_debug_write => s_debug_write,
            ou16_debug_address => su16_debug_address,
            ou8_debug_data => su8_debug_data
        );
    audio_rom_transport : entity work.rabbitpunch_audio_rom_transport
        port map (
            i_clk => s_clk,
            i_invalidate => s_invalidate,
            o_idle => s_transport_idle,
            i_program_request => s_rom_request,
            o_program_ready => s_rom_ready,
            iu16_program_address => su16_rom_address,
            o_program_response_valid => s_rom_reply,
            ou8_program_data => su8_rom_data,
            i_sample_request => s_adpcm_rom_request,
            iu18_sample_address => su18_adpcm_rom_address,
            o_sample_valid => s_adpcm_rom_valid,
            ou8_sample_data => su8_adpcm_rom_data,
            i_main_request => s_main_request,
            o_main_ready => s_main_ready,
            iu27_main_byte_address => su27_main_address,
            o_main_response_valid => s_main_valid,
            ou64_main_read_data => su64_main_data,
            o_backend_request => s_backend_request,
            ou27_backend_byte_address => su27_backend_address,
            i_backend_ready => su3_sdram_ready(2),
            i_backend_response_valid => su3_sdram_valid(2),
            iu64_backend_read_data => su64_sdram_data(2)
        );
    su3_sdram_requests(2) <= s_backend_request;
    su3_sdram_requests(1 downto 0) <= su2_traffic_requests;
    su27_sdram_addresses(0) <= su27_priority_addresses(0);
    su27_sdram_addresses(1) <= su27_priority_addresses(1);
    su27_sdram_addresses(2) <= su27_backend_address;
    memory : entity work.rabbitpunch_sdram
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            o_initialized => s_initialized,
            iu3_requests => su3_sdram_requests,
            ou3_ready => su3_sdram_ready,
            iu3_writes => "000",
            iu27_byte_addresses => su27_sdram_addresses,
            iu16_write_data => (others => (others => '0')),
            iu2_byte_enables => (others => "00"),
            ou3_response_valid => su3_sdram_valid,
            ou64_read_data => su64_sdram_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_sdram_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_chip_select,
            o_sdram_write_n => s_write_n,
            o_sdram_row_n => s_row_n,
            o_sdram_column_n => s_column_n,
            o_sdram_clock_enable => s_cke
        );
    chip : sdram_chip_model_wide
        port map (
            clk => s_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_sdram_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_chip_select,
            SDRAM_nWE => s_write_n,
            SDRAM_nRAS => s_row_n,
            SDRAM_nCAS => s_column_n
        );
    check_command_pins : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_initialized = '1' and not (s_row_n = '1' and s_column_n = '1' and s_write_n = '1')) then
                for vint_bit in su13_sdram_address'range loop
                    assert (su13_sdram_address(vint_bit) = '0' or su13_sdram_address(vint_bit) = '1')
                        report "Unknown physical SDRAM command address" severity failure;
                end loop;
                for vint_bit in su2_bank'range loop
                    assert (su2_bank(vint_bit) = '0' or su2_bank(vint_bit) = '1')
                        report "Unknown physical SDRAM bank" severity failure;
                end loop;
            end if;
        end if;
    end process;
    main_traffic : process(s_clk)
        variable v_pending : boolean := false;
        variable vint_index : natural range 0 to 255 := 0;
        variable vu64_expected : unsigned(63 downto 0);
    begin
        if (rising_edge(s_clk)) then
            s_main_request <= '0';
            if (s_main_valid = '1') then
                assert (v_pending and su64_main_data = vu64_expected) report "Shared-port main burst response mismatch actual=" & to_hstring(su64_main_data) & " expected=" & to_hstring(vu64_expected) & " pending=" & boolean'image(v_pending) & " address=" & to_hstring(su27_main_address) & " completed=" & integer'image(sint_main_reads) severity failure;
                v_pending := false;
                sint_main_reads <= sint_main_reads + 1;
            end if;
            if (s_main_run = '1' and not v_pending and s_main_ready = '1') then
                su27_main_address <= to_unsigned(16#10000# + vint_index*8, 27);
                vu64_expected := burst_pattern(16#10000# + vint_index*8);
                s_main_request <= '1';
                v_pending := true;
                if (vint_index = 255) then
                    vint_index := 0;
                else
                    vint_index := vint_index + 1;
                end if;
            end if;
        end if;
    end process;
    priority_traffic : process(s_clk)
        type t_indices is array (0 to 1) of natural range 0 to 63;
        type t_periods is array (0 to 1) of positive;
        constant PERIODS : t_periods := (128, 160);
        constant BASES : t_periods := (16#150000#, 16#50000#);
        variable v_indices : t_indices := (others => 0);
        variable vu2_pending : unsigned(1 downto 0) := "00";
        variable v_expected : t_sdram_read_data;
        variable vint_clock, vint_completions : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            vint_completions := 0;
            su2_traffic_requests <= "00";
            for vint_client in 0 to 1 loop
                if (su3_sdram_valid(vint_client) = '1') then
                    assert (vu2_pending(vint_client) = '1' and su64_sdram_data(vint_client) = v_expected(vint_client))
                        report "High-priority synthetic burst data/ownership mismatch" severity failure;
                    vu2_pending(vint_client) := '0';
                    vint_completions := vint_completions + 1;
                end if;
                if (s_traffic_run = '1' and vu2_pending(vint_client) = '0' and su3_sdram_ready(vint_client) = '1' and
                    vint_clock mod PERIODS(vint_client) = 0) then
                    su27_priority_addresses(vint_client) <= to_unsigned(BASES(vint_client) + v_indices(vint_client)*8, 27);
                    v_expected(vint_client) := burst_pattern(BASES(vint_client) + v_indices(vint_client)*8);
                    su2_traffic_requests(vint_client) <= '1';
                    vu2_pending(vint_client) := '1';
                    if (v_indices(vint_client) = 63) then
                        v_indices(vint_client) := 0;
                    else
                        v_indices(vint_client) := v_indices(vint_client) + 1;
                    end if;
                end if;
            end loop;
            sint_priority_reads <= sint_priority_reads + vint_completions;
        end if;
    end process;
    measure_latency : process(s_clk)
        variable vint_clock, vint_program_start, vint_sample_start : natural := 0;
        variable v_program_pending, v_sample_pending, v_sample_selected : boolean := false;
        variable vu18_sample_address : unsigned(17 downto 0);
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            if (s_rom_reply = '1') then
                assert (v_program_pending) report "Unowned audio program response" severity failure;
                if (vint_clock - vint_program_start > sint_max_program_cycles) then
                    sint_max_program_cycles <= vint_clock - vint_program_start;
                end if;
                v_program_pending := false;
            end if;
            if (s_rom_request = '1' and s_rom_ready = '1') then
                assert (not v_program_pending) report "Overlapping audio program requests" severity failure;
                vint_program_start := vint_clock;
                v_program_pending := true;
            end if;
            if (s_adpcm_rom_request = '0') then
                v_sample_selected := false;
                v_sample_pending := false;
            elsif (not v_sample_selected or vu18_sample_address /= su18_adpcm_rom_address) then
                vu18_sample_address := su18_adpcm_rom_address;
                v_sample_selected := true;
                v_sample_pending := true;
                vint_sample_start := vint_clock;
            end if;
            if (v_sample_pending and s_adpcm_rom_valid = '1') then
                if (vint_clock - vint_sample_start > sint_max_sample_cycles) then
                    sint_max_sample_cycles <= vint_clock - vint_sample_start;
                end if;
                v_sample_pending := false;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_samples_before : natural;
        procedure command(constant vu8_data : unsigned(7 downto 0); constant vint_count : positive) is
        begin
            wait until falling_edge(s_clk);
            su8_command <= vu8_data;
            s_send <= '1';
            wait until falling_edge(s_clk);
            s_send <= '0';
            wait until sint_writes = vint_count for 100 us;
            assert (sint_writes = vint_count and sint_acks = vint_count and s_pending = '0')
                report "Sound command interrupt or acknowledgement failed" severity failure;
            wait until s_adpcm_busy = '1' for 100 us;
            assert (s_adpcm_busy = '1') report "Sound CPU did not trigger ADPCM through its bus" severity failure;
            wait until su9_adpcm_pcm /= 0 for 3 ms;
            assert (s_adpcm_busy = '1' and su9_adpcm_pcm /= 0 and su18_adpcm_rom_address(17) = vu8_data(0))
                report "Audio subsystem selected wrong sample bank or failed to decode" severity failure;
            wait until falling_edge(s_clk);
            s_pause <= '1';
            wait until s_paused = '1' for 10 us;
            assert (s_paused = '1') report "Sound board pause did not drain" severity failure;
            wait until falling_edge(s_clk);
            s_view <= '1';
            wait until falling_edge(s_clk);
            assert (su8_view_data = vu8_data) report "Sound handler native RAM inspection mismatch" severity failure;
            s_view <= '0';
            vint_samples_before := sint_samples;
            wait until s_adpcm_busy = '0' for 3 ms;
            assert (s_adpcm_busy = '0') report "ADPCM stopped progressing during CPU pause" severity failure;
            wait for 40 us;
            assert (sint_samples >= vint_samples_before + 2 and sint_writes = vint_count)
                report "Sound pause stopped YM cadence or allowed CPU writes" severity failure;
            wait until falling_edge(s_clk);
            s_pause <= '0';
        end procedure;
    begin
        wait for 2 us;
        wait until falling_edge(s_clk);
        s_initialize <= '0';
        wait until s_initialized = '1' for 500 us;
        assert (s_initialized = '1') report "Audio SDRAM did not initialize" severity failure;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        s_main_run <= '1';
        s_traffic_run <= '1';
        wait until s_debug_request = '1' and su16_debug_address = 25 for 100 us;
        assert (s_debug_request = '1' and su16_debug_address = 25) report "Sound CPU did not pass YM busy readback and reach EI/HALT" severity failure;
        command(x"00", 1);
        command(x"01", 2);
        wait until falling_edge(s_clk);
        s_pause <= '1';
        s_main_run <= '0';
        s_traffic_run <= '0';
        if (s_paused /= '1') then
            wait until s_paused = '1' for 100 us;
        end if;
        if (s_transport_idle /= '1' or su3_sdram_ready /= "111") then
            wait until s_transport_idle = '1' and su3_sdram_ready = "111" for 100 us;
        end if;
        assert (s_paused = '1' and s_transport_idle = '1' and su3_sdram_ready = "111" and
            sint_main_reads > 20 and sint_priority_reads > 20)
            report "Audio SDRAM traffic did not overlap and drain" severity failure;
        wait until falling_edge(s_clk);
        s_invalidate <= '1';
        wait until falling_edge(s_clk);
        s_invalidate <= '0';
        report "AUDIO_SDRAM_PASS commands=2 sample_banks=2 main_bursts=" & integer'image(sint_main_reads) &
            " priority_bursts=" & integer'image(sint_priority_reads) &
            " max_program_cycles=" & integer'image(sint_max_program_cycles) &
            " max_sample_cycles=" & integer'image(sint_max_sample_cycles);
        finish;
        wait;
    end process;
    process
    begin
        wait for 8 ms;
        assert false report "Sound board diagnostic timeout" severity failure;
    end process;
end architecture;

