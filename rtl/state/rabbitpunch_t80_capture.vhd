-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library state_t80;

-- Evaluation boundary around the unchanged 230-bit donor. Capture only at a
-- drained, prefix-free fresh fetch after the previous interrupt decision.
-- RabbitPunch has no ordinary Z80 NMI or BUSRQ; both remain tied inactive.
-- The image adds the wrapper's input-data latch to the donor register bank.
-- No interrupt monitor or game-stack writes are used for acquisition.
entity rabbitpunch_t80_capture is
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
end entity;

architecture rtl of rabbitpunch_t80_capture is
    type t_prefix is (STATE_NONE, STATE_INDEX, STATE_ED, STATE_CB, STATE_INDEX_CB);
    signal styp_prefix : t_prefix := STATE_NONE;
    signal s_prefix_pending : std_logic := '0';
    signal s_ei_pending : std_logic := '0';
    signal s_pending, s_held, s_normalizing : std_logic := '0';
    signal s_enable, s_state_write, s_boundary, s_interrupt_cycle_n : std_logic;
    signal s_retire, s_load : std_logic;
    signal s_no_read, s_write, s_io, s_memory_n, s_io_n, s_read_n, s_write_n : std_logic := '1';
    signal s_refresh_n, s_bus_acknowledge_n : std_logic;
    signal su3_machine_cycle, su3_clock_phase : unsigned(2 downto 0);
    signal su2_instruction_set : unsigned(1 downto 0);
    signal su8_read_latch : unsigned(7 downto 0) := (others => '0');
    signal su230_registers : unsigned(229 downto 0);
    signal su230_load : unsigned(229 downto 0);
