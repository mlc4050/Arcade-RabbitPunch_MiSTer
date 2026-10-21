library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Active-high board interface around the unchanged synchronous T80se.
-- CLKEN advances the CPU on i_clk. Vendor vector conversions stay here.
entity rabbitpunch_z80 is
    generic (
        GBOOL_STATE_CAPABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_enable : in std_logic;
        i_wait : in std_logic;
        i_interrupt : in std_logic;
        i_non_maskable_interrupt : in std_logic;
        i_bus_request : in std_logic;
        iu8_read_data : in unsigned(7 downto 0);
        ou16_address : out unsigned(15 downto 0);
        ou8_write_data : out unsigned(7 downto 0);
        o_opcode_fetch : out std_logic;
        o_memory_request : out std_logic;
        o_io_request : out std_logic;
        o_read : out std_logic;
        o_write : out std_logic;
        o_refresh : out std_logic;
        o_halted : out std_logic;
        o_bus_grant : out std_logic;
        i_capture_request : in std_logic := '0';
        i_capture_cancel : in std_logic := '0';
        i_bus_drained : in std_logic := '1';
        o_capture_pending : out std_logic := '0';
        o_state_held : out std_logic := '0';
        i_state_resume : in std_logic := '0';
        i_state_write : in std_logic := '0';
        iu256_state_data : in unsigned(255 downto 0) := (others => '0');
        ou256_state_data : out unsigned(255 downto 0) := (others => '0')
    );
end entity;

architecture rtl of rabbitpunch_z80 is
    component T80se is
        generic (
            Mode : integer := 0;    -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
            T2Write : integer := 0;  -- 0 => WR_n active in T3, /=0 => WR_n active in T2
            IOWait : integer := 1   -- 0 => Single cycle I/O, 1 => Std I/O cycle
        );
        port (
            RESET_n         : in  std_logic;
            CLK_n           : in  std_logic;
            CLKEN           : in  std_logic;
            WAIT_n          : in  std_logic;
            INT_n           : in  std_logic;
            NMI_n           : in  std_logic;
            BUSRQ_n         : in  std_logic;
            M1_n            : out std_logic;
            MREQ_n          : out std_logic;
            IORQ_n          : out std_logic;
            RD_n            : out std_logic;
            WR_n            : out std_logic;
            RFSH_n          : out std_logic;
            HALT_n          : out std_logic;
            BUSAK_n         : out std_logic;
            A               : out std_logic_vector(15 downto 0);
            DI              : in  std_logic_vector(7 downto 0);
            DO              : out std_logic_vector(7 downto 0)
        );
    end component;
    component rabbitpunch_t80_capture is
        port (
            i_clk : in std_logic;
            i_reset_n : in std_logic;
            i_clock_enable : in std_logic;
            i_wait_n : in std_logic;
            i_interrupt_n : in std_logic;
            o_opcode_fetch_n : out std_logic;
            o_memory_request_n : out std_logic;
            o_io_request_n : out std_logic;
            o_read_n : out std_logic;
            o_write_n : out std_logic;
            o_refresh_n : out std_logic;
            o_halted_n : out std_logic;
            ou16_address : out unsigned(15 downto 0);
            iu8_read_data : in unsigned(7 downto 0);
            ou8_write_data : out unsigned(7 downto 0);
            i_capture_request : in std_logic;
            i_cancel : in std_logic := '0';
            i_bus_drained : in std_logic;
            o_capture_pending : out std_logic;
            o_held : out std_logic;
            i_resume : in std_logic;
            i_state_write : in std_logic;
            iu256_state_data : in unsigned(255 downto 0);
            ou256_state_data : out unsigned(255 downto 0);
            o_clean_boundary : out std_logic;
            ou3_machine_cycle : out unsigned(2 downto 0);
            ou3_clock_phase : out unsigned(2 downto 0)
        );
    end component;
    subtype t_address is unsigned(15 downto 0);
    subtype t_data is unsigned(7 downto 0);
    signal s_opcode_n, s_memory_n, s_io_n, s_read_n, s_write_n, s_refresh_n, s_halted_n, s_bus_grant_n : std_logic;
begin
    o_opcode_fetch <= not s_opcode_n;
    o_memory_request <= not s_memory_n;
    o_io_request <= not s_io_n;
    o_read <= not s_read_n;
    o_write <= not s_write_n;
    o_refresh <= not s_refresh_n;
    o_halted <= not s_halted_n;
    o_bus_grant <= not s_bus_grant_n;
    original_cpu : if (not GBOOL_STATE_CAPABLE) generate
        o_capture_pending <= '0';
        o_state_held <= '0';
        ou256_state_data <= (others => '0');
        inactive_state_access : process(i_clk)
        begin
            if (rising_edge(i_clk)) then
                assert (i_capture_request = '0' and i_state_write = '0')
                    report "Z80 state access requires GBOOL_STATE_CAPABLE" severity failure;
            end if;
        end process;
        cpu : T80se
            generic map (
                Mode => 0,
                T2Write => 0,
                IOWait => 1
            )
            port map (
                RESET_n => not i_reset,
                CLK_n => i_clk,
                CLKEN => i_enable,
                WAIT_n => not i_wait,
                INT_n => not i_interrupt,
                NMI_n => not i_non_maskable_interrupt,
                BUSRQ_n => not i_bus_request,
                M1_n => s_opcode_n,
                MREQ_n => s_memory_n,
                IORQ_n => s_io_n,
                RD_n => s_read_n,
                WR_n => s_write_n,
                RFSH_n => s_refresh_n,
                HALT_n => s_halted_n,
                BUSAK_n => s_bus_grant_n,
                t_address(A) => ou16_address,
                DI => std_logic_vector(iu8_read_data),
                t_data(DO) => ou8_write_data
            );
    end generate;
    state_cpu : if (GBOOL_STATE_CAPABLE) generate
        assert (i_non_maskable_interrupt = '0' and i_bus_request = '0')
            report "RabbitPunch state CPU requires inactive NMI/BUSRQ" severity failure;
        s_bus_grant_n <= '1';
        cpu : rabbitpunch_t80_capture
            port map (
                i_clk => i_clk,
                i_reset_n => not i_reset,
                i_clock_enable => i_enable,
                i_wait_n => not i_wait,
                i_interrupt_n => not i_interrupt,
                o_opcode_fetch_n => s_opcode_n,
                o_memory_request_n => s_memory_n,
                o_io_request_n => s_io_n,
                o_read_n => s_read_n,
                o_write_n => s_write_n,
                o_refresh_n => s_refresh_n,
                o_halted_n => s_halted_n,
                ou16_address => ou16_address,
                iu8_read_data => iu8_read_data,
                ou8_write_data => ou8_write_data,
                i_capture_request => i_capture_request,
                i_cancel => i_capture_cancel,
                i_bus_drained => i_bus_drained,
                o_capture_pending => o_capture_pending,
                o_held => o_state_held,
                i_resume => i_state_resume,
                i_state_write => i_state_write,
                iu256_state_data => iu256_state_data,
                ou256_state_data => ou256_state_data,
                o_clean_boundary => open,
                ou3_machine_cycle => open,
                ou3_clock_phase => open
            );
    end generate;
end architecture;
