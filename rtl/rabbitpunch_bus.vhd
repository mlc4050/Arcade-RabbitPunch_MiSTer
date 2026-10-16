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
    type state_t is (idle, waiting, complete, draining);
    signal s_state : state_t := idle;
begin
    o_cpu_transfer_acknowledge_n <= '0' when s_state = complete and i_cpu_address_strobe_n = '0' and i_reset = '0' else '1';
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            o_request <= '0';
            if i_reset = '1' then
                if (s_state = waiting or s_state = draining) and i_response_valid = '0' then
                    s_state <= draining;
                else
                    s_state <= idle;
                end if;
                ou16_cpu_read_data <= (others => '1');
            else
                case s_state is
                    when idle =>
                        if i_cpu_address_strobe_n = '0' and (i_cpu_upper_byte_strobe_n = '0' or i_cpu_lower_byte_strobe_n = '0') then
                            o_request <= '1';
                            o_request_write <= not i_cpu_read;
                            ou24_request_address <= iu23_cpu_word_address & '0';
                            ou16_request_data <= iu16_cpu_write_data;
                            ou2_request_bytes <= (not i_cpu_upper_byte_strobe_n) & (not i_cpu_lower_byte_strobe_n);
                            s_state <= waiting;
                        end if;
                    when waiting =>
                        if i_cpu_address_strobe_n = '1' then
                            if i_response_valid = '1' then s_state <= idle;
                            else s_state <= draining; end if;
                        elsif i_response_valid = '1' then
                            ou16_cpu_read_data <= iu16_response_data;
                            s_state <= complete;
                        end if;
                    when complete =>
                        if i_cpu_address_strobe_n = '1' then s_state <= idle; end if;
                    when draining =>
                        if i_response_valid = '1' then s_state <= idle; end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
