-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Arrival-test boundary only. The unchanged donor ignores DDR busy; queueing
-- and loader ownership must be added outside this adapter before production.
entity rabbitpunch_hdmi_rotation is
    port (
        i_clk : in std_logic;
        i_pixel_enable : in std_logic;
        iu8_red : in unsigned(7 downto 0);
        iu8_green : in unsigned(7 downto 0);
        iu8_blue : in unsigned(7 downto 0);
        i_horizontal_sync : in std_logic;
        i_vertical_sync : in std_logic;
        i_data_enable : in std_logic;
        i_enable : in std_logic;
        i_counterclockwise : in std_logic;
        i_framebuffer_vertical_blank : in std_logic;
        i_framebuffer_low_latency : in std_logic;
        o_enabled : out std_logic;
        ou5_format : out unsigned(4 downto 0);
        ou12_width : out unsigned(11 downto 0);
        ou12_height : out unsigned(11 downto 0);
        ou32_base : out unsigned(31 downto 0);
        ou14_stride : out unsigned(13 downto 0);
        i_ddr_busy : in std_logic;
        ou8_ddr_burst_count : out unsigned(7 downto 0);
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_data : out unsigned(63 downto 0);
        ou8_ddr_byte_enables : out unsigned(7 downto 0);
        o_ddr_write : out std_logic
    );
end entity;

architecture rtl of rabbitpunch_hdmi_rotation is
    component screen_rotate_two is
        port (
            CLK_VIDEO : in std_logic;
            CE_PIXEL : in std_logic;
            VGA_R : in unsigned(7 downto 0);
            VGA_G : in unsigned(7 downto 0);
            VGA_B : in unsigned(7 downto 0);
            VGA_HS : in std_logic;
            VGA_VS : in std_logic;
            VGA_DE : in std_logic;
            rotate_ccw : in std_logic;
            no_rotate : in std_logic;
            flip : in std_logic;
            two_screen : in std_logic;
            video_rotated : out std_logic;
            FB_EN : out std_logic;
            FB_FORMAT : out unsigned(4 downto 0);
            FB_WIDTH : out unsigned(11 downto 0);
            FB_HEIGHT : out unsigned(11 downto 0);
            FB_BASE : out unsigned(31 downto 0);
            FB_STRIDE : out unsigned(13 downto 0);
            FB_VBL : in std_logic;
            FB_LL : in std_logic;
            DDRAM_CLK : out std_logic;
            DDRAM_BUSY : in std_logic;
            DDRAM_BURSTCNT : out unsigned(7 downto 0);
            DDRAM_ADDR : out unsigned(28 downto 0);
            DDRAM_DIN : out unsigned(63 downto 0);
            DDRAM_BE : out unsigned(7 downto 0);
            DDRAM_WE : out std_logic;
            DDRAM_RD : out std_logic
        );
    end component;
    signal s_previous_video_sync, s_previous_framebuffer_blank : std_logic := '0';
    signal s_completed : std_logic := '0';
    signal su2_write_buffer : unsigned(1 downto 0) := "00";
    signal su2_read_buffer : unsigned(1 downto 0) := "01";
    signal su2_completed_buffer : unsigned(1 downto 0) := "10";
    signal su32_donor_base : unsigned(31 downto 0);
    signal su29_donor_address : unsigned(28 downto 0);

    function free_buffer(iu2_first : unsigned(1 downto 0);
        iu2_second : unsigned(1 downto 0)) return unsigned is
    begin
        for vint_buffer in 0 to 2 loop
            if (iu2_first /= vint_buffer and iu2_second /= vint_buffer) then
                return to_unsigned(vint_buffer, 2);
            end if;
        end loop;
        return to_unsigned(0, 2);
    end function;
begin
    -- Own only the slot indices; the unchanged donor still calculates every
    -- pixel offset, byte mask, format and stride. A single VHDL process can
    -- order coincident events explicitly without narrowing FB_VBL to a pulse.
    -- FB_VBL is already sampled on CLK_VIDEO by sys_top.
    -- Low-latency requests intentionally use safe triple buffering here until
    -- an end-to-end genlock/beam-racing contract is established.
    ou32_base <= su32_donor_base(31 downto 25) & su2_read_buffer & su32_donor_base(22 downto 0);
    ou29_ddr_word_address <= su29_donor_address(28 downto 22) & su2_write_buffer & su29_donor_address(19 downto 0);
    coordinate_buffers : process(i_clk)
        variable vu2_write, vu2_read, vu2_completed : unsigned(1 downto 0);
        variable v_completed : std_logic;
    begin
        if (rising_edge(i_clk)) then
            vu2_write := su2_write_buffer;
            vu2_read := su2_read_buffer;
            vu2_completed := su2_completed_buffer;
            v_completed := s_completed;
            if (i_vertical_sync = '1' and s_previous_video_sync = '0') then
                vu2_completed := su2_write_buffer;
                v_completed := '1';
                vu2_write := free_buffer(su2_write_buffer, su2_read_buffer);
            end if;
            if (i_framebuffer_vertical_blank = '1' and s_previous_framebuffer_blank = '0' and
                v_completed = '1' and vu2_completed /= vu2_write) then
                vu2_read := vu2_completed;
            end if;
            su2_write_buffer <= vu2_write;
            su2_read_buffer <= vu2_read;
            su2_completed_buffer <= vu2_completed;
            s_completed <= v_completed;
            s_previous_video_sync <= i_vertical_sync;
            s_previous_framebuffer_blank <= i_framebuffer_vertical_blank;
        end if;
    end process;
    rotation : screen_rotate_two
        port map (
            CLK_VIDEO => i_clk,
            CE_PIXEL => i_pixel_enable,
            VGA_R => iu8_red,
            VGA_G => iu8_green,
            VGA_B => iu8_blue,
            VGA_HS => i_horizontal_sync,
            VGA_VS => i_vertical_sync,
            VGA_DE => i_data_enable,
            rotate_ccw => i_counterclockwise,
            no_rotate => not i_enable,
            flip => '0',
            two_screen => '0',
            video_rotated => open,
            FB_EN => o_enabled,
            FB_FORMAT => ou5_format,
            FB_WIDTH => ou12_width,
            FB_HEIGHT => ou12_height,
            FB_BASE => su32_donor_base,
            FB_STRIDE => ou14_stride,
            FB_VBL => '0',
            FB_LL => '0',
            DDRAM_CLK => open,
            DDRAM_BUSY => i_ddr_busy,
            DDRAM_BURSTCNT => ou8_ddr_burst_count,
            DDRAM_ADDR => su29_donor_address,
            DDRAM_DIN => ou64_ddr_data,
            DDRAM_BE => ou8_ddr_byte_enables,
            DDRAM_WE => o_ddr_write,
            DDRAM_RD => open
        );
end architecture;
