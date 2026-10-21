library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- F400 controls bank bit 0 and the physical active-low reset pin at bit 7.
-- F600 latches a command before producing one start edge on i_clk.
entity rabbitpunch_adpcm is
    generic (
        GBOOL_STATE_CAPABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_control_write : in std_logic;
        i_command_write : in std_logic;
        iu8_write_data : in unsigned(7 downto 0);
        o_busy : out std_logic;
        o_rom_request : out std_logic;
        ou18_rom_address : out unsigned(17 downto 0);
        i_rom_valid : in std_logic;
        iu8_rom_data : in unsigned(7 downto 0);
        ou9_pcm : out unsigned(8 downto 0);
        o_bank : out std_logic;
        o_reset_asserted : out std_logic;
        i_state_hold : in std_logic := '0';
        i_state_load : in std_logic := '0';
        iu16_state : in unsigned(15 downto 0) := (others => '0');
        ou16_state : out unsigned(15 downto 0) := (others => '0');
        i_chip_state_write : in std_logic := '0';
        iu16_chip_state_word_address : in unsigned(15 downto 0) := (others => '0');
        iu32_chip_state_write_data : in unsigned(31 downto 0) := (others => '0');
        ou32_chip_state_read_data : out unsigned(31 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_adpcm is
    type t_state is (STATE_IDLE, STATE_WAITING, STATE_START);
    signal styp_state : t_state := STATE_IDLE;
    signal s_bank : std_logic := '0';
    signal s_control_reset : std_logic := '1';
    signal s_chip_reset, s_start : std_logic;
    signal s_start_ready : std_logic := '0';
    signal su8_command : unsigned(7 downto 0) := x"00";
    signal su17_rom_address : unsigned(16 downto 0);
begin
    s_chip_reset <= i_reset or s_control_reset;
    s_start <= '1' when styp_state = STATE_START and s_chip_reset = '0' else '0';
    ou18_rom_address <= s_bank & su17_rom_address;
    ou16_state <= to_unsigned(0, 3) & su8_command & s_start_ready & s_control_reset & s_bank &
        to_unsigned(t_state'pos(styp_state), 2);
    o_bank <= s_bank;
    o_reset_asserted <= s_chip_reset;
    chip : entity work.rabbitpunch_upd7759
        generic map (
            GBOOL_STATE_CAPABLE => GBOOL_STATE_CAPABLE
        )
        port map (
            i_clk => i_clk,
            i_reset => s_chip_reset,
            i_enable => i_enable,
            i_start => s_start,
            iu8_command => su8_command,
            o_busy => o_busy,
            o_rom_request => o_rom_request,
            ou17_rom_address => su17_rom_address,
            i_rom_valid => i_rom_valid,
            iu8_rom_data => iu8_rom_data,
            ou9_pcm => ou9_pcm,
            i_state_hold => i_state_hold and not i_reset,
            i_state_write => i_chip_state_write and not i_reset,
            iu16_state_word_address => iu16_chip_state_word_address,
            iu32_state_write_data => iu32_chip_state_write_data,
            ou32_state_read_data => ou32_chip_state_read_data
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            assert (i_control_write /= '1' or i_command_write /= '1')
                report "ADPCM control and command cannot share one bus transfer" severity failure;
            if (i_reset = '1') then
                s_bank <= '0';
                s_control_reset <= '1';
                su8_command <= x"00";
                s_start_ready <= '0';
                styp_state <= STATE_IDLE;
            elsif (i_state_hold = '1') then
                assert (i_control_write = '0' and i_command_write = '0')
                    report "ADPCM capture requires drained command writes" severity failure;
                if (i_state_load = '1') then
                    assert (iu16_state(15 downto 13) = 0 and iu16_state(1 downto 0) < 3)
                        report "Illegal ADPCM wrapper image" severity failure;
                    styp_state <= t_state'val(to_integer(iu16_state(1 downto 0)));
                    s_bank <= iu16_state(2);
                    s_control_reset <= iu16_state(3);
                    s_start_ready <= iu16_state(4);
                    su8_command <= iu16_state(12 downto 5);
                end if;
            else
                assert (i_state_load = '0') report "ADPCM wrapper load requires hold" severity failure;
                case styp_state is
                    when STATE_IDLE =>
                        null;
                    when STATE_WAITING =>
                        if (s_start_ready = '1') then
                            styp_state <= STATE_START;
                        end if;
                    when STATE_START =>
                        styp_state <= STATE_IDLE;
                end case;
                -- cen_ctl inside JT7759 is registered. A waiting command sees
                -- this ready flag one clock after the first enable, giving the
                -- chip time to leave reset before the start edge is presented.
                if (s_control_reset = '1') then
                    s_start_ready <= '0';
                    styp_state <= STATE_IDLE;
                elsif (i_enable = '1') then
                    s_start_ready <= '1';
                end if;
                if (i_control_write = '1') then
                    s_bank <= iu8_write_data(0);
                    s_control_reset <= not iu8_write_data(7);
                    if (iu8_write_data(7) = '0') then
                        s_start_ready <= '0';
                        styp_state <= STATE_IDLE;
                    end if;
                end if;
                if (i_command_write = '1' and s_control_reset = '0') then
                    su8_command <= iu8_write_data;
                    if (s_start_ready = '1') then
                        styp_state <= STATE_START;
                    else
                        styp_state <= STATE_WAITING;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
