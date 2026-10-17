library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One outstanding byte transaction from rabbitpunch_soundcpu. Keep this backend
-- live during CPU reset/pause so an already-issued request can always drain.
entity rabbitpunch_sound_bus is
    port (
        i_clk : in std_logic;
        i_request : in std_logic;
        i_request_write : in std_logic;
        iu16_request_address : in unsigned(15 downto 0);
        iu8_request_data : in unsigned(7 downto 0);
        o_response_valid : out std_logic;
        ou8_response_data : out unsigned(7 downto 0);
        o_rom_request : out std_logic;
        ou16_rom_address : out unsigned(15 downto 0);
        i_rom_ready : in std_logic;
        i_rom_response_valid : in std_logic;
        iu8_rom_response_data : in unsigned(7 downto 0);
        i_ym_write_enable : in std_logic;
        iu8_ym_status : in unsigned(7 downto 0);
        o_ym_write : out std_logic;
        o_ym_data_register : out std_logic;
        ou8_ym_write_data : out unsigned(7 downto 0);
        iu8_command : in unsigned(7 downto 0);
        o_command_read : out std_logic;
        o_adpcm_control_write : out std_logic;
        o_adpcm_command_write : out std_logic;
        ou8_adpcm_data : out unsigned(7 downto 0);
        i_view_enable : in std_logic;
        iu11_view_address : in unsigned(10 downto 0);
        ou8_view_data : out unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_sound_bus is
    type t_state is (STATE_IDLE, STATE_ROM_REQUEST, STATE_ROM_WAITING, STATE_RAM_REPLY, STATE_YM_WRITE);
    signal styp_state : t_state := STATE_IDLE;
    signal s_ram_enable : std_logic;
    signal su8_ram_data : unsigned(7 downto 0);
begin
    s_ram_enable <= '1' when i_request = '1' and iu16_request_address >= x"F800" else '0';
    o_rom_request <= '1' when styp_state = STATE_ROM_REQUEST else '0';
    -- JT51's register interface consumes writes on every system clock.
    -- Present exactly one pulse at the selected chip-enable edge.
    o_ym_write <= '1' when styp_state = STATE_YM_WRITE and i_ym_write_enable = '1' else '0';
    sound_ram : entity work.rabbitpunch_ram8
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_ram_enable,
            i_cpu_write => i_request_write,
            iux_cpu_address => iu16_request_address(10 downto 0),
            iu8_cpu_data => iu8_request_data,
            ou8_cpu_data => su8_ram_data,
            i_view_enable => i_view_enable,
            iux_view_address => iu11_view_address,
            ou8_view_data => ou8_view_data
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_response_valid <= '0';
            o_command_read <= '0';
            o_adpcm_control_write <= '0';
            o_adpcm_command_write <= '0';
            assert (i_request /= '1' or styp_state = STATE_IDLE)
                report "Sound backend received overlapping requests" severity failure;
            case styp_state is
                when STATE_IDLE =>
                    if (i_request = '1') then
                        ou8_response_data <= x"FF";
                        if (iu16_request_address >= x"F800") then
                            styp_state <= STATE_RAM_REPLY;
                        elsif (i_request_write = '1') then
                            if (iu16_request_address = x"F000" or iu16_request_address = x"F001") then
                                o_ym_data_register <= iu16_request_address(0);
                                ou8_ym_write_data <= iu8_request_data;
                                styp_state <= STATE_YM_WRITE;
                            else
                                o_response_valid <= '1';
                                ou8_adpcm_data <= iu8_request_data;
                                if (iu16_request_address = x"F400") then
                                    o_adpcm_control_write <= '1';
                                elsif (iu16_request_address = x"F600") then
                                    o_adpcm_command_write <= '1';
                                end if;
                            end if;
                        elsif (iu16_request_address < x"F000") then
                            ou16_rom_address <= iu16_request_address;
                            styp_state <= STATE_ROM_REQUEST;
                        else
                            o_response_valid <= '1';
                            if (iu16_request_address = x"F001") then
                                ou8_response_data <= iu8_ym_status;
                            elsif (iu16_request_address = x"F200") then
                                ou8_response_data <= iu8_command;
                                o_command_read <= '1';
                            end if;
                        end if;
                    end if;
                when STATE_ROM_REQUEST =>
                    if (i_rom_ready = '1') then
                        styp_state <= STATE_ROM_WAITING;
                    end if;
                when STATE_ROM_WAITING =>
                    if (i_rom_response_valid = '1') then
                        ou8_response_data <= iu8_rom_response_data;
                        o_response_valid <= '1';
                        styp_state <= STATE_IDLE;
                    end if;
                when STATE_RAM_REPLY =>
                    ou8_response_data <= su8_ram_data;
                    o_response_valid <= '1';
                    styp_state <= STATE_IDLE;
                when STATE_YM_WRITE =>
                    if (i_ym_write_enable = '1') then
                        o_response_valid <= '1';
                        styp_state <= STATE_IDLE;
                    end if;
            end case;
        end if;
    end process;
end architecture;
