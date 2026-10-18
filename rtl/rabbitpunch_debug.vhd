-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Read-only instrumentation. Counters survive game reset and never drive game logic.
entity rabbitpunch_debug is
    generic (
        GBOOL_JTAG_ENABLE : boolean := true;
        GU32_BUILD_ID : unsigned(31 downto 0) := (others => '0');
        GINT_COUNTER_WIDTH : positive range 1 to 32 := 32
    );
    port (
        i_clk : in std_logic;
        i_pixel_enable : in std_logic;
        i_visible : in std_logic;
        i_vertical_sync : in std_logic;
        iu9_beam_x : in unsigned(8 downto 0);
        iu9_beam_y : in unsigned(8 downto 0);
        iu16_status : in unsigned(15 downto 0);
        i_cpu_request : in std_logic;
        i_cpu_write : in std_logic;
        iu24_cpu_address : in unsigned(23 downto 0);
        iu16_cpu_data : in unsigned(15 downto 0);
        iu2_cpu_bytes : in unsigned(1 downto 0);
        i_sound_request : in std_logic;
        i_sound_write : in std_logic;
        iu16_sound_address : in unsigned(15 downto 0);
        iu8_sound_data : in unsigned(7 downto 0);
        i_audio_sample : in std_logic;
        ou511_snapshot : out unsigned(510 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_debug is
    component altsource_probe is
        generic (
            instance_id : string := "UNUSED";
            probe_width : natural := 1;
            source_width : natural := 1;
            sld_auto_instance_index : string := "YES"
        );
        port (
            probe : in unsigned(probe_width - 1 downto 0);
            source_clk : in std_logic;
            source_ena : in std_logic;
            source : out unsigned(source_width - 1 downto 0)
        );
    end component;
    constant CU32_CORE_ID : unsigned(31 downto 0) := x"5250554E";
    constant CU32_COUNTER_MAX : unsigned(31 downto 0) := shift_right(unsigned'(x"FFFFFFFF"), 32 - GINT_COUNTER_WIDTH);
    signal su32_frames : unsigned(31 downto 0) := (others => '0');
    signal su32_cpu_requests : unsigned(31 downto 0) := (others => '0');
    signal su32_cpu_writes : unsigned(31 downto 0) := (others => '0');
    signal su32_sound_requests : unsigned(31 downto 0) := (others => '0');
    signal su32_visible_pixels : unsigned(31 downto 0) := (others => '0');
    signal su32_audio_samples : unsigned(31 downto 0) := (others => '0');
    signal su32_underflows : unsigned(31 downto 0) := (others => '0');
    signal su32_last_cpu_request : unsigned(31 downto 0) := (others => '0');
    signal su32_last_cpu_write : unsigned(31 downto 0) := (others => '0');
    signal su16_last_cpu_data : unsigned(15 downto 0) := (others => '0');
    signal su32_last_sound_request : unsigned(31 downto 0) := (others => '0');
    signal s_previous_sync : std_logic := '1';
    signal s_previous_underflow : std_logic := '0';
    signal su511_snapshot : unsigned(510 downto 0) := (others => '0');

    function increment_saturated(iu32_value : unsigned(31 downto 0)) return unsigned is
    begin
        if (iu32_value = CU32_COUNTER_MAX) then
            return iu32_value;
        end if;
        return iu32_value + 1;
    end function;
begin
    ou511_snapshot <= su511_snapshot;
    capture : process(i_clk)
        variable vu511_packet : unsigned(510 downto 0);
    begin
        if (rising_edge(i_clk)) then
            if (i_pixel_enable = '1') then
                s_previous_sync <= i_vertical_sync;
                if (s_previous_sync = '1' and i_vertical_sync = '0') then
                    su32_frames <= increment_saturated(su32_frames);
                end if;
                if (i_visible = '1') then
                    su32_visible_pixels <= increment_saturated(su32_visible_pixels);
                end if;
            end if;
            if (i_cpu_request = '1') then
                su32_cpu_requests <= increment_saturated(su32_cpu_requests);
                su32_last_cpu_request <= (others => '0');
                su32_last_cpu_request(23 downto 0) <= iu24_cpu_address;
                su32_last_cpu_request(24) <= i_cpu_write;
                if (i_cpu_write = '1') then
                    su32_cpu_writes <= increment_saturated(su32_cpu_writes);
                    su32_last_cpu_write <= (others => '0');
                    su32_last_cpu_write(23 downto 0) <= iu24_cpu_address;
                    su32_last_cpu_write(25 downto 24) <= iu2_cpu_bytes;
                    su16_last_cpu_data <= iu16_cpu_data;
                end if;
            end if;
            if (i_sound_request = '1') then
                su32_sound_requests <= increment_saturated(su32_sound_requests);
                su32_last_sound_request <= (others => '0');
                su32_last_sound_request(15 downto 0) <= iu16_sound_address;
                su32_last_sound_request(23 downto 16) <= iu8_sound_data;
                su32_last_sound_request(24) <= i_sound_write;
            end if;
            if (i_audio_sample = '1') then
                su32_audio_samples <= increment_saturated(su32_audio_samples);
            end if;
            s_previous_underflow <= iu16_status(5);
            if (iu16_status(5) = '1' and s_previous_underflow = '0') then
                su32_underflows <= increment_saturated(su32_underflows);
            end if;
            vu511_packet := (others => '0');
            vu511_packet(31 downto 0) := CU32_CORE_ID;
            vu511_packet(63 downto 32) := GU32_BUILD_ID;
            vu511_packet(95 downto 64) := su32_frames;
            vu511_packet(127 downto 96) := su32_cpu_requests;
            vu511_packet(159 downto 128) := su32_cpu_writes;
            vu511_packet(191 downto 160) := su32_sound_requests;
            vu511_packet(223 downto 192) := su32_visible_pixels;
            vu511_packet(255 downto 224) := su32_last_cpu_write;
            vu511_packet(271 downto 256) := su16_last_cpu_data;
            vu511_packet(319 downto 288) := su32_last_sound_request;
            vu511_packet(351 downto 320) := su32_last_cpu_request;
            vu511_packet(360 downto 352) := iu9_beam_x;
            vu511_packet(369 downto 361) := iu9_beam_y;
            vu511_packet(399 downto 384) := iu16_status;
            vu511_packet(447 downto 416) := su32_audio_samples;
            vu511_packet(479 downto 448) := su32_underflows;
            vu511_packet(510 downto 480) := to_unsigned(1, 31);
            su511_snapshot <= vu511_packet;
        end if;
    end process;
    hardware_probe : if (GBOOL_JTAG_ENABLE) generate
        probe : altsource_probe
            generic map (
                instance_id => "RPUN",
                probe_width => 511,
                source_width => 1,
                sld_auto_instance_index => "YES"
            )
            port map (
                probe => su511_snapshot,
                source_clk => i_clk,
                source_ena => '0',
                source => open
            );
    end generate;
end architecture;
