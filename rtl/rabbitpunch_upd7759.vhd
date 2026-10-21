library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Corrected native/state standalone-mode uPD7759 interface. PCM is raw two's-complement in an
-- unsigned bus; external board logic owns bank selection and reset/start timing.
entity rabbitpunch_upd7759 is
    generic (
        GBOOL_STATE_CAPABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_start : in std_logic;
        iu8_command : in unsigned(7 downto 0);
        o_busy : out std_logic;
        o_rom_request : out std_logic;
        ou17_rom_address : out unsigned(16 downto 0);
        i_rom_valid : in std_logic;
        iu8_rom_data : in unsigned(7 downto 0);
        ou9_pcm : out unsigned(8 downto 0);
        i_state_hold : in std_logic := '0';
        i_state_write : in std_logic := '0';
        iu16_state_word_address : in unsigned(15 downto 0) := (others => '0');
        iu32_state_write_data : in unsigned(31 downto 0) := (others => '0');
        ou32_state_read_data : out unsigned(31 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_upd7759 is
    component rabbitpunch_jt7759_state_netlist is
        port (
            i_reset : in std_logic;
            i_clk : in std_logic;
            i_chip_enable : in std_logic;
            i_start_n : in std_logic;
            i_chip_select : in std_logic;
            i_standalone_mode : in std_logic;
            o_busy_n : out std_logic;
            i_write_n : in std_logic;
            iu8_write_data : in unsigned(7 downto 0);
            o_data_request_n : out std_logic;
            o_rom_request : out std_logic;
            ou17_rom_address : out unsigned(16 downto 0);
            iu8_rom_data : in unsigned(7 downto 0);
            i_rom_valid : in std_logic;
            ou9_pcm : out unsigned(8 downto 0);
            i_state_hold : in std_logic;
            i_state_write : in std_logic;
            iu16_state_word_address : in unsigned(15 downto 0);
            iu32_state_write_data : in unsigned(31 downto 0);
            ou32_state_read_data : out unsigned(31 downto 0)
        );
    end component;
    component rabbitpunch_upd7759_playback is
        port (
            i_clk : in std_logic;
            i_reset : in std_logic;
            i_enable : in std_logic;
            i_start : in std_logic;
            iu8_command : in unsigned(7 downto 0);
            o_busy : out std_logic;
            o_rom_request : out std_logic;
            ou17_rom_address : out unsigned(16 downto 0);
            i_rom_valid : in std_logic;
            iu8_rom_data : in unsigned(7 downto 0);
            ou9_pcm : out unsigned(8 downto 0)
        );
    end component;
    signal s_busy_n : std_logic;
begin
    original_chip : if (not GBOOL_STATE_CAPABLE) generate
        ou32_state_read_data <= (others => '0');
        inactive_state_access : process(i_clk)
        begin
            if (rising_edge(i_clk)) then
                -- Sample the synchronous interface after port expressions
                -- settle; elaboration delta cycles are not chip accesses.
                assert (i_state_hold = '0' and i_state_write = '0')
                    report "State chip access requires GBOOL_STATE_CAPABLE" severity failure;
            end if;
        end process;
        chip : rabbitpunch_upd7759_playback
            port map (
                i_clk => i_clk,
                i_reset => i_reset,
                i_enable => i_enable,
                i_start => i_start,
                iu8_command => iu8_command,
                o_busy => o_busy,
                o_rom_request => o_rom_request,
                ou17_rom_address => ou17_rom_address,
                i_rom_valid => i_rom_valid,
                iu8_rom_data => iu8_rom_data,
                ou9_pcm => ou9_pcm
            );
    end generate;

    state_chip : if (GBOOL_STATE_CAPABLE) generate
        signal s_state_rom_request : std_logic;
    begin
        o_busy <= not s_busy_n;
        o_rom_request <= s_state_rom_request and not i_state_hold;
        chip : rabbitpunch_jt7759_state_netlist
            port map (
                i_reset => i_reset,
                i_clk => i_clk,
                i_chip_enable => i_enable,
                i_start_n => not i_start,
                i_chip_select => '1',
                i_standalone_mode => '1',
                o_busy_n => s_busy_n,
                i_write_n => '1',
                iu8_write_data => iu8_command,
                o_data_request_n => open,
                o_rom_request => s_state_rom_request,
                ou17_rom_address => ou17_rom_address,
                iu8_rom_data => iu8_rom_data,
                i_rom_valid => i_rom_valid,
                ou9_pcm => ou9_pcm,
                i_state_hold => i_state_hold,
                i_state_write => i_state_write,
                iu16_state_word_address => iu16_state_word_address,
                iu32_state_write_data => iu32_state_write_data,
                ou32_state_read_data => ou32_state_read_data
            );
    end generate;
end architecture;
