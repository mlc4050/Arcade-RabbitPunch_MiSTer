library ieee;
use ieee.std_logic_1164.all;

-- One request pulse and one response per 68000 bus cycle. The backend must finish
-- accepted requests even across CPU reset; stale replies are drained before reuse.
entity rabbitpunch_bus is
    port (
        clk, reset : in std_logic;
        cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n : in std_logic;
        cpu_address : in std_logic_vector(23 downto 1);
        cpu_write_data : in std_logic_vector(15 downto 0);
        cpu_read_data : out std_logic_vector(15 downto 0);
        cpu_dtack_n : out std_logic;
        request, request_write : out std_logic;
        request_address : out std_logic_vector(23 downto 0);
        request_data : out std_logic_vector(15 downto 0);
        request_bytes : out std_logic_vector(1 downto 0);
        response_valid : in std_logic;
        response_data : in std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_bus is
    type state_t is (idle, waiting, complete, draining);
    signal state : state_t := idle;
begin
    cpu_dtack_n <= '0' when state = complete and cpu_as_n = '0' and reset = '0' else '1';
    process(clk)
    begin
        if rising_edge(clk) then
            request <= '0';
            if reset = '1' then
                if (state = waiting or state = draining) and response_valid = '0' then
                    state <= draining;
                else
                    state <= idle;
                end if;
                cpu_read_data <= (others => '1');
            else
                case state is
                    when idle =>
                        if cpu_as_n = '0' and (cpu_uds_n = '0' or cpu_lds_n = '0') then
                            request <= '1';
                            request_write <= not cpu_rw;
                            request_address <= cpu_address & '0';
                            request_data <= cpu_write_data;
                            request_bytes <= (not cpu_uds_n) & (not cpu_lds_n);
                            state <= waiting;
                        end if;
                    when waiting =>
                        if cpu_as_n = '1' then
                            if response_valid = '1' then state <= idle;
                            else state <= draining; end if;
                        elsif response_valid = '1' then
                            cpu_read_data <= response_data;
                            state <= complete;
                        end if;
                    when complete =>
                        if cpu_as_n = '1' then state <= idle; end if;
                    when draining =>
                        if response_valid = '1' then state <= idle; end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
