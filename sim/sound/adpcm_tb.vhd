library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity adpcm_tb is
end entity;

architecture test of adpcm_tb is
    function rom_byte(vu18_address : unsigned(17 downto 0)) return unsigned is
        variable vint_address : natural;
    begin
        vint_address := to_integer(vu18_address(16 downto 0));
        case vint_address is
            when 0 => return x"00";
            when 1 => return x"5A";
            when 2 => return x"A5";
            when 3 => return x"69";
            when 4 => return x"55";
            when 5 => return x"00";
            when 6 =>
                if (vu18_address(17) = '0') then
                    return x"20";
                else
                    return x"30";
                end if;
            when 16#41# | 16#61# => return x"89";
            when 16#42# | 16#62# => return x"03";
            when 16#43# | 16#63# =>
                if (vu18_address(17) = '0') then
                    return x"77";
                else
                    return x"33";
                end if;
            when 16#44# | 16#64# => return x"FF";
            when others => return x"00";
        end case;
    end function;
    signal s_clk : std_logic := '0';
    signal s_reset : std_logic := '1';
    signal s_enable, s_control_write, s_command_write, s_busy : std_logic := '0';
    signal s_rom_request, s_rom_cached, s_rom_valid, s_bank, s_reset_asserted : std_logic := '0';
    signal su8_data, su8_rom_data : unsigned(7 downto 0) := x"00";
    signal su18_rom_address, su18_cached_address : unsigned(17 downto 0);
    signal su9_pcm : unsigned(8 downto 0);
    signal sint_divider : natural range 0 to 74 := 0;
    signal sint_bank0_reads, sint_bank1_reads, sint_nonzero : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_enable <= '1' when sint_divider = 74 else '0';
    -- A bank change invalidates an old response immediately, before the next
    -- clock. The future ROM frontend must enforce this address-tag contract.
    s_rom_valid <= s_rom_cached when s_rom_request = '1' and su18_rom_address = su18_cached_address else '0';
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_divider = 74) then
                sint_divider <= 0;
            else
                sint_divider <= sint_divider + 1;
            end if;
            if (s_busy = '1' and su9_pcm /= 0) then
                sint_nonzero <= sint_nonzero + 1;
            end if;
        end if;
    end process;
    dut : entity work.rabbitpunch_adpcm
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_control_write => s_control_write,
            i_command_write => s_command_write,
            iu8_write_data => su8_data,
            o_busy => s_busy,
            o_rom_request => s_rom_request,
            ou18_rom_address => su18_rom_address,
            i_rom_valid => s_rom_valid,
            iu8_rom_data => su8_rom_data,
            ou9_pcm => su9_pcm,
            o_bank => s_bank,
            o_reset_asserted => s_reset_asserted
        );
    rom_transport : process(s_clk)
        variable v_active : boolean := false;
        variable vint_delay : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_rom_request = '0') then
                s_rom_cached <= '0';
                v_active := false;
            elsif (not v_active or su18_rom_address /= su18_cached_address) then
                su18_cached_address <= su18_rom_address;
                v_active := true;
                vint_delay := 23;
                s_rom_cached <= '0';
                if (su18_rom_address(17) = '0') then
                    sint_bank0_reads <= sint_bank0_reads + 1;
                else
                    sint_bank1_reads <= sint_bank1_reads + 1;
                end if;
            elsif (vint_delay = 0) then
                su8_rom_data <= rom_byte(su18_cached_address);
                s_rom_cached <= '1';
            else
                vint_delay := vint_delay - 1;
            end if;
        end if;
    end process;
    stimulus : process
        variable vint_before, vint_reads_before : natural;
        procedure write_control(constant vu8_data : unsigned(7 downto 0)) is
        begin
            wait until falling_edge(s_clk);
            su8_data <= vu8_data;
            s_control_write <= '1';
            wait until falling_edge(s_clk);
            s_control_write <= '0';
            su8_data <= x"CC";
        end procedure;
        procedure write_command is
        begin
            wait until falling_edge(s_clk);
            su8_data <= x"00";
            s_command_write <= '1';
            wait until falling_edge(s_clk);
            s_command_write <= '0';
            su8_data <= x"CC";
        end procedure;
        procedure play_sample is
        begin
            vint_before := sint_nonzero;
            write_command;
            if (s_busy /= '1') then
                wait until s_busy = '1' for 100 us;
            end if;
            assert (s_busy = '1') report "Board ADPCM command did not start" severity failure;
            wait until s_busy = '0' for 3 ms;
            assert (s_busy = '0' and sint_nonzero > vint_before)
                report "Board ADPCM sample did not complete with PCM" severity failure;
            wait for 2 us;
        end procedure;
    begin
        wait for 20 us;
        wait until falling_edge(s_clk);
        s_reset <= '0';
        write_command;
        wait for 20 us;
        assert (s_reset_asserted = '1' and s_busy = '0' and su9_pcm = 0)
            report "Board ADPCM started while its reset pin was asserted" severity failure;
        write_control(x"80");
        play_sample;
        assert (s_bank = '0' and sint_bank0_reads >= 6 and sint_bank1_reads = 0)
            report "Board ADPCM bank zero address mapping failed" severity failure;
        write_control(x"01");
        assert (s_bank = '1' and s_reset_asserted = '1' and s_busy = '0' and su9_pcm = 0)
            report "Board ADPCM control reset polarity or bank latch failed" severity failure;
        write_control(x"81");
        vint_reads_before := sint_bank0_reads;
        play_sample;
        assert (s_bank = '1' and sint_bank1_reads >= 6 and sint_bank0_reads = vint_reads_before)
            report "Board ADPCM bank one address mapping failed" severity failure;
        write_command;
        wait until s_busy = '1' for 100 us;
        assert (s_busy = '1') report "Board ADPCM abort setup did not start" severity failure;
        wait until su9_pcm /= 0 for 3 ms;
        assert (s_busy = '1' and su9_pcm /= 0) report "Board ADPCM abort setup never decoded audio" severity failure;
        write_control(x"00");
        assert (s_reset_asserted = '1' and s_bank = '0' and s_busy = '0' and su9_pcm = 0)
            report "Board ADPCM reset did not abort active playback" severity failure;
        write_control(x"80");
        play_sample;
        report "ADPCM_PASS banks=2 complete_samples=3 reset_abort=checked reset_command_ignore=checked delayed_rom=23";
        finish;
        wait;
    end process;
    process
    begin
        wait for 10 ms;
        assert false report "Board ADPCM timeout" severity failure;
    end process;
end architecture;
