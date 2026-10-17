library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity jt51_baseline_tb is
    generic (GBOOL_USE_WRAPPER : boolean := false);
end entity;

architecture test of jt51_baseline_tb is
    -- Native vendor declaration is isolated to this baseline binding.
    component jt51 is
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen : in std_logic;
            cen_p1 : in std_logic;
            cs_n : in std_logic;
            wr_n : in std_logic;
            a0 : in std_logic;
            din : in unsigned(7 downto 0);
            dout : out unsigned(7 downto 0);
            ct1 : out std_logic;
            ct2 : out std_logic;
            irq_n : out std_logic;
            sample : out std_logic;
            left : out unsigned(15 downto 0);
            right : out unsigned(15 downto 0);
            xleft : out unsigned(15 downto 0);
            xright : out unsigned(15 downto 0)
        );
    end component;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_write_n : std_logic := '1';
    signal s_check_audio : std_logic := '0';
    signal s_register_data : std_logic := '0';
    signal s_enable, s_half_enable, s_irq_n, s_sample : std_logic;
    signal su8_write_data : unsigned(7 downto 0) := (others => '0');
    signal su8_status : unsigned(7 downto 0);
    signal su16_left, su16_right, su16_full_left, su16_full_right : unsigned(15 downto 0);
    signal sint_divider : natural range 0 to 23 := 0;
    signal sint_samples : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 11 or sint_divider = 23 else '0';
    s_half_enable <= '1' when sint_divider = 23 else '0';
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 23) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
        end if;
    end process;
    native_chip : if not GBOOL_USE_WRAPPER generate
        chip : jt51
            port map (
                rst => s_reset,
                clk => s_clk,
                cen => s_enable,
                cen_p1 => s_half_enable,
                cs_n => '0',
                wr_n => s_write_n,
                a0 => s_register_data,
                din => su8_write_data,
                dout => su8_status,
                ct1 => open,
                ct2 => open,
                irq_n => s_irq_n,
                sample => s_sample,
                left => su16_left,
                right => su16_right,
                xleft => su16_full_left,
                xright => su16_full_right
            );
    end generate;
    wrapped_chip : if GBOOL_USE_WRAPPER generate
        signal s_interrupt : std_logic;
    begin
        s_irq_n <= not s_interrupt;
        chip : entity work.rabbitpunch_ym2151
            port map (
                i_clk => s_clk,
                i_reset => s_reset,
                i_chip_enable => s_enable,
                i_half_chip_enable => s_half_enable,
                i_chip_select => '1',
                i_write => not s_write_n,
                i_data_register => s_register_data,
                iu8_write_data => su8_write_data,
                ou8_status => su8_status,
                o_interrupt => s_interrupt,
                o_sample_marker => s_sample,
                ou16_left_pcm => su16_left,
                ou16_right_pcm => su16_right,
                ou16_full_left_pcm => su16_full_left,
                ou16_full_right_pcm => su16_full_right
            );
    end generate;
    samples : process(s_clk)
        variable v_previous_sample : std_logic := '0';
        variable vint_clock, vint_last_sample, vint_samples : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            vint_clock := vint_clock + 1;
            if (s_reset = '1') then
                vint_samples := 0;
                vint_last_sample := 0;
            elsif (s_sample = '1' and v_previous_sample = '0') then
                if (vint_samples > 0) then
                    assert (vint_clock - vint_last_sample = 768)
                        report "YM2151 sample cadence differs from clock/64" severity failure;
                end if;
                if (s_check_audio = '1') then
                    assert (su16_left = 0 and su16_right = 0 and su16_full_left = 0 and su16_full_right = 0)
                        report "Explicitly muted YM2151 is not silent" severity failure;
                end if;
                vint_last_sample := vint_clock;
                vint_samples := vint_samples + 1;
            end if;
            v_previous_sample := s_sample;
            sint_samples <= vint_samples;
        end if;
    end process;
    stimulus : process
        variable v_timer_start : time;
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure write_register(vint_address, vint_data : natural) is
        begin
            s_register_data <= '0';
            su8_write_data <= to_unsigned(vint_address, 8);
            s_write_n <= '0';
            cycles(24);
            s_write_n <= '1';
            cycles(12);
            s_register_data <= '1';
            su8_write_data <= to_unsigned(vint_data, 8);
            s_write_n <= '0';
            cycles(24);
            s_write_n <= '1';
            cycles(12);
            if (su8_status(7) /= '0') then
                wait until su8_status(7) = '0' for 32 us;
            end if;
            assert (su8_status(7) = '0') report "JT51 busy flag failed to clear" severity failure;
            cycles(1);
        end procedure;
    begin
        cycles(3840);
        s_reset <= '0';
        cycles(1536);
        assert (s_irq_n = '1' and su8_status(1 downto 0) = 0)
            report "JT51 timer status did not reset" severity failure;
        -- FM parameter storage is initialized by software, not by assuming RAM zeros.
        for vint_channel in 0 to 7 loop
            write_register(16#20# + vint_channel, 0);
            write_register(16#08#, vint_channel);
        end loop;
        cycles(3072);
        s_check_audio <= '1';
        write_register(16#10#, 255);
        write_register(16#11#, 3);
        write_register(16#14#, 5);
        if (s_irq_n /= '0') then
            wait until s_irq_n = '0' for 70 us;
        end if;
        assert (s_irq_n = '0' and su8_status(0) = '1') report "Timer A did not interrupt" severity failure;
        write_register(16#14#, 16#10#);
        cycles(24);
        assert (s_irq_n = '1' and su8_status(0) = '0') report "Timer A flag did not clear" severity failure;
        write_register(16#12#, 255);
        write_register(16#14#, 16#0A#);
        v_timer_start := now;
        if (s_irq_n /= '0') then
            wait until s_irq_n = '0' for 600 us;
        end if;
        assert (s_irq_n = '0' and su8_status(1) = '1' and su8_status(0) = '0')
            report "Timer B did not interrupt independently" severity failure;
        -- The first overflow has free-running prescaler phase. Measure a full
        -- period between overflows while keeping the timer running across clear.
        v_timer_start := now;
        write_register(16#14#, 16#2A#);
        assert (s_irq_n = '1' and su8_status(1) = '0')
            report "Running timer B flag did not clear" severity failure;
        wait until s_irq_n = '0' for 600 us;
        assert (s_irq_n = '0' and now - v_timer_start > 255 us and now - v_timer_start < 257 us)
            report "Timer B full period differs from 4 MHz clock/1024" severity failure;
        write_register(16#14#, 16#20#);
        cycles(24);
        assert (s_irq_n = '1' and su8_status(1 downto 0) = 0 and sint_samples > 10)
            report "JT51 timers/audio cadence did not complete" severity failure;
        report "JT51_BASELINE_PASS samples=" & integer'image(sint_samples);
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "JT51 baseline timeout" severity failure;
    end process;
end architecture;
