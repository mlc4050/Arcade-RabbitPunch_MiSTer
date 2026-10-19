-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One MAME hiscore.dat block, selected by validated per-game metadata.
-- The memory client is the production acknowledged maintenance byte port.
-- i_initialize/i_game_reset must also initialize that port: it drains backend
-- debt while discarding any canceled client reply. No fixed pause delay is used.
entity rabbitpunch_hiscore is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_reset : in std_logic;
        i_profile_valid : in std_logic;
        i_us_set : in std_logic;
        iu32_start_wait : in unsigned(31 downto 0);
        iu16_check_wait : in unsigned(15 downto 0);
        i_osd_open : in std_logic;
        i_autosave : in std_logic;
        i_manual_save : in std_logic := '0';
        i_dump_download : in std_logic;
        i_dump_write : in std_logic;
        i_dump_upload : in std_logic;
        iu27_dump_address : in unsigned(26 downto 0);
        iu8_dump_data : in unsigned(7 downto 0);
        ou8_dump_data : out unsigned(7 downto 0);
        o_dump_wait : out std_logic;
        o_upload_request : out std_logic;
        o_initialized : out std_logic;
        o_saved_valid : out std_logic;
        o_dirty : out std_logic;
        o_memory_access : out std_logic;
        o_memory_valid : out std_logic;
        o_memory_write : out std_logic;
        ou14_memory_address : out unsigned(13 downto 0);
        ou8_memory_data : out unsigned(7 downto 0);
        i_memory_ready : in std_logic;
        i_memory_response : in std_logic;
        iu8_memory_data : in unsigned(7 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_hiscore is
    type t_state is (STATE_IDLE, STATE_FIRST_ISSUE, STATE_FIRST_WAIT,
        STATE_LAST_ISSUE, STATE_LAST_WAIT, STATE_RESTORE_READ,
        STATE_RESTORE_ISSUE, STATE_RESTORE_WAIT, STATE_CAPTURE_ISSUE,
        STATE_CAPTURE_WAIT, STATE_CAPTURE_COMMIT);
    signal styp_state : t_state := STATE_IDLE;
    signal s_saved_bank, s_saved_valid, s_initialized : std_logic := '0';
    signal s_dirty, s_notified, s_changed, s_capture_pending : std_logic := '0';
    signal s_old_download, s_old_upload, s_old_osd, s_old_profile : std_logic := '0';
    signal s_download_bad : std_logic := '0';
    signal s_old_manual_save, s_manual_pending, s_manual_capture : std_logic := '0';
    signal su8_download_count : unsigned(7 downto 0) := (others => '0');
    signal su7_index : unsigned(6 downto 0) := (others => '0');
    signal su7_length : unsigned(6 downto 0);
    signal su8_last_guard : unsigned(7 downto 0);
    signal su32_wait : unsigned(31 downto 0) := (others => '0');
    signal s_store_enable, s_store_write : std_logic;
    signal su8_store_address, su8_store_data, su8_store_read : unsigned(7 downto 0);
    signal su8_view_address, su8_view_data : unsigned(7 downto 0);
    signal s_valid_download_byte : std_logic;
begin
    su7_length <= to_unsigned(115, 7) when i_us_set = '1' else to_unsigned(119, 7);
    su8_last_guard <= x"17" when i_us_set = '1' else x"80";
    o_initialized <= s_initialized;
    o_saved_valid <= s_saved_valid;
    o_dirty <= s_dirty;
    o_dump_wait <= '1' when styp_state /= STATE_IDLE else '0';
    o_memory_access <= '1' when styp_state /= STATE_IDLE else '0';
    o_memory_valid <= '1' when i_initialize = '0' and i_game_reset = '0' and
        (styp_state = STATE_FIRST_ISSUE or styp_state = STATE_LAST_ISSUE or
         styp_state = STATE_RESTORE_ISSUE or styp_state = STATE_CAPTURE_ISSUE) else '0';
    o_memory_write <= '1' when styp_state = STATE_RESTORE_ISSUE else '0';
    ou14_memory_address <= to_unsigned(16#3E01#, 14) + resize(su7_index, 14);
    ou8_memory_data <= su8_store_read;
    ou8_dump_data <= su8_view_data when s_saved_valid = '1' and
        iu27_dump_address < resize(su7_length, 27) else (others => '0');
    su8_view_address <= s_saved_bank & iu27_dump_address(6 downto 0) when i_dump_upload = '1'
        else s_saved_bank & su7_index;
    s_valid_download_byte <= '1' when i_dump_download = '1' and i_dump_write = '1' and
        i_profile_valid = '1' and styp_state = STATE_IDLE and s_download_bad = '0' and
        iu27_dump_address = resize(su8_download_count, 27) and
        su8_download_count < resize(su7_length, 8) else '0';
    s_store_enable <= '1' when s_valid_download_byte = '1' or styp_state = STATE_RESTORE_READ or
        (styp_state = STATE_CAPTURE_WAIT and i_memory_response = '1') else '0';
    s_store_write <= '0' when styp_state = STATE_RESTORE_READ else '1';
    su8_store_address <= (not s_saved_bank) & iu27_dump_address(6 downto 0) when s_valid_download_byte = '1'
        else s_saved_bank & su7_index when styp_state = STATE_RESTORE_READ
        else (not s_saved_bank) & su7_index;
    su8_store_data <= iu8_dump_data when s_valid_download_byte = '1' else iu8_memory_data;
    buffers : entity work.rabbitpunch_ram8
        generic map (
            GINT_ADDRESS_BITS => 8
        )
        port map (
            i_clk => i_clk,
            i_cpu_enable => s_store_enable,
            i_cpu_write => s_store_write,
            iux_cpu_address => su8_store_address,
            iu8_cpu_data => su8_store_data,
            ou8_cpu_data => su8_store_read,
            i_view_enable => '1',
            iux_view_address => su8_view_address,
            ou8_view_data => su8_view_data
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_upload_request <= '0';
            s_old_download <= i_dump_download;
            s_old_upload <= i_dump_upload;
            s_old_osd <= i_osd_open;
            s_old_manual_save <= i_manual_save;
            s_old_profile <= i_profile_valid;
            if (i_initialize = '1') then
                styp_state <= STATE_IDLE;
                s_saved_bank <= '0';
                s_saved_valid <= '0';
                s_initialized <= '0';
                s_dirty <= '0';
                s_notified <= '0';
                s_capture_pending <= '0';
                s_manual_pending <= '0';
                s_manual_capture <= '0';
                s_download_bad <= '0';
                su8_download_count <= (others => '0');
                su32_wait <= iu32_start_wait;
            elsif (i_profile_valid = '1' and s_old_profile = '0') then
                styp_state <= STATE_IDLE;
                s_saved_valid <= '0';
                s_initialized <= '0';
                s_dirty <= '0';
                s_notified <= '0';
                s_capture_pending <= '0';
                s_manual_pending <= '0';
                s_manual_capture <= '0';
                su32_wait <= iu32_start_wait;
            else
                -- Host snapshot loading is independent of the gameplay reset.
                -- Reset still cancels RAM work through the maintenance helper.
                if (i_dump_upload = '0' and s_old_upload = '1') then
                    s_dirty <= '0';
                    s_notified <= '0';
                end if;
                if (i_dump_download = '1') then
                    if (s_old_download = '0') then
                        su8_download_count <= (others => '0');
                        s_download_bad <= '0';
                    end if;
                    if (i_dump_write = '1') then
                        if (s_valid_download_byte = '1') then
                            su8_download_count <= su8_download_count + 1;
                        else
                            s_download_bad <= '1';
                        end if;
                    end if;
                elsif (s_old_download = '1') then
                    if (s_download_bad = '0' and su8_download_count = resize(su7_length, 8) and i_profile_valid = '1') then
                        s_saved_bank <= not s_saved_bank;
                        s_saved_valid <= '1';
                        s_initialized <= '0';
                        s_dirty <= '0';
                        s_notified <= '0';
                        su32_wait <= iu32_start_wait;
                    end if;
                end if;
                if (i_game_reset = '1') then
                    styp_state <= STATE_IDLE;
                    s_initialized <= '0';
                    s_capture_pending <= '0';
                    s_manual_pending <= '0';
                    s_manual_capture <= '0';
                    su32_wait <= iu32_start_wait;
                else
                    if (i_manual_save = '1' and s_old_manual_save = '0' and i_profile_valid = '1') then
                        s_manual_pending <= '1';
                        s_manual_capture <= '1';
                        s_capture_pending <= '1';
                    end if;
                    if (i_osd_open = '1' and s_old_osd = '0' and s_initialized = '1') then
                        s_capture_pending <= '1';
                    end if;
                    if (styp_state = STATE_IDLE and i_dump_download = '0' and i_dump_upload = '0' and
                        s_saved_valid = '1' and s_old_download = '0' and s_capture_pending = '0' and
                        ((s_dirty = '1' and s_notified = '0' and i_autosave = '1' and i_osd_open = '1') or
                         (s_manual_pending = '1' and s_manual_capture = '0'))) then
                        o_upload_request <= '1';
                        s_notified <= '1';
                        s_manual_pending <= '0';
                    end if;
                    -- Native HPS may announce a transfer while wait is asserted.
                    -- Finish accepted RAM work before admitting its first data byte.
                    if (styp_state /= STATE_IDLE or (i_dump_download = '0' and s_old_download = '0')) then
                        case styp_state is
                            when STATE_IDLE =>
                                if (i_profile_valid = '1' and i_dump_upload = '0') then
                                    if (s_initialized = '0') then
                                        if (su32_wait /= 0) then
                                            su32_wait <= su32_wait - 1;
                                        else
                                            su7_index <= (others => '0');
                                            styp_state <= STATE_FIRST_ISSUE;
                                        end if;
                                    elsif (s_capture_pending = '1') then
                                        su7_index <= (others => '0');
                                        s_changed <= not s_saved_valid;
                                        s_capture_pending <= '0';
                                        styp_state <= STATE_CAPTURE_ISSUE;
                                    end if;
                                end if;
                            when STATE_FIRST_ISSUE =>
                                if (i_memory_ready = '1') then
                                    styp_state <= STATE_FIRST_WAIT;
                                end if;
                            when STATE_FIRST_WAIT =>
                                if (i_memory_response = '1') then
                                    if (iu8_memory_data = 0) then
                                        su7_index <= su7_length - 1;
                                        styp_state <= STATE_LAST_ISSUE;
                                    else
                                        su32_wait <= resize(iu16_check_wait, 32);
                                        styp_state <= STATE_IDLE;
                                    end if;
                                end if;
                            when STATE_LAST_ISSUE =>
                                if (i_memory_ready = '1') then
                                    styp_state <= STATE_LAST_WAIT;
                                end if;
                            when STATE_LAST_WAIT =>
                                if (i_memory_response = '1') then
                                    if (iu8_memory_data = su8_last_guard) then
                                        su7_index <= (others => '0');
                                        if (s_saved_valid = '1') then
                                            styp_state <= STATE_RESTORE_READ;
                                        else
                                            s_changed <= '1';
                                            styp_state <= STATE_CAPTURE_ISSUE;
                                        end if;
                                    else
                                        su32_wait <= resize(iu16_check_wait, 32);
                                        styp_state <= STATE_IDLE;
                                    end if;
                                end if;
                            when STATE_RESTORE_READ =>
                                styp_state <= STATE_RESTORE_ISSUE;
                            when STATE_RESTORE_ISSUE =>
                                if (i_memory_ready = '1') then
                                    styp_state <= STATE_RESTORE_WAIT;
                                end if;
                            when STATE_RESTORE_WAIT =>
                                if (i_memory_response = '1') then
                                    if (su7_index = su7_length - 1) then
                                        s_initialized <= '1';
                                        s_capture_pending <= i_osd_open;
                                        styp_state <= STATE_IDLE;
                                    else
                                        su7_index <= su7_index + 1;
                                        styp_state <= STATE_RESTORE_READ;
                                    end if;
                                end if;
                            when STATE_CAPTURE_ISSUE =>
                                if (i_memory_ready = '1') then
                                    styp_state <= STATE_CAPTURE_WAIT;
                                end if;
                            when STATE_CAPTURE_WAIT =>
                                if (i_memory_response = '1') then
                                    if (s_saved_valid = '0' or i_dump_upload = '1' or iu8_memory_data /= su8_view_data) then
                                        s_changed <= '1';
                                    end if;
                                    if (su7_index = su7_length - 1) then
                                        styp_state <= STATE_CAPTURE_COMMIT;
                                    else
                                        su7_index <= su7_index + 1;
                                        styp_state <= STATE_CAPTURE_ISSUE;
                                    end if;
                                end if;
                            when STATE_CAPTURE_COMMIT =>
                                -- Never switch the read bank during an HPS transfer.
                                if (i_dump_upload = '0') then
                                    s_saved_bank <= not s_saved_bank;
                                    s_saved_valid <= '1';
                                    s_initialized <= '1';
                                    s_manual_capture <= '0';
                                    if (s_changed = '1') then
                                        s_dirty <= '1';
                                        s_notified <= '0';
                                    end if;
                                    styp_state <= STATE_IDLE;
                                end if;
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
