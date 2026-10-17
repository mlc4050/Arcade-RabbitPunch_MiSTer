library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_sdram_types.all;
use std.env.all;

entity audio_roms_tb is
end entity;

architecture test of audio_roms_tb is
    type t_counts is array (0 to 2) of natural;
    function byte_value(vint_address : natural; vint_version : natural) return unsigned is
        variable vu27_address, vu27_folded : unsigned(26 downto 0);
    begin
        vu27_address := to_unsigned(vint_address, 27);
        vu27_folded := vu27_address xor shift_right(vu27_address, 8) xor shift_right(vu27_address, 16);
        return vu27_folded(7 downto 0) xor to_unsigned(vint_version * 167, 8);
    end function;
    function burst_value(vu27_address : unsigned(26 downto 0); vint_version : natural) return unsigned is
        variable vu64_data : unsigned(63 downto 0);
    begin
        for vint_byte in 0 to 7 loop
            vu64_data(vint_byte*8+7 downto vint_byte*8) := byte_value(to_integer(vu27_address) + vint_byte, vint_version);
        end loop;
        return vu64_data;
    end function;
    signal s_clk : std_logic := '0';
    signal s_invalidate, s_idle, s_program_request, s_program_ready, s_program_valid : std_logic := '0';
    signal s_sample_request, s_sample_valid : std_logic := '0';
    signal su16_program_address : unsigned(15 downto 0) := (others => '0');
    signal su18_sample_address : unsigned(17 downto 0) := (others => '0');
    signal su8_program_data, su8_sample_data : unsigned(7 downto 0);
    signal su3_requests, su3_ready, su3_valid : unsigned(2 downto 0) := "000";
    signal su27_addresses : t_sdram_addresses;
    signal su64_data : t_sdram_read_data;
    signal sint_fetches : t_counts := (others => 0);
    signal sint_version : natural range 0 to 1 := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    dut : entity work.rabbitpunch_audio_roms
        port map (
            i_clk => s_clk,
            i_invalidate => s_invalidate,
            o_idle => s_idle,
            i_program_request => s_program_request,
            o_program_ready => s_program_ready,
            iu16_program_address => su16_program_address,
            o_program_response_valid => s_program_valid,
            ou8_program_data => su8_program_data,
            i_sample_request => s_sample_request,
            iu18_sample_address => su18_sample_address,
            o_sample_valid => s_sample_valid,
            ou8_sample_data => su8_sample_data,
            ou3_backend_requests => su3_requests,
            iu3_backend_ready => su3_ready,
            ou27_backend_byte_addresses => su27_addresses,
            iu3_backend_response_valid => su3_valid,
            iu64_backend_read_data => su64_data
        );
    backend : process(s_clk)
        variable vu3_pending : unsigned(2 downto 0) := "000";
        variable v_delays : t_counts := (others => 0);
        variable v_words : t_sdram_read_data;
        variable vint_clock, vint_address : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            su3_ready <= "000";
            su3_valid <= "000";
            assert (su3_requests(2) = '0') report "Audio ROMs used the reserved cache port" severity failure;
            for vint_client in 0 to 1 loop
                if (vu3_pending(vint_client) = '1') then
                    if (v_delays(vint_client) = 0) then
                        su3_valid(vint_client) <= '1';
                        su64_data(vint_client) <= v_words(vint_client);
                        vu3_pending(vint_client) := '0';
                    else
                        v_delays(vint_client) := v_delays(vint_client) - 1;
                    end if;
                elsif (vint_clock mod 5 > vint_client) then
                    su3_ready(vint_client) <= '1';
                end if;
                if (su3_requests(vint_client) = '1') then
                    assert (vu3_pending(vint_client) = '0' and su3_ready(vint_client) = '1')
                        report "Audio ROM backend lost request credit" severity failure;
                    vint_address := to_integer(su27_addresses(vint_client));
                    assert (vint_address mod 8 = 0) report "Audio burst address was not aligned" severity failure;
                    if (vint_client = 0) then
                        assert (vint_address >= ROM_AUDIOCPU_BASE and vint_address < ROM_AUDIOCPU_BASE + ROM_AUDIOCPU_SIZE)
                            report "Sound CPU ROM mapped outside its image region" severity failure;
                    else
                        assert (vint_address >= ROM_UPD_BASE and vint_address < ROM_UPD_BASE + ROM_UPD_SIZE)
                            report "Sample ROM mapped outside its image region" severity failure;
                    end if;
                    v_words(vint_client) := burst_value(su27_addresses(vint_client), sint_version);
                    v_delays(vint_client) := 23 + vint_client * 7;
                    vu3_pending(vint_client) := '1';
                    su3_ready(vint_client) <= '0';
                    sint_fetches(vint_client) <= sint_fetches(vint_client) + 1;
                end if;
            end loop;
        end if;
    end process;
    monitor : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_sample_valid = '1') then
                assert (s_sample_request = '1' and su8_sample_data = byte_value(ROM_UPD_BASE + to_integer(su18_sample_address), sint_version))
                    report "Sample ROM exposed stale data after address/bank change" severity failure;
            end if;
        end if;
    end process;
    stimulus : process
        variable v_before : t_counts;
        variable v_program_seen : boolean;
        procedure program_read(constant vint_address : natural) is
        begin
            wait until falling_edge(s_clk);
            while (s_program_ready /= '1') loop
                wait until falling_edge(s_clk);
            end loop;
            su16_program_address <= to_unsigned(vint_address, 16);
            s_program_request <= '1';
            wait until falling_edge(s_clk);
            s_program_request <= '0';
            su16_program_address <= x"FFFF";
            if (s_program_valid /= '1') then
                wait until s_program_valid = '1' for 100 us;
            end if;
            assert (s_program_valid = '1' and su8_program_data = byte_value(ROM_AUDIOCPU_BASE + vint_address, sint_version))
                report "Sound program byte/latching mismatch" severity failure;
            wait until falling_edge(s_clk);
        end procedure;
        procedure sample_read(constant vint_address : natural) is
        begin
            wait until falling_edge(s_clk);
            su18_sample_address <= to_unsigned(vint_address, 18);
            s_sample_request <= '1';
            wait until falling_edge(s_clk);
            if (s_sample_valid /= '1') then
                wait until s_sample_valid = '1' for 100 us;
            end if;
            assert (s_sample_valid = '1' and su8_sample_data = byte_value(ROM_UPD_BASE + vint_address, sint_version))
                report "Sample byte/cache lane mismatch" severity failure;
            wait until falling_edge(s_clk);
        end procedure;
        procedure drain is
        begin
            if (s_idle /= '1') then
                wait until s_idle = '1' for 100 us;
            end if;
            assert (s_idle = '1') report "Audio ROM frontend failed to drain" severity failure;
            wait until falling_edge(s_clk);
        end procedure;
    begin
        wait for 100 ns;
        for vint_lane in 0 to 7 loop
            program_read(16#1230# + vint_lane);
            sample_read(16#0128# + vint_lane);
        end loop;
        assert (sint_fetches(0) = 1 and sint_fetches(1) = 1)
            report "Audio sequential byte reads did not reuse one burst per client" severity failure;
        program_read(16#FFFF#);
        sample_read(16#1FFFF#);
        sample_read(16#20000#);
        sample_read(16#3FFFF#);
        wait until falling_edge(s_clk);
        su16_program_address <= x"4050";
        s_program_request <= '1';
        su18_sample_address <= to_unsigned(16#1050#, 18);
        wait until falling_edge(s_clk);
        s_program_request <= '0';
        su16_program_address <= x"0000";
        v_program_seen := false;
        for vint_cycle in 1 to 1000 loop
            wait until falling_edge(s_clk);
            if (s_program_valid = '1') then
                assert (su8_program_data = byte_value(ROM_AUDIOCPU_BASE + 16#4050#, sint_version))
                    report "Concurrent sound program miss data changed" severity failure;
                v_program_seen := true;
            end if;
            exit when v_program_seen and s_sample_valid = '1';
        end loop;
        assert (v_program_seen and s_sample_valid = '1') report "Concurrent audio clients stalled" severity failure;
        v_before := sint_fetches;
        wait until falling_edge(s_clk);
        su18_sample_address <= to_unsigned(16#0080#, 18);
        wait until rising_edge(s_clk) and su3_requests(1) = '1' for 100 us;
        assert (su3_requests(1) = '1') report "Sample bank-race setup did not miss" severity failure;
        wait until falling_edge(s_clk);
        su18_sample_address <= to_unsigned(16#20083#, 18);
        wait until s_sample_valid = '1' for 100 us;
        assert (s_sample_valid = '1' and sint_fetches(1) = v_before(1) + 2)
            report "Sample bank change did not discard stale miss response" severity failure;
        wait until falling_edge(s_clk);
        su18_sample_address <= to_unsigned(16#00A0#, 18);
        wait until rising_edge(s_clk) and su3_requests(1) = '1' for 100 us;
        assert (su3_requests(1) = '1') report "Sample withdrawal setup did not miss" severity failure;
        wait until falling_edge(s_clk);
        s_sample_request <= '0';
        drain;
        v_before := sint_fetches;
        sample_read(16#00A0#);
        assert (sint_fetches = v_before) report "Drained sample miss was canceled on request withdrawal" severity failure;
        wait until falling_edge(s_clk);
        s_sample_request <= '0';
        drain;
        v_before := sint_fetches;
        s_invalidate <= '1';
        wait until falling_edge(s_clk);
        s_invalidate <= '0';
        sint_version <= 1;
        program_read(16#4050#);
        sample_read(16#00A0#);
        assert (sint_fetches(0) = v_before(0) + 1 and sint_fetches(1) = v_before(1) + 1)
            report "Image invalidation retained old audio cache entries" severity failure;
        wait until falling_edge(s_clk);
        s_sample_request <= '0';
        drain;
        report "AUDIO_ROMS_PASS byte_lanes=8 clients=2 bank_race=checked withdrawal_drain=checked image_invalidation=checked";
        finish;
        wait;
    end process;
    process
    begin
        wait for 2 ms;
        assert false report "Audio ROM frontend timeout" severity failure;
    end process;
end architecture;
