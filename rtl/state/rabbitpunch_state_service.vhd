-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_state_layout.all;

-- One immutable image lease spans copying, validation and application/publication.
-- Accepted read/write credits retain their client independently of service phase.
-- Save returns the machine before publishing; restore validates before acquisition.
entity rabbitpunch_state_service is
    port (
        i_clk : in std_logic;
        i_initialize : in std_logic;
        i_game_reset_completed : in std_logic;
        i_save : in std_logic;
        i_restore : in std_logic;
        i_cancel : in std_logic;
        iu2_slot : in unsigned(1 downto 0);
        i_rom_identity_valid : in std_logic;
        iu32_abi_signature : in unsigned(31 downto 0);
        iu32_rom_identity : in unsigned(31 downto 0);
        iu32_config_identity : in unsigned(31 downto 0);
        o_ready : out std_logic;
        o_busy : out std_logic;
        o_finished : out std_logic := '0';
        o_success : out std_logic := '0';
        o_restoring : out std_logic;
        o_incomplete : out std_logic;
        ou8_error : out unsigned(7 downto 0);
        i_machine_ready : in std_logic;
        i_machine_busy : in std_logic;
        i_machine_held : in std_logic;
        i_machine_finished : in std_logic;
        iu4_machine_error : in unsigned(3 downto 0);
        o_machine_acquire : out std_logic;
        o_machine_cancel : out std_logic;
        o_machine_release : out std_logic;
        o_body_apply_begin : out std_logic;
        o_body_request : out std_logic;
        i_body_ready : in std_logic;
        o_body_write : out std_logic;
        ou18_body_address : out unsigned(17 downto 0);
        ou8_body_data : out unsigned(7 downto 0);
        i_body_response : in std_logic;
        i_body_error : in std_logic;
        iu8_body_data : in unsigned(7 downto 0);
        o_body_commit : out std_logic;
        i_body_committed : in std_logic;
        i_body_commit_error : in std_logic;
        o_ddr_read : out std_logic;
        o_ddr_write : out std_logic;
        ou29_ddr_word_address : out unsigned(28 downto 0);
        ou64_ddr_write_data : out unsigned(63 downto 0);
        i_ddr_busy : in std_logic;
        i_ddr_read_valid : in std_logic;
        iu64_ddr_read_data : in unsigned(63 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_state_service is
    type t_state is (STATE_RESET_DRAIN, STATE_IDLE, STATE_BUFFER_BEGIN,
        STATE_READER_START, STATE_READER_WAIT, STATE_SEAL,
        STATE_ACQUIRE, STATE_ACQUIRE_WAIT, STATE_SNAPSHOT_START,
        STATE_SNAPSHOT_WAIT, STATE_VALIDATE_START, STATE_VALIDATE_WAIT,
        STATE_APPLY_BEGIN, STATE_APPLY_START, STATE_APPLY_WAIT,
        STATE_RELEASE, STATE_RELEASE_WAIT, STATE_PUBLISH_START,
        STATE_PUBLISH_WAIT, STATE_ERROR_DRAIN, STATE_SUCCESS);
    type t_image_owner is (STATE_IMAGE_NONE, STATE_IMAGE_VALIDATOR,
        STATE_IMAGE_APPLY, STATE_IMAGE_PUBLISH);
    type t_body_owner is (STATE_BODY_NONE, STATE_BODY_SNAPSHOT, STATE_BODY_APPLY);
    type t_ddr_owner is (STATE_DDR_NONE, STATE_DDR_READER, STATE_DDR_PUBLISH);
    signal styp_state : t_state := STATE_RESET_DRAIN;
    signal styp_image_owner : t_image_owner := STATE_IMAGE_NONE;
    signal styp_body_owner : t_body_owner := STATE_BODY_NONE;
    signal styp_ddr_owner : t_ddr_owner := STATE_DDR_NONE;
    signal s_restore, s_abort, s_changed, s_quiet, s_reset_pending, s_reset_ack : std_logic := '0';
    signal s_cancel_sent : std_logic := '0';
    signal s_client_cancel : std_logic;
    signal su2_slot : unsigned(1 downto 0) := (others => '0');
    signal su32_rom, su32_config, su32_abi : unsigned(31 downto 0) := (others => '0');
    signal su8_error : unsigned(7 downto 0) := (others => '0');
    signal s_snapshot_start, s_reader_start, s_validator_start, s_apply_start, s_publish_start : std_logic;
    signal s_buffer_begin, s_buffer_cancel, s_buffer_fill, s_buffer_seal : std_logic;
    signal su8_buffer_fill_data : unsigned(7 downto 0);
    signal s_image_request, s_snapshot_body_response, s_apply_body_response : std_logic;
    signal su18_image_address : unsigned(17 downto 0);
    signal s_validator_image_response, s_apply_image_response, s_publish_image_response : std_logic;
    signal s_reader_ddr_response, s_publish_ddr_response : std_logic;
    signal s_snapshot_machine_hold_request : std_logic;
    signal s_snapshot_body_request : std_logic;
    signal su18_snapshot_body_address : unsigned(17 downto 0);
    signal s_snapshot_image_begin : std_logic;
    signal s_snapshot_image_cancel : std_logic;
    signal s_snapshot_image_valid : std_logic;
    signal su8_snapshot_image_data : unsigned(7 downto 0);
    signal s_snapshot_image_seal : std_logic;
    signal s_snapshot_active : std_logic;
    signal s_snapshot_finished : std_logic;
    signal s_snapshot_success : std_logic;
    signal su4_snapshot_error : unsigned(3 downto 0);
    signal s_reader_byte_valid : std_logic;
    signal su8_reader_byte_data : unsigned(7 downto 0);
    signal s_reader_active : std_logic;
    signal s_reader_finished : std_logic;
    signal s_reader_success : std_logic;
    signal su3_reader_error : unsigned(2 downto 0);
    signal s_reader_ddr_read : std_logic;
    signal su29_reader_ddr_word_address : unsigned(28 downto 0);
    signal s_validator_image_read : std_logic;
    signal su18_validator_image_address : unsigned(17 downto 0);
    signal s_validator_active : std_logic;
    signal s_validator_finished : std_logic;
    signal s_validator_valid : std_logic;
    signal su6_validator_error : unsigned(5 downto 0);
    signal s_apply_machine_hold_request : std_logic;
    signal s_apply_image_read : std_logic;
    signal su18_apply_image_address : unsigned(17 downto 0);
    signal s_apply_body_request : std_logic;
    signal su18_apply_body_address : unsigned(17 downto 0);
    signal su8_apply_body_data : unsigned(7 downto 0);
    signal s_apply_body_commit : std_logic;
    signal s_apply_active : std_logic;
    signal s_apply_finished : std_logic;
    signal s_apply_success : std_logic;
    signal s_apply_incomplete : std_logic;
    signal su4_apply_error : unsigned(3 downto 0);
    signal s_publish_image_read : std_logic;
    signal su18_publish_image_address : unsigned(17 downto 0);
    signal s_publish_ddr_read : std_logic;
    signal s_publish_ddr_write : std_logic;
    signal su29_publish_ddr_word_address : unsigned(28 downto 0);
    signal su64_publish_ddr_write_data : unsigned(63 downto 0);
    signal s_publish_active : std_logic;
    signal s_publish_finished : std_logic;
    signal s_publish_success : std_logic;
    signal su3_publish_error : unsigned(2 downto 0);
    signal s_buffer_fill_ready : std_logic;
    signal s_buffer_sealed : std_logic;
    signal s_buffer_error : std_logic;
    signal su18_buffer_filled_bytes : unsigned(17 downto 0);
    signal s_buffer_read_response : std_logic;
    signal s_buffer_read_error : std_logic;
    signal su8_buffer_read_data : unsigned(7 downto 0);
begin
    o_ready <= '1' when styp_state = STATE_IDLE and i_initialize = '0' and
        i_rom_identity_valid = '1' and (i_machine_ready = '1' or
        (s_apply_incomplete = '1' and i_machine_held = '1')) else '0';
    o_busy <= '0' when styp_state = STATE_IDLE else '1';
    o_restoring <= s_restore;
    o_incomplete <= s_apply_incomplete;
    ou8_error <= su8_error;
    s_changed <= '1' when i_rom_identity_valid /= '1' or iu32_rom_identity /= su32_rom or
        iu32_config_identity /= su32_config or iu32_abi_signature /= su32_abi else '0';
    s_abort <= '1' when i_initialize = '1' or styp_state = STATE_ERROR_DRAIN or
        styp_state = STATE_RESET_DRAIN or (styp_state /= STATE_IDLE and
        styp_state /= STATE_SUCCESS and (i_cancel = '1' or s_changed = '1')) else '0';
    -- Child cancellation is an event. Holding it through cleanup would keep
    -- snapshot/validator FAIL states from retiring to IDLE after their debt.
    s_client_cancel <= s_abort and not s_cancel_sent;
    s_quiet <= '1' when s_snapshot_active = '0' and s_reader_active = '0' and
        s_validator_active = '0' and s_apply_active = '0' and s_publish_active = '0' and
        styp_image_owner = STATE_IMAGE_NONE and styp_body_owner = STATE_BODY_NONE and
        styp_ddr_owner = STATE_DDR_NONE else '0';
    s_reset_ack <= s_reset_pending and s_quiet;
    s_snapshot_start <= '1' when styp_state = STATE_SNAPSHOT_START and s_abort = '0' else '0';
    s_reader_start <= '1' when styp_state = STATE_READER_START and s_abort = '0' else '0';
    s_validator_start <= '1' when styp_state = STATE_VALIDATE_START and s_abort = '0' else '0';
    s_apply_start <= '1' when styp_state = STATE_APPLY_START and s_abort = '0' else '0';
    s_publish_start <= '1' when styp_state = STATE_PUBLISH_START and s_abort = '0' else '0';
    o_machine_acquire <= '1' when styp_state = STATE_ACQUIRE and s_abort = '0' else '0';
    o_machine_cancel <= s_abort when styp_state /= STATE_IDLE else '0';
    o_machine_release <= '1' when styp_state = STATE_RELEASE or
        (styp_state = STATE_ERROR_DRAIN and s_quiet = '1' and i_machine_held = '1') else '0';
    o_body_apply_begin <= '1' when styp_state = STATE_APPLY_BEGIN and s_abort = '0' else '0';
    o_body_request <= s_snapshot_body_request or s_apply_body_request;
    o_body_write <= s_apply_body_request;
    ou18_body_address <= su18_apply_body_address when s_apply_body_request = '1' else su18_snapshot_body_address;
    ou8_body_data <= su8_apply_body_data;
    o_body_commit <= s_apply_body_commit;
    s_snapshot_body_response <= i_body_response when styp_body_owner = STATE_BODY_SNAPSHOT else '0';
    s_apply_body_response <= i_body_response when styp_body_owner = STATE_BODY_APPLY else '0';
    s_image_request <= s_validator_image_read or s_apply_image_read or s_publish_image_read;
    su18_image_address <= su18_validator_image_address when s_validator_image_read = '1' else
        su18_apply_image_address when s_apply_image_read = '1' else su18_publish_image_address;
    s_validator_image_response <= s_buffer_read_response when styp_image_owner = STATE_IMAGE_VALIDATOR else '0';
    s_apply_image_response <= s_buffer_read_response when styp_image_owner = STATE_IMAGE_APPLY else '0';
    s_publish_image_response <= s_buffer_read_response when styp_image_owner = STATE_IMAGE_PUBLISH else '0';
    s_buffer_begin <= '1' when styp_state = STATE_BUFFER_BEGIN and s_abort = '0' else s_snapshot_image_begin;
    s_buffer_fill <= s_snapshot_image_valid or s_reader_byte_valid;
    su8_buffer_fill_data <= su8_snapshot_image_data when s_snapshot_image_valid = '1' else su8_reader_byte_data;
    s_buffer_seal <= '1' when styp_state = STATE_SEAL and s_abort = '0' else s_snapshot_image_seal;
    s_buffer_cancel <= '1' when styp_state = STATE_ERROR_DRAIN and s_quiet = '1' else s_snapshot_image_cancel;
    o_ddr_read <= s_reader_ddr_read or s_publish_ddr_read;
    o_ddr_write <= s_publish_ddr_write;
    ou29_ddr_word_address <= su29_publish_ddr_word_address when
        s_publish_ddr_read = '1' or s_publish_ddr_write = '1' else su29_reader_ddr_word_address;
    ou64_ddr_write_data <= su64_publish_ddr_write_data;
    s_reader_ddr_response <= i_ddr_read_valid when styp_ddr_owner = STATE_DDR_READER else '0';
    s_publish_ddr_response <= i_ddr_read_valid when styp_ddr_owner = STATE_DDR_PUBLISH else '0';
    ownership : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            -- Reset cancels clients, never clears an outstanding owner.
            if (s_buffer_read_response = '1') then
                assert (styp_image_owner /= STATE_IMAGE_NONE) report "Unowned service image reply" severity failure;
                styp_image_owner <= STATE_IMAGE_NONE;
            end if;
            if (s_image_request = '1') then
                assert (styp_image_owner = STATE_IMAGE_NONE and s_buffer_sealed = '1') report "Overlapping service image credit" severity failure;
                if (s_validator_image_read = '1') then
                    styp_image_owner <= STATE_IMAGE_VALIDATOR;
                elsif (s_apply_image_read = '1') then
                    styp_image_owner <= STATE_IMAGE_APPLY;
                else
                    styp_image_owner <= STATE_IMAGE_PUBLISH;
                end if;
            end if;
            if (i_body_response = '1') then
                assert (styp_body_owner /= STATE_BODY_NONE) report "Unowned service body reply" severity failure;
                styp_body_owner <= STATE_BODY_NONE;
            end if;
            if (o_body_request = '1' and i_body_ready = '1') then
                assert (styp_body_owner = STATE_BODY_NONE) report "Overlapping service body credit" severity failure;
                if (s_apply_body_request = '1') then
                    styp_body_owner <= STATE_BODY_APPLY;
                else
                    styp_body_owner <= STATE_BODY_SNAPSHOT;
                end if;
            end if;
            if (i_ddr_read_valid = '1') then
                assert (styp_ddr_owner /= STATE_DDR_NONE) report "Unowned service DDR reply" severity failure;
                styp_ddr_owner <= STATE_DDR_NONE;
            end if;
            if (o_ddr_read = '1' and i_ddr_busy = '0') then
                assert (styp_ddr_owner = STATE_DDR_NONE) report "Overlapping service DDR credit" severity failure;
                if (s_reader_ddr_read = '1') then
                    styp_ddr_owner <= STATE_DDR_READER;
                else
                    styp_ddr_owner <= STATE_DDR_PUBLISH;
                end if;
            end if;
        end if;
    end process;
    control : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_finished <= '0';
            o_success <= '0';
            if (styp_state = STATE_IDLE and s_abort = '0') then
                s_cancel_sent <= '0';
            elsif (s_abort = '1') then
                s_cancel_sent <= '1';
            end if;
            if (i_game_reset_completed = '1') then
                s_reset_pending <= '1';
            elsif (s_reset_ack = '1') then
                s_reset_pending <= '0';
            end if;
            if (i_initialize = '1') then
                styp_state <= STATE_RESET_DRAIN;
                su8_error <= (others => '0');
            elsif (s_abort = '1' and styp_state /= STATE_ERROR_DRAIN and styp_state /= STATE_RESET_DRAIN) then
                styp_state <= STATE_ERROR_DRAIN;
                if (i_cancel = '1') then
                    su8_error <= x"01";
                else
                    su8_error <= x"02";
                end if;
            else
                case styp_state is
                    when STATE_RESET_DRAIN =>
                        if (s_quiet = '1') then
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_IDLE =>
                        if (o_ready = '1' and (i_restore = '1' or (i_save = '1' and s_apply_incomplete = '0'))) then
                            su2_slot <= iu2_slot;
                            su32_rom <= iu32_rom_identity;
                            su32_config <= iu32_config_identity;
                            su32_abi <= iu32_abi_signature;
                            su8_error <= (others => '0');
                            s_restore <= i_restore;
                            if (i_restore = '1') then
                                styp_state <= STATE_BUFFER_BEGIN;
                            else
                                styp_state <= STATE_ACQUIRE;
                            end if;
                        end if;
                    when STATE_BUFFER_BEGIN => styp_state <= STATE_READER_START;
                    when STATE_READER_START => styp_state <= STATE_READER_WAIT;
                    when STATE_READER_WAIT =>
                        if (s_reader_finished = '1') then
                            if (s_reader_success = '1') then
                                styp_state <= STATE_SEAL;
                            else
                                su8_error <= x"10" or resize(su3_reader_error, 8);
                                styp_state <= STATE_ERROR_DRAIN;
                            end if;
                        end if;
                    when STATE_SEAL => styp_state <= STATE_VALIDATE_START;
                    when STATE_ACQUIRE =>
                        if (i_machine_held = '1') then
                            if (s_restore = '1') then
                                styp_state <= STATE_APPLY_BEGIN;
                            else
                                styp_state <= STATE_SNAPSHOT_START;
                            end if;
                        else
                            styp_state <= STATE_ACQUIRE_WAIT;
                        end if;
                    when STATE_ACQUIRE_WAIT =>
                        if (i_machine_held = '1') then
                            if (s_restore = '1') then
                                styp_state <= STATE_APPLY_BEGIN;
                            else
                                styp_state <= STATE_SNAPSHOT_START;
                            end if;
                        elsif (i_machine_finished = '1' and iu4_machine_error /= 0) then
                            su8_error <= x"80" or resize(iu4_machine_error, 8);
                            styp_state <= STATE_ERROR_DRAIN;
                        end if;
                    when STATE_SNAPSHOT_START => styp_state <= STATE_SNAPSHOT_WAIT;
                    when STATE_SNAPSHOT_WAIT =>
                        if (s_snapshot_finished = '1') then
                            if (s_snapshot_success = '1') then
                                styp_state <= STATE_VALIDATE_START;
                            else
                                su8_error <= x"20" or resize(su4_snapshot_error, 8);
                                styp_state <= STATE_ERROR_DRAIN;
                            end if;
                        end if;
                    when STATE_VALIDATE_START => styp_state <= STATE_VALIDATE_WAIT;
                    when STATE_VALIDATE_WAIT =>
                        if (s_validator_finished = '1') then
                            if (s_validator_valid = '1') then
                                if (s_restore = '1') then
                                    styp_state <= STATE_ACQUIRE;
                                else
                                    styp_state <= STATE_RELEASE;
                                end if;
                            else
                                su8_error <= x"40" or resize(su6_validator_error, 8);
                                styp_state <= STATE_ERROR_DRAIN;
                            end if;
                        end if;
                    when STATE_APPLY_BEGIN => styp_state <= STATE_APPLY_START;
                    when STATE_APPLY_START => styp_state <= STATE_APPLY_WAIT;
                    when STATE_APPLY_WAIT =>
                        if (s_apply_finished = '1') then
                            if (s_apply_success = '1') then
                                styp_state <= STATE_RELEASE;
                            else
                                su8_error <= x"30" or resize(su4_apply_error, 8);
                                styp_state <= STATE_ERROR_DRAIN;
                            end if;
                        end if;
                    when STATE_RELEASE => styp_state <= STATE_RELEASE_WAIT;
                    when STATE_RELEASE_WAIT =>
                        if (i_machine_finished = '1') then
                            if (iu4_machine_error /= 0) then
                                su8_error <= x"80" or resize(iu4_machine_error, 8);
                                styp_state <= STATE_ERROR_DRAIN;
                            elsif (s_restore = '1') then
                                styp_state <= STATE_SUCCESS;
                            else
                                styp_state <= STATE_PUBLISH_START;
                            end if;
                        end if;
                    when STATE_PUBLISH_START => styp_state <= STATE_PUBLISH_WAIT;
                    when STATE_PUBLISH_WAIT =>
                        if (s_publish_finished = '1') then
                            if (s_publish_success = '1') then
                                styp_state <= STATE_SUCCESS;
                            else
                                su8_error <= x"90" or resize(su3_publish_error, 8);
                                styp_state <= STATE_ERROR_DRAIN;
                            end if;
                        end if;
                    when STATE_ERROR_DRAIN =>
                        if (s_quiet = '1' and (i_machine_busy = '0' or s_apply_incomplete = '1' or iu4_machine_error /= 0)) then
                            o_finished <= '1';
                            styp_state <= STATE_IDLE;
                        end if;
                    when STATE_SUCCESS =>
                        assert (s_quiet = '1' and s_apply_incomplete = '0') report "Service completed with outstanding debt" severity failure;
                        o_finished <= '1';
                        o_success <= '1';
                        styp_state <= STATE_IDLE;
                end case;
            end if;
        end if;
    end process;
    snapshot : entity work.rabbitpunch_state_snapshot
        generic map (
            GINT_BODY_BYTES => CINT_BODY_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_snapshot_start,
            i_cancel => s_client_cancel,
            i_rom_identity_valid => i_rom_identity_valid,
            iu32_abi_signature => iu32_abi_signature,
            iu32_rom_identity => iu32_rom_identity,
            iu32_config_identity => iu32_config_identity,
            iu192_section_bytes => CU192_SECTION_BYTES,
            o_machine_hold_request => s_snapshot_machine_hold_request,
            i_machine_held => i_machine_held,
            o_body_request => s_snapshot_body_request,
            i_body_ready => i_body_ready,
            ou18_body_address => su18_snapshot_body_address,
            i_body_response => s_snapshot_body_response,
            i_body_error => i_body_error,
            iu8_body_data => iu8_body_data,
            o_image_begin => s_snapshot_image_begin,
            o_image_cancel => s_snapshot_image_cancel,
            o_image_valid => s_snapshot_image_valid,
            i_image_ready => s_buffer_fill_ready,
            ou8_image_data => su8_snapshot_image_data,
            o_image_seal => s_snapshot_image_seal,
            o_active => s_snapshot_active,
            o_finished => s_snapshot_finished,
            o_success => s_snapshot_success,
            ou4_error => su4_snapshot_error
        );
    reader : entity work.rabbitpunch_state_slot_reader
        generic map (
            GINT_PAYLOAD_BYTES => CINT_IMAGE_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_reader_start,
            i_cancel => s_client_cancel,
            iu2_slot => su2_slot,
            o_byte_valid => s_reader_byte_valid,
            i_byte_ready => s_buffer_fill_ready,
            ou8_byte_data => su8_reader_byte_data,
            o_active => s_reader_active,
            o_finished => s_reader_finished,
            o_success => s_reader_success,
            ou3_error => su3_reader_error,
            o_ddr_read => s_reader_ddr_read,
            ou29_ddr_word_address => su29_reader_ddr_word_address,
            i_ddr_busy => i_ddr_busy,
            i_ddr_read_valid => s_reader_ddr_response,
            iu64_ddr_read_data => iu64_ddr_read_data
        );
    validator : entity work.rabbitpunch_state_image_validator
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_validator_start,
            i_cancel => s_client_cancel,
            i_image_sealed => s_buffer_sealed,
            i_rom_identity_valid => i_rom_identity_valid,
            iu32_abi_signature => iu32_abi_signature,
            iu32_rom_identity => iu32_rom_identity,
            iu32_config_identity => iu32_config_identity,
            o_image_read => s_validator_image_read,
            ou18_image_address => su18_validator_image_address,
            i_image_response => s_validator_image_response,
            i_image_error => s_buffer_read_error,
            iu8_image_data => su8_buffer_read_data,
            o_active => s_validator_active,
            o_finished => s_validator_finished,
            o_valid => s_validator_valid,
            ou6_error => su6_validator_error
        );
    apply : entity work.rabbitpunch_state_apply
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_game_reset_completed => s_reset_ack,
            i_start => s_apply_start,
            i_cancel => s_client_cancel,
            i_image_valid => s_validator_valid,
            i_machine_held => i_machine_held,
            o_machine_hold_request => s_apply_machine_hold_request,
            o_image_read => s_apply_image_read,
            ou18_image_address => su18_apply_image_address,
            i_image_response => s_apply_image_response,
            i_image_error => s_buffer_read_error,
            iu8_image_data => su8_buffer_read_data,
            o_body_request => s_apply_body_request,
            i_body_ready => i_body_ready,
            ou18_body_address => su18_apply_body_address,
            ou8_body_data => su8_apply_body_data,
            i_body_response => s_apply_body_response,
            i_body_error => i_body_error,
            o_body_commit => s_apply_body_commit,
            i_body_committed => i_body_committed,
            i_body_commit_error => i_body_commit_error,
            o_active => s_apply_active,
            o_finished => s_apply_finished,
            o_success => s_apply_success,
            o_incomplete => s_apply_incomplete,
            ou4_error => su4_apply_error
        );
    publish : entity work.rabbitpunch_state_publish
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_start => s_publish_start,
            i_cancel => s_client_cancel,
            i_image_valid => s_validator_valid,
            iu2_slot => su2_slot,
            o_image_read => s_publish_image_read,
            ou18_image_address => su18_publish_image_address,
            i_image_response => s_publish_image_response,
            i_image_error => s_buffer_read_error,
            iu8_image_data => su8_buffer_read_data,
            o_ddr_read => s_publish_ddr_read,
            o_ddr_write => s_publish_ddr_write,
            ou29_ddr_word_address => su29_publish_ddr_word_address,
            ou64_ddr_write_data => su64_publish_ddr_write_data,
            i_ddr_busy => i_ddr_busy,
            i_ddr_read_valid => s_publish_ddr_response,
            iu64_ddr_read_data => iu64_ddr_read_data,
            o_active => s_publish_active,
            o_finished => s_publish_finished,
            o_success => s_publish_success,
            ou3_error => su3_publish_error
        );
    image_store : entity work.rabbitpunch_state_image_buffer
        generic map (
            GINT_IMAGE_BYTES => CINT_IMAGE_BYTES
        )
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            i_begin => s_buffer_begin,
            i_cancel => s_buffer_cancel,
            i_fill_valid => s_buffer_fill,
            o_fill_ready => s_buffer_fill_ready,
            iu8_fill_data => su8_buffer_fill_data,
            i_seal => s_buffer_seal,
            o_sealed => s_buffer_sealed,
            o_error => s_buffer_error,
            ou18_filled_bytes => su18_buffer_filled_bytes,
            i_read_valid => s_image_request,
            iu18_read_address => su18_image_address,
            o_read_response => s_buffer_read_response,
            o_read_error => s_buffer_read_error,
            ou8_read_data => su8_buffer_read_data
        );
end architecture;