begin
    o_memory_request_n <= s_memory_n;
    o_io_request_n <= s_io_n;
    o_read_n <= s_read_n;
    o_write_n <= s_write_n;
    o_refresh_n <= s_refresh_n;
    o_capture_pending <= s_pending;
    o_held <= s_held;
    o_clean_boundary <= s_boundary;
    ou3_machine_cycle <= su3_machine_cycle;
    ou3_clock_phase <= su3_clock_phase;
    ou256_state_data <= to_unsigned(0, 18) & su8_read_latch & su230_registers;
    s_boundary <= '1' when su3_machine_cycle = 1 and su3_clock_phase = 1 and
        su2_instruction_set = 0 and s_prefix_pending = '0' and s_ei_pending = '0' and s_interrupt_cycle_n = '1' and
        s_memory_n = '1' and s_io_n = '1' and s_read_n = '1' and s_write_n = '1' and
        s_refresh_n = '1' and s_bus_acknowledge_n = '1' and i_bus_drained = '1' else '0';
    -- M1/T1 still commits the preceding instruction's delayed register write.
    -- Execute that edge without issuing its new fetch, then reload the retired
    -- architectural bank into the donor's clean fetch state. SAVE and RESTORE
    -- consequently resume the same pipeline, including after LD A,r or POP.
    s_retire <= (s_pending or i_capture_request) and s_boundary and
        i_clock_enable and not i_cancel and not s_held and not s_normalizing and i_reset_n;
    s_enable <= i_clock_enable and not s_held and not s_normalizing;
    s_state_write <= i_state_write and s_held and i_reset_n;
    s_load <= s_state_write or (s_normalizing and i_reset_n);
    su230_load <= su230_registers when s_normalizing = '1' else iu256_state_data(229 downto 0);
    core : entity state_t80.T80
        generic map (
            Mode => 0,
            IOWait => 1
        )
        port map (
            RESET_n => i_reset_n,
            CLK_n => i_clk,
            CEN => s_enable,
            WAIT_n => i_wait_n,
            INT_n => i_interrupt_n,
            NMI_n => '1',
            BUSRQ_n => '1',
            M1_n => o_opcode_fetch_n,
            IORQ => s_io,
            NoRead => s_no_read,
            Write => s_write,
            RFSH_n => s_refresh_n,
            HALT_n => o_halted_n,
            BUSAK_n => s_bus_acknowledge_n,
            unsigned(A) => ou16_address,
            DInst => std_logic_vector(iu8_read_data),
            DI => std_logic_vector(su8_read_latch),
            unsigned(DO) => ou8_write_data,
            unsigned(MC) => su3_machine_cycle,
            unsigned(TS) => su3_clock_phase,
            IntCycle_n => s_interrupt_cycle_n,
            IntE => open,
            Stop => open,
            out0 => '0',
            unsigned(REG) => su230_registers,
            DIRSet => s_load,
            DIR => std_logic_vector(su230_load),
            unsigned(ISet_out) => su2_instruction_set
        );
    acquisition : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            assert (i_state_write = '0' or s_held = '1')
                report "T80 image load requires a held clean boundary" severity failure;
            assert (i_state_write = '0' or iu256_state_data(255 downto 238) = 0)
                report "T80 image has nonzero reserved bits" severity failure;
            if (i_reset_n = '0') then
                s_pending <= '0';
                s_held <= '0';
                s_normalizing <= '0';
            elsif (s_normalizing = '1') then
                s_normalizing <= '0';
                s_held <= '1';
                s_pending <= '0';
            elsif (i_cancel = '1') then
                -- Cancel acquisition only. A held/partially loaded CPU stays
                -- held until the parent deliberately resumes or resets it.
                s_pending <= '0';
            elsif (s_held = '1') then
                if (i_resume = '1') then
                    s_held <= '0';
                    s_pending <= '0';
                end if;
            elsif (i_capture_request = '1' or s_pending = '1') then
                if (s_retire = '1') then
                    s_normalizing <= '1';
                    s_pending <= '1';
                else
                    s_pending <= '1';
                end if;
            end if;
        end if;
    end process;
    -- ISet_out describes the prior decode and alone misses the gap immediately
    -- after a prefix fetch. Track accepted M1 bytes too. Indexed-CB is treated
    -- conservatively: wait through its next M1 before another clean boundary.
    prefix_guard : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            if (i_reset_n = '0' or s_load = '1') then
                styp_prefix <= STATE_NONE;
                s_prefix_pending <= '0';
                s_ei_pending <= '0';
            elsif (s_enable = '1' and su3_machine_cycle = 1 and su3_clock_phase = 2 and i_wait_n = '1') then
                if (s_interrupt_cycle_n = '0' or o_halted_n = '0') then
                    styp_prefix <= STATE_NONE;
                    s_prefix_pending <= '0';
                    s_ei_pending <= '0';
                else
                    -- EI takes effect on the following M1 in this donor. Its
                    -- pending decode is not in REG and DIRSet clears IR.
                    -- Conservatively defer any FB byte until a later M1.
                    if (iu8_read_data = x"FB") then
                        s_ei_pending <= '1';
                    else
                        s_ei_pending <= '0';
                    end if;
                    case styp_prefix is
                        when STATE_ED | STATE_CB =>
                            styp_prefix <= STATE_NONE;
                            s_prefix_pending <= '0';
                        when STATE_INDEX =>
                            if (iu8_read_data = x"DD" or iu8_read_data = x"FD") then
                                styp_prefix <= STATE_INDEX;
                                s_prefix_pending <= '1';
                            elsif (iu8_read_data = x"ED") then
                                styp_prefix <= STATE_ED;
                                s_prefix_pending <= '1';
                            elsif (iu8_read_data = x"CB") then
                                styp_prefix <= STATE_INDEX_CB;
                                s_prefix_pending <= '1';
                            else
                                styp_prefix <= STATE_NONE;
                                s_prefix_pending <= '0';
                            end if;
                        when STATE_NONE | STATE_INDEX_CB =>
                            if (iu8_read_data = x"DD" or iu8_read_data = x"FD") then
                                styp_prefix <= STATE_INDEX;
                                s_prefix_pending <= '1';
                            elsif (iu8_read_data = x"ED") then
                                styp_prefix <= STATE_ED;
                                s_prefix_pending <= '1';
                            elsif (iu8_read_data = x"CB") then
                                styp_prefix <= STATE_CB;
                                s_prefix_pending <= '1';
                            else
                                styp_prefix <= STATE_NONE;
                                s_prefix_pending <= '0';
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;
    -- T80se/T80s-compatible rising-edge bus timing, with writes in T3.
    bus_timing : process(i_reset_n, i_clk)
    begin
        if (i_reset_n = '0') then
            s_read_n <= '1';
            s_write_n <= '1';
            s_io_n <= '1';
            s_memory_n <= '1';
            su8_read_latch <= (others => '0');
        elsif (rising_edge(i_clk)) then
            if (s_state_write = '1') then
                s_read_n <= '1';
                s_write_n <= '1';
                s_io_n <= '1';
                s_memory_n <= '1';
                su8_read_latch <= iu256_state_data(237 downto 230);
            elsif (s_normalizing = '1' or s_retire = '1') then
                -- No fetch was offered, so no external transaction is lost.
                s_read_n <= '1';
                s_write_n <= '1';
                s_io_n <= '1';
                s_memory_n <= '1';
            elsif (s_enable = '1') then
                s_read_n <= '1';
                s_write_n <= '1';
                s_io_n <= '1';
                s_memory_n <= '1';
                if (su3_machine_cycle = 1) then
                    if (su3_clock_phase = 1 or (su3_clock_phase = 2 and i_wait_n = '0')) then
                        s_read_n <= not s_interrupt_cycle_n;
                        s_memory_n <= not s_interrupt_cycle_n;
                        s_io_n <= s_interrupt_cycle_n;
                    end if;
                    if (su3_clock_phase = 3) then
                        s_memory_n <= '0';
                    end if;
                else
                    if ((su3_clock_phase = 1 or (su3_clock_phase = 2 and i_wait_n = '0')) and
                        s_no_read = '0' and s_write = '0') then
                        s_read_n <= '0';
                        s_io_n <= not s_io;
                        s_memory_n <= s_io;
                    end if;
                    if (su3_clock_phase = 2 and s_write = '1') then
                        s_write_n <= '0';
                        s_io_n <= not s_io;
                        s_memory_n <= s_io;
                    end if;
                end if;
                if (su3_clock_phase = 2 and i_wait_n = '1') then
                    su8_read_latch <= iu8_read_data;
                end if;
            end if;
        end if;
    end process;
end architecture;
