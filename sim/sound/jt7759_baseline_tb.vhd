library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity jt7759_baseline_tb is
    generic (GBOOL_USE_WRAPPER : boolean := false);
end entity;

architecture test of jt7759_baseline_tb is
    component jt7759 is
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen : in std_logic;
            stn : in std_logic;
            cs : in std_logic;
            mdn : in std_logic;
            busyn : out std_logic;
            wrn : in std_logic;
            din : in unsigned(7 downto 0);
            drqn : out std_logic;
            rom_cs : out std_logic;
            rom_addr : out unsigned(16 downto 0);
            rom_data : in unsigned(7 downto 0);
            rom_ok : in std_logic;
            sound : out unsigned(8 downto 0)
        );
    end component;
    function rom_byte(vu17_address : unsigned(16 downto 0)) return unsigned is
        variable vint_address : natural;
    begin
        vint_address := to_integer(vu17_address);
        case vint_address is
            when 0 => return x"00";
            when 1 => return x"5A";
            when 2 => return x"A5";
            when 3 => return x"69";
            when 4 => return x"55";
            when 5 => return x"00";
            when 6 => return x"20";
            when 7 => return x"00";
            when 8 => return x"30";
            when 16#41# | 16#61# => return x"89";
            when 16#42# | 16#62# => return x"03";
            when 16#43# | 16#63# => return x"77";
            when 16#44# | 16#64# => return x"FF";
            when others => return x"00";
        end case;
    end function;
    signal s_clk : std_logic := '0';
    signal s_reset, s_start_n : std_logic := '1';
    signal s_enable, s_busy_n, s_rom_request, s_rom_valid : std_logic := '0';
    signal su17_rom_address : unsigned(16 downto 0);
    signal su8_rom_data : unsigned(7 downto 0);
    signal s_wrapper_busy : std_logic;
    signal su8_command : unsigned(7 downto 0) := x"00";
    signal su9_sound : unsigned(8 downto 0);
    signal sint_divider : natural range 0 to 74 := 0;
    signal sint_nonzero, sint_fetches : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 74 else '0';
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 74) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            if (s_busy_n = '0' and su9_sound /= 0) then
                sint_nonzero <= sint_nonzero + 1;
            end if;
        end if;
    end process;
    native_chip : if (not GBOOL_USE_WRAPPER) generate
        chip : jt7759
            port map (
                rst => s_reset,
                clk => s_clk,
                cen => s_enable,
                stn => s_start_n,
                cs => '1',
                mdn => '1',
                busyn => s_busy_n,
                wrn => '1',
                din => su8_command,
                drqn => open,
                rom_cs => s_rom_request,
                rom_addr => su17_rom_address,
                rom_data => su8_rom_data,
                rom_ok => s_rom_valid,
                sound => su9_sound
            );
    end generate;
    wrapped_chip : if (GBOOL_USE_WRAPPER) generate
        s_busy_n <= not s_wrapper_busy;
        chip : entity work.rabbitpunch_upd7759
            port map (
                i_clk => s_clk,
                i_reset => s_reset,
                i_enable => s_enable,
                i_start => not s_start_n,
                iu8_command => su8_command,
                o_busy => s_wrapper_busy,
                o_rom_request => s_rom_request,
                ou17_rom_address => su17_rom_address,
                i_rom_valid => s_rom_valid,
                iu8_rom_data => su8_rom_data,
                ou9_pcm => su9_sound
            );
    end generate;
    rom_transport : process(s_clk)
        variable v_active : boolean := false;
        variable vu17_address : unsigned(16 downto 0);
        variable vint_delay : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_rom_request = '0') then
                s_rom_valid <= '0';
                v_active := false;
            elsif (not v_active or su17_rom_address /= vu17_address) then
                vu17_address := su17_rom_address;
                assert (vu17_address < 256) report "JT7759 unexpected sample ROM address" severity failure;
                v_active := true;
                vint_delay := 13;
                s_rom_valid <= '0';
                sint_fetches <= sint_fetches + 1;
            elsif (vint_delay = 0) then
                su8_rom_data <= rom_byte(vu17_address);
                s_rom_valid <= '1';
            else
                vint_delay := vint_delay - 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_nonzero_before, vint_fetches_before : natural;
    begin
        wait for 20 us;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        wait for 20 us;
        assert (s_busy_n = '1' and su9_sound = 0) report "JT7759 reset/idle failed" severity failure;
        for vint_sample in 1 to 2 loop
            vint_nonzero_before := sint_nonzero;
            vint_fetches_before := sint_fetches;
            wait until falling_edge(s_clk);
            su8_command <= to_unsigned(vint_sample - 1, 8);
            s_start_n <= '0';
            for vint_cycle in 1 to 4 loop
                wait until falling_edge(s_clk);
            end loop;
            s_start_n <= '1';
            if (s_busy_n /= '0') then
                wait until s_busy_n = '0' for 100 us;
            end if;
            assert (s_busy_n = '0') report "JT7759 start/retrigger was not accepted" severity failure;
            wait until s_busy_n = '1' for 3 ms;
            assert (s_busy_n = '1' and sint_nonzero > vint_nonzero_before and sint_fetches >= vint_fetches_before + 6)
                report "JT7759 sample did not complete with ROM reads and nonzero PCM" severity failure;
            for vint_cycle in 1 to 64 loop
                wait until falling_edge(s_clk);
            end loop;
        end loop;
        s_reset <= '1';
        wait until falling_edge(s_clk);
        assert (s_busy_n = '1' and su9_sound = 0) report "JT7759 reset did not mute output" severity failure;
        report "JT7759_BASELINE_PASS samples=2 retrigger=checked delayed_rom=13 reset_mute=checked";
        finish;
        wait;
    end process;
end architecture;
