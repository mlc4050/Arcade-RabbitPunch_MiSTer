library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standalone-mode uPD7759 interface. PCM is raw two's-complement in an
-- unsigned bus; external board logic owns bank selection and reset/start timing.
entity rabbitpunch_upd7759 is
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
end entity;

architecture rtl of rabbitpunch_upd7759 is
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
    signal s_busy_n : std_logic;
begin
    o_busy <= not s_busy_n;
    chip : jt7759
        port map (
            rst => i_reset,
            clk => i_clk,
            cen => i_enable,
            stn => not i_start,
            cs => '1',
            mdn => '1',
            busyn => s_busy_n,
            wrn => '1',
            din => iu8_command,
            drqn => open,
            rom_cs => o_rom_request,
            rom_addr => ou17_rom_address,
            rom_data => iu8_rom_data,
            rom_ok => i_rom_valid,
            sound => ou9_pcm
        );
end architecture;
