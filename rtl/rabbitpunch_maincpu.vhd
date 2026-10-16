library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 48 MHz evaluation clock: alternating phases every three clocks give 8 MHz.
-- Memory latency becomes real 68000 wait states; phases are never accelerated.
entity rabbitpunch_maincpu is
    generic (sint_PHASE_DIVIDER : positive := 3);
    port (
        i_clk, i_reset, i_pause : in std_logic;
        o_request, o_request_write : out std_logic;
        ou24_request_address : out unsigned(23 downto 0);
        ou16_request_data : out unsigned(15 downto 0);
        ou2_request_bytes : out unsigned(1 downto 0);
        i_response_valid : in std_logic;
        iu16_response_data : in unsigned(15 downto 0);
        o_paused : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_maincpu is
    signal sint_phase_count : natural range 0 to sint_PHASE_DIVIDER-1 := 0;
    signal s_phase : std_logic := '0';
    signal s_enable_phase1, s_enable_phase2, s_frozen : std_logic;
    signal s_address_strobe_n, s_upper_byte_strobe_n, s_lower_byte_strobe_n, s_read, s_transfer_acknowledge_n : std_logic;
    signal su23_word_address : unsigned(23 downto 1);
    signal su16_read_data, su16_write_data : unsigned(15 downto 0);
begin
    -- Finish the current bus cycle before stopping. Backend replies keep running.
    s_frozen <= '1' when i_pause = '1' and s_address_strobe_n = '1' and i_reset = '0' else '0';
    o_paused <= s_frozen;
    s_enable_phase1 <= '1' when sint_phase_count = sint_PHASE_DIVIDER-1 and s_phase = '0' and s_frozen = '0' else '0';
    s_enable_phase2 <= '1' when sint_phase_count = sint_PHASE_DIVIDER-1 and s_phase = '1' and s_frozen = '0' else '0';
    process(i_clk)
    begin
        if rising_edge(i_clk) and s_frozen = '0' then
            if sint_phase_count = sint_PHASE_DIVIDER-1 then
                sint_phase_count <= 0;
                s_phase <= not s_phase;
            else sint_phase_count <= sint_phase_count + 1;
            end if;
        end if;
    end process;

    cpu : entity work.rabbitpunch_fx68k port map (
        i_clk => i_clk,
        i_external_reset => i_reset,
        i_powerup_reset => i_reset,
        i_enable_phase1 => s_enable_phase1,
        i_enable_phase2 => s_enable_phase2,
        i_run => '1',
        o_read => s_read,
        o_address_strobe_n => s_address_strobe_n,
        o_upper_byte_strobe_n => s_upper_byte_strobe_n,
        o_lower_byte_strobe_n => s_lower_byte_strobe_n,
        ou23_word_address => su23_word_address,
        ou16_write_data => su16_write_data,
        iu16_read_data => su16_read_data,
        i_transfer_acknowledge_n => s_transfer_acknowledge_n,
        i_peripheral_transfer_n => '1', -- No 6800 peripheral or IRQ wiring yet.
        i_bus_error_n => '1',
        i_bus_request_n => '1', -- No external bus master.
        i_bus_grant_acknowledge_n => '1',
        iu3_interrupt_level_n => "111", -- Interrupts disabled for initial CPU tests.
        ou3_function_code => open,
        o_peripheral_clock => open,
        o_peripheral_address_valid_n => open,
        o_bus_grant_n => open,
        o_external_reset_out_n => open,
        o_halted_out_n => open
    );
    bus_adapter : entity work.rabbitpunch_bus port map (
        i_clk => i_clk,
        i_reset => i_reset,
        i_cpu_address_strobe_n => s_address_strobe_n,
        i_cpu_read => s_read,
        i_cpu_upper_byte_strobe_n => s_upper_byte_strobe_n,
        i_cpu_lower_byte_strobe_n => s_lower_byte_strobe_n,
        iu23_cpu_word_address => su23_word_address,
        iu16_cpu_write_data => su16_write_data,
        ou16_cpu_read_data => su16_read_data,
        o_cpu_transfer_acknowledge_n => s_transfer_acknowledge_n,
        o_request => o_request,
        o_request_write => o_request_write,
        ou24_request_address => ou24_request_address,
        ou16_request_data => ou16_request_data,
        ou2_request_bytes => ou2_request_bytes,
        i_response_valid => i_response_valid,
        iu16_response_data => iu16_response_data
    );
end architecture;
