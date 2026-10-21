library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PCM ports carry raw two's-complement bits in unsigned buses. Preserve that
-- encoding when mixing audio. Both enables advance logic on i_clk, not clocks.
entity rabbitpunch_ym2151 is
    generic (
        GBOOL_STATE_CAPABLE : boolean := false
    );
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
        ou16_full_right_pcm : out unsigned(15 downto 0);
        i_state_hold : in std_logic := '0';
        i_state_write : in std_logic := '0';
        iu16_state_word_address : in unsigned(15 downto 0) := (others => '0');
        iu32_state_write_data : in unsigned(31 downto 0) := (others => '0');
        ou32_state_read_data : out unsigned(31 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_ym2151 is
    component rabbitpunch_jt51_state_netlist is
        port (
            i_reset : in std_logic;
            i_clk : in std_logic;
            i_chip_enable : in std_logic;
            i_half_chip_enable : in std_logic;
            i_chip_select_n : in std_logic;
            i_write_n : in std_logic;
            i_data_register : in std_logic;
            iu8_write_data : in unsigned(7 downto 0);
            ou8_status : out unsigned(7 downto 0);
            o_control1 : out std_logic;
            o_control2 : out std_logic;
            o_interrupt_n : out std_logic;
            o_sample : out std_logic;
            ou16_left_pcm : out unsigned(15 downto 0);
            ou16_right_pcm : out unsigned(15 downto 0);
            ou16_full_left_pcm : out unsigned(15 downto 0);
            ou16_full_right_pcm : out unsigned(15 downto 0);
            i_state_hold : in std_logic;
            i_state_write : in std_logic;
            iu16_state_word_address : in unsigned(15 downto 0);
            iu32_state_write_data : in unsigned(31 downto 0);
            ou32_state_read_data : out unsigned(31 downto 0)
        );
    end component;
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
    end generate;

    state_chip : if (GBOOL_STATE_CAPABLE) generate
        chip : rabbitpunch_jt51_state_netlist
            port map (
                i_reset => i_reset,
                i_clk => i_clk,
                i_chip_enable => i_chip_enable,
                i_half_chip_enable => i_half_chip_enable,
                i_chip_select_n => not i_chip_select,
                i_write_n => not i_write,
                i_data_register => i_data_register,
                iu8_write_data => iu8_write_data,
                ou8_status => ou8_status,
                o_control1 => open,
                o_control2 => open,
                o_interrupt_n => s_interrupt_n,
                o_sample => o_sample_marker,
                ou16_left_pcm => ou16_left_pcm,
                ou16_right_pcm => ou16_right_pcm,
                ou16_full_left_pcm => ou16_full_left_pcm,
                ou16_full_right_pcm => ou16_full_right_pcm,
                i_state_hold => i_state_hold,
                i_state_write => i_state_write,
                iu16_state_word_address => iu16_state_word_address,
                iu32_state_write_data => iu32_state_write_data,
                ou32_state_read_data => ou32_state_read_data
            );
    end generate;
end architecture;
