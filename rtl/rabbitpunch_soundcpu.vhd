library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The bus runs on i_clk while the Z80 advances only at enabled, completed
-- transaction boundaries. A request is a one-clock pulse with one reply owed.
entity rabbitpunch_soundcpu is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_pause : in std_logic;
        i_interrupt : in std_logic;
        o_request : out std_logic;
        o_request_write : out std_logic;
        ou16_request_address : out unsigned(15 downto 0);
        ou8_request_data : out unsigned(7 downto 0);
        i_response_valid : in std_logic;
        iu8_response_data : in unsigned(7 downto 0);
        o_paused : out std_logic;
        o_halted : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_soundcpu is
    type t_state is (STATE_IDLE, STATE_WAITING, STATE_COMPLETE, STATE_DRAINING);
    signal styp_state : t_state := STATE_IDLE;
    signal s_memory, s_read, s_write, s_cycle, s_enable, s_reset : std_logic;
    signal su16_address : unsigned(15 downto 0);
    signal su8_write_data : unsigned(7 downto 0);
    signal su8_read_data : unsigned(7 downto 0) := x"FF";
begin
    s_cycle <= s_memory and (s_read or s_write);
    s_reset <= '1' when i_reset = '1' or styp_state = STATE_DRAINING else '0';
    s_enable <= i_enable when i_pause = '0' and s_reset = '0' and
        (s_cycle = '0' or styp_state = STATE_COMPLETE) else '0';
    o_paused <= '1' when i_pause = '1' and
        (styp_state = STATE_IDLE or styp_state = STATE_COMPLETE) else '0';
    cpu : entity work.rabbitpunch_z80
        port map (
            i_clk => i_clk,
            i_reset => s_reset,
            i_enable => s_enable,
            i_wait => '0',
            i_interrupt => i_interrupt,
            i_non_maskable_interrupt => '0',
            i_bus_request => '0',
            iu8_read_data => su8_read_data,
            ou16_address => su16_address,
            ou8_write_data => su8_write_data,
            o_opcode_fetch => open,
            o_memory_request => s_memory,
            o_io_request => open,
            o_read => s_read,
            o_write => s_write,
            o_refresh => open,
            o_halted => o_halted,
            o_bus_grant => open
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_request <= '0';
            if (i_reset = '1') then
                su8_read_data <= x"FF";
                if ((styp_state = STATE_WAITING or styp_state = STATE_DRAINING) and i_response_valid /= '1') then
                    styp_state <= STATE_DRAINING;
                else
                    styp_state <= STATE_IDLE;
                end if;
            else
                case styp_state is
                    when STATE_IDLE =>
                        if (s_cycle = '1' and i_pause = '0') then
                            ou16_request_address <= su16_address;
                            ou8_request_data <= su8_write_data;
                            o_request_write <= s_write;
                            o_request <= '1';
                            styp_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_response_valid = '1') then
                            su8_read_data <= iu8_response_data;
                            styp_state <= STATE_COMPLETE;
                        end if;
                    when STATE_COMPLETE =>
                        if (s_cycle = '0') then
                            su8_read_data <= x"FF";
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAINING =>
                        if (i_response_valid = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
