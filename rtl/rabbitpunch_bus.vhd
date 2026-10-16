library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One request pulse and one response per 68000 bus cycle. The backend must finish
-- accepted requests even across CPU reset; stale replies are drained before reuse.
entity rabbitpunch_bus is
    port (
        i_clk, i_reset : in std_logic;
        i_cpu_address_strobe_n, i_cpu_read, i_cpu_upper_byte_strobe_n, i_cpu_lower_byte_strobe_n : in std_logic;
        iu23_cpu_word_address : in unsigned(23 downto 1);
        iu16_cpu_write_data : in unsigned(15 downto 0);
        ou16_cpu_read_data : out unsigned(15 downto 0);
        o_cpu_transfer_acknowledge_n : out std_logic;
        o_request, o_request_write : out std_logic;
        ou24_request_address : out unsigned(23 downto 0);
        ou16_request_data : out unsigned(15 downto 0);
        ou2_request_bytes : out unsigned(1 downto 0);
        i_response_valid : in std_logic;
        iu16_response_data : in unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_bus is
    type styp_state is (STATE_IDLE, STATE_WAITING, STATE_COMPLETE, STATE_DRAINING);
    signal s_state : styp_state := STATE_IDLE;
begin
    o_cpu_transfer_acknowledge_n <= '0' when s_state = STATE_COMPLETE and i_cpu_address_strobe_n = '0' and i_reset = '0' else '1';
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_request <= '0';
            if (i_reset = '1') then
                if ((s_state = STATE_WAITING or s_state = STATE_DRAINING) and i_response_valid = '0') then
                    s_state <= STATE_DRAINING;
                else
                    s_state <= STATE_IDLE;
                end if;
                ou16_cpu_read_data <= (others => '1');
            else
                case s_state is
                    when STATE_IDLE =>
                        if (i_cpu_address_strobe_n = '0' and (i_cpu_upper_byte_strobe_n = '0' or i_cpu_lower_byte_strobe_n = '0')) then
                            o_request <= '1';
                            o_request_write <= not i_cpu_read;
                            ou24_request_address <= iu23_cpu_word_address & '0';
                            ou16_request_data <= iu16_cpu_write_data;
                            ou2_request_bytes <= (not i_cpu_upper_byte_strobe_n) & (not i_cpu_lower_byte_strobe_n);
                            s_state <= STATE_WAITING;
                        end if;
                    when STATE_WAITING =>
                        if (i_cpu_address_strobe_n = '1') then
                            if (i_response_valid = '1') then
                                s_state <= STATE_IDLE;
                            else
                                s_state <= STATE_DRAINING;
                            end if;
                        elsif (i_response_valid = '1') then
                            ou16_cpu_read_data <= iu16_response_data;
                            s_state <= STATE_COMPLETE;
                        end if;
                    when STATE_COMPLETE =>
                        if (i_cpu_address_strobe_n = '1') then
                            s_state <= STATE_IDLE;
                        end if;
                    when STATE_DRAINING =>
                        if (i_response_valid = '1') then
                            s_state <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
