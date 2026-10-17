library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PCM ports carry raw two's-complement bits in unsigned buses. Preserve that
-- encoding when mixing audio. Both enables advance logic on i_clk, not clocks.
entity rabbitpunch_ym2151 is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_chip_enable : in std_logic;
        i_half_chip_enable : in std_logic;
        i_chip_select : in std_logic;
        i_write : in std_logic;
        i_data_register : in std_logic;
        iu8_write_data : in unsigned(7 downto 0);
        ou8_status : out unsigned(7 downto 0);
        o_interrupt : out std_logic;
        o_sample_marker : out std_logic;
        ou16_left_pcm : out unsigned(15 downto 0);
        ou16_right_pcm : out unsigned(15 downto 0);
        ou16_full_left_pcm : out unsigned(15 downto 0);
        ou16_full_right_pcm : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_ym2151 is
    component jt51 is
        port (
            rst : in std_logic;
            clk : in std_logic;
            cen : in std_logic;
            cen_p1 : in std_logic;
            cs_n : in std_logic;
            wr_n : in std_logic;
            a0 : in std_logic;
            din : in unsigned(7 downto 0);
            dout : out unsigned(7 downto 0);
            ct1 : out std_logic;
            ct2 : out std_logic;
            irq_n : out std_logic;
            sample : out std_logic;
            left : out unsigned(15 downto 0);
            right : out unsigned(15 downto 0);
            xleft : out unsigned(15 downto 0);
            xright : out unsigned(15 downto 0)
        );
    end component;
    signal s_interrupt_n : std_logic;
begin
    o_interrupt <= not s_interrupt_n;
    chip : jt51
        port map (
            rst => i_reset,
            clk => i_clk,
            cen => i_chip_enable,
            cen_p1 => i_half_chip_enable,
            cs_n => not i_chip_select,
            wr_n => not i_write,
            a0 => i_data_register,
            din => iu8_write_data,
            dout => ou8_status,
            ct1 => open,
            ct2 => open,
            irq_n => s_interrupt_n,
            sample => o_sample_marker,
            left => ou16_left_pcm,
            right => ou16_right_pcm,
            xleft => ou16_full_left_pcm,
            xright => ou16_full_right_pcm
        );
end architecture;
