-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- The imported GX monitor owns an off-board architectural register/frame bank.
-- A request is a pulse; held stalls its first bank read until resume. The
-- parent completes each CPU access once and holds reply data through AS_n.
entity rabbitpunch_m68k_capture is
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_bus_active : in std_logic;
        i_bus_complete : in std_logic;
        iu24_byte_address : in unsigned(23 downto 0);
        i_write : in std_logic;
        iu3_function_code : in unsigned(2 downto 0);
        iu16_write_data : in unsigned(15 downto 0);
        i_level7_acknowledge : in std_logic;
        i_stopped : in std_logic;
        i_capture_request : in std_logic;
        o_level7_request : out std_logic;
        o_overlay_selected : out std_logic;
        o_overlay_ready : out std_logic;
        ou16_overlay_data : out unsigned(15 downto 0);
        o_held : out std_logic;
        i_resume : in std_logic;
        o_completed : out std_logic;
        iu5_state_address : in unsigned(4 downto 0);
        i_state_write : in std_logic;
        iu32_state_data : in unsigned(31 downto 0);
        ou32_state_data : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_m68k_capture is
    component gx_ss_m68k is
        generic (M020 : integer := 1);
        port (
            clk, rst, acc, take : in std_logic;
            a32 : in unsigned(31 downto 0);
            wr : in std_logic;
            fc : in unsigned(2 downto 0);
            dout : in unsigned(15 downto 0);
            iack7, stop_in, req : in std_logic;
            ipl7, hit, rdy : out std_logic;
            din : out unsigned(15 downto 0);
            held : out std_logic;
            go : in std_logic;
            done : out std_logic;
            b_idx : in unsigned(4 downto 0);
            b_we : in std_logic;
            b_d : in unsigned(31 downto 0);
            b_q : out unsigned(31 downto 0)
        );
    end component;
begin
    capture : gx_ss_m68k
        generic map (
            M020 => 0
        )
        port map (
            clk => i_clk,
            rst => i_reset,
            acc => i_bus_active,
            take => i_bus_complete,
            a32 => resize(iu24_byte_address, 32),
            wr => i_write,
            fc => iu3_function_code,
            dout => iu16_write_data,
            iack7 => i_level7_acknowledge,
            stop_in => i_stopped,
            req => i_capture_request,
            ipl7 => o_level7_request,
            hit => o_overlay_selected,
            rdy => o_overlay_ready,
            din => ou16_overlay_data,
            held => o_held,
            go => i_resume,
            done => o_completed,
            b_idx => iu5_state_address,
            b_we => i_state_write,
            b_d => iu32_state_data,
            b_q => ou32_state_data
        );
end architecture;
