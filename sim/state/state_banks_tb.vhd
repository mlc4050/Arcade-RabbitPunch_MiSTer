-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 RabbitPunch contributors
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_state_layout.all;

entity state_banks_tb is
end entity;

architecture test of state_banks_tb is
    type t_words is array(natural range <>) of unsigned(31 downto 0);
    type t_bytes is array(natural range <>) of unsigned(7 downto 0);
    function F_BYTE(vint_address, vint_epoch : natural) return unsigned is
        variable vint_word : natural;
    begin
        if (vint_address >= CINT_M68K_BASE and vint_address < CINT_T80_BASE) then
            vint_word := (vint_address - CINT_M68K_BASE)/4;
            if (vint_word = 16 or vint_word = 17 or vint_word = 21 or vint_word = 23) then
                return x"00";
            end if;
        elsif (vint_address >= CINT_ADPCM_BASE - 2 and vint_address < CINT_ADPCM_BASE) then
            return x"00";
        elsif (vint_address = CINT_BODY_BYTES - 1) then
            return to_unsigned((vint_address*29 + vint_address/256 +
                (vint_address/65536)*113 + vint_epoch*71 + 7) mod 32, 8);
        end if;
        return to_unsigned((vint_address*29 + vint_address/256 +
            (vint_address/65536)*113 + vint_epoch*71 + 7) mod 256, 8);
    end function;
    function F_WORD(vint_address, vint_epoch : natural) return unsigned is
        variable vu32_data : unsigned(31 downto 0);
    begin
        for vint_lane in 0 to 3 loop
            vu32_data(8*vint_lane + 7 downto 8*vint_lane) := F_BYTE(vint_address + vint_lane, vint_epoch);
        end loop;
        return vu32_data;
    end function;
    function F_WORDS(vint_base, vint_count : natural) return t_words is
        variable vu32_data : t_words(0 to vint_count - 1);
    begin
        for vint_word in vu32_data'range loop
            vu32_data(vint_word) := F_WORD(vint_base + 4*vint_word, 0);
        end loop;
        return vu32_data;
    end function;
    function F_BYTES return t_bytes is
        variable vu8_data : t_bytes(0 to CINT_RAM_BYTES - 1);
    begin
        for vint_byte in vu8_data'range loop
            vu8_data(vint_byte) := F_BYTE(vint_byte, 0);
        end loop;
        return vu8_data;
    end function;
    function F_WIDE(vint_base, vint_size : natural) return unsigned is
        variable vux_data : unsigned(8*vint_size - 1 downto 0);
    begin
        for vint_byte in 0 to vint_size - 1 loop
            vux_data(8*vint_byte + 7 downto 8*vint_byte) := F_BYTE(vint_base + vint_byte, 0);
        end loop;
        return vux_data;
    end function;
    signal s_main_request, s_main_write, s_main_response : std_logic;
    signal s_sound_request, s_sound_write, s_sound_response : std_logic;
    signal s_pending_sound : std_logic := '0';
    signal su24_main_address : unsigned(23 downto 0);
    signal su16_main_write_data, su16_main_read_data, su16_sound_address : unsigned(15 downto 0);
    signal su2_main_bytes : unsigned(1 downto 0);
    signal su8_sound_write_data : unsigned(7 downto 0);
    -- Independent inverse of the physical board map, not the DUT's dense
    -- address calculation. Main byte masks select the original big-endian lane.
    function F_MAIN_BASE(vu24_address : unsigned(23 downto 0)) return natural is
        variable vint_address : natural := to_integer(vu24_address);
    begin
        if (vint_address >= 16#40000# and vint_address <= 16#4FFFE#) then
            return vint_address - 16#40000#;
        elsif (vint_address >= 16#60000# and vint_address <= 16#60FFE#) then
            return 65536 + vint_address - 16#60000#;
        elsif (vint_address >= 16#80000# and vint_address <= 16#83FFE#) then
            return 69632 + vint_address - 16#80000#;
        elsif (vint_address >= 16#A0000# and vint_address <= 16#A07FE#) then
            return 86016 + vint_address - 16#A0000#;
        elsif (vint_address >= 16#FC000# and vint_address <= 16#FFFFE#) then
            return 88064 + vint_address - 16#FC000#;
        end if;
        assert (false) report "State RAM access escaped physical banks" severity failure;
        return 0;
    end function;
    signal s_clk : std_logic := '0';
    signal s_initialize, s_begin, s_request, s_write, s_commit : std_logic := '0';
    signal s_session, s_held : std_logic := '1';
    signal s_ready, s_response, s_error, s_committed, s_commit_error, s_idle : std_logic;
    signal su18_address : unsigned(17 downto 0) := (others => '0');
    signal su8_data : unsigned(7 downto 0) := (others => '0');
    signal su8_read_data : unsigned(7 downto 0);
    signal s_memory_request, s_memory_response : std_logic := '0';
    signal su8_memory_read_data : unsigned(7 downto 0);
    signal su5_m68k_address : unsigned(4 downto 0);
    signal su16_chip_address : unsigned(15 downto 0);
    signal su32_m68k_read_data, su32_m68k_write_data, su32_fm_data, su32_adpcm_data, su32_chip_data :
        unsigned(31 downto 0);
    signal su256_t80 : unsigned(255 downto 0) := F_WIDE(CINT_T80_BASE, CINT_T80_BYTES);
    signal su256_t80_load : unsigned(255 downto 0);
    signal su512_board : unsigned(511 downto 0) := F_WIDE(CINT_BOARD_BASE, CINT_BOARD_BYTES);
    signal su512_board_load : unsigned(511 downto 0);
    signal s_m68k_write, s_fm_write, s_adpcm_write, s_t80_load, s_board_load : std_logic;
    signal su32_m68k : t_words(0 to 23) := F_WORDS(CINT_M68K_BASE, 24);
    signal su32_fm : t_words(0 to 125) := F_WORDS(CINT_FM_BASE, 126);
    signal su32_adpcm : t_words(0 to 5) := F_WORDS(CINT_ADPCM_BASE, 6);
    signal sint_main_writes, sint_fm_writes, sint_adpcm_writes, sint_wide_loads : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_memory_request <= s_main_request or s_sound_request;
    s_main_response <= s_memory_response and not s_pending_sound;
    s_sound_response <= s_memory_response and s_pending_sound;
    -- Unknown donor placeholders and unused top FM bits must never leak into
    -- the byte image. Other bits have nontrivial independent address patterns.
    su32_m68k_read_data <= (others => 'X') when su5_m68k_address = 16 or su5_m68k_address = 17 or
        su5_m68k_address = 21 or su5_m68k_address = 23 else su32_m68k(to_integer(su5_m68k_address));
    su32_fm_data <= x"XXXX" & su32_fm(125)(15 downto 0) when su16_chip_address = 125 else
        su32_fm(to_integer(su16_chip_address)) when su16_chip_address < 126 else (others => 'X');
    su32_adpcm_data <= (2 downto 0 => 'X') & su32_adpcm(5)(28 downto 0) when su16_chip_address = 5 else
        su32_adpcm(to_integer(su16_chip_address)) when su16_chip_address < 6 else (others => 'X');
    dut : entity work.rabbitpunch_state_banks
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_session => s_session,
            i_machine_held => s_held,
            i_apply_begin => s_begin,
            i_byte_request => s_request,
            o_byte_ready => s_ready,
            i_byte_write => s_write,
            iu18_byte_address => su18_address,
            iu8_byte_data => su8_data,
            o_byte_response => s_response,
            o_byte_error => s_error,
            ou8_byte_data => su8_read_data,
            i_commit => s_commit,
            o_committed => s_committed,
            o_commit_error => s_commit_error,
            o_idle => s_idle,
            o_main_request => s_main_request,
            o_main_write => s_main_write,
            ou24_main_address => su24_main_address,
            ou16_main_data => su16_main_write_data,
            ou2_main_bytes => su2_main_bytes,
            i_main_response => s_main_response,
            iu16_main_data => su16_main_read_data,
            o_sound_request => s_sound_request,
            o_sound_write => s_sound_write,
            ou16_sound_address => su16_sound_address,
            ou8_sound_data => su8_sound_write_data,
            i_sound_response => s_sound_response,
            iu8_sound_data => su8_memory_read_data,
            ou5_m68k_address => su5_m68k_address,
            iu32_m68k_data => su32_m68k_read_data,
            o_m68k_write => s_m68k_write,
            ou32_m68k_data => su32_m68k_write_data,
            iu256_t80_data => su256_t80,
            ou256_t80_data => su256_t80_load,
            o_t80_load => s_t80_load,
            iu512_board_data => su512_board,
            ou512_board_data => su512_board_load,
            o_board_load => s_board_load,
            ou16_chip_address => su16_chip_address,
            iu32_fm_data => su32_fm_data,
            iu32_adpcm_data => su32_adpcm_data,
            ou32_chip_data => su32_chip_data,
            o_fm_write => s_fm_write,
            o_adpcm_write => s_adpcm_write
        );
    banks : process(s_clk)
        variable vu8_memory : t_bytes(0 to CINT_RAM_BYTES - 1) := F_BYTES;
        variable vint_debt, vint_address, vint_word_base : natural := 0;
        variable vu8_data : unsigned(7 downto 0);
        variable s_write_pending : std_logic;
    begin
        if (rising_edge(s_clk)) then
            s_memory_response <= '0';
            if (s_memory_request = '1') then
                assert (vint_debt = 0 and not (s_main_request = '1' and s_sound_request = '1')) severity failure;
                vint_debt := 5;
                if (s_sound_request = '1') then
                    assert (su16_sound_address >= x"F800") severity failure;
                    vint_address := 104448 + to_integer(su16_sound_address - x"F800");
                    vu8_data := su8_sound_write_data;
                    s_write_pending := s_sound_write;
                    s_pending_sound <= '1';
                else
                    vint_word_base := F_MAIN_BASE(su24_main_address);
                    vint_address := vint_word_base;
                    assert (su24_main_address(0) = '0' and (su2_main_bytes = "10" or su2_main_bytes = "01"))
                        report "State RAM byte lane invalid" severity failure;
                    if (su2_main_bytes = "10") then
                        vu8_data := su16_main_write_data(15 downto 8);
                    else
                        vint_address := vint_address + 1;
                        vu8_data := su16_main_write_data(7 downto 0);
                    end if;
                    s_write_pending := s_main_write;
                    s_pending_sound <= '0';
                end if;
                assert (vint_address = to_integer(su18_address))
                    report "Physical RAM address does not match requested body byte" severity failure;
            elsif (vint_debt > 0) then
                vint_debt := vint_debt - 1;
                if (vint_debt = 0) then
                    if (s_write_pending = '1') then
                        vu8_memory(vint_address) := vu8_data;
                    end if;
                    su8_memory_read_data <= vu8_memory(vint_address);
                    if (s_pending_sound = '0') then
                        su16_main_read_data <= vu8_memory(vint_word_base) & vu8_memory(vint_word_base + 1);
                    end if;
                    s_memory_response <= '1';
                end if;
            end if;
            if (s_m68k_write = '1') then
                assert (su5_m68k_address /= 16 and su5_m68k_address /= 17 and
                    su5_m68k_address /= 21 and su5_m68k_address /= 23) severity failure;
                assert (su32_m68k_write_data = F_WORD(CINT_M68K_BASE + 4*to_integer(su5_m68k_address), 1))
                    severity failure;
                su32_m68k(to_integer(su5_m68k_address)) <= su32_m68k_write_data;
                sint_main_writes <= sint_main_writes + 1;
            end if;
            if (s_fm_write = '1') then
                assert (su32_chip_data = F_WORD(CINT_FM_BASE + 4*to_integer(su16_chip_address), 1)) severity failure;
                su32_fm(to_integer(su16_chip_address)) <= su32_chip_data;
                sint_fm_writes <= sint_fm_writes + 1;
            end if;
            if (s_adpcm_write = '1') then
                assert (su32_chip_data = F_WORD(CINT_ADPCM_BASE + 4*to_integer(su16_chip_address), 1)) severity failure;
                su32_adpcm(to_integer(su16_chip_address)) <= su32_chip_data;
                sint_adpcm_writes <= sint_adpcm_writes + 1;
            end if;
            if (s_t80_load = '1' or s_board_load = '1') then
                assert (s_t80_load = '1' and s_board_load = '1') severity failure;
                for vint_byte in 0 to CINT_T80_BYTES - 1 loop
                    assert (su256_t80_load(8*vint_byte + 7 downto 8*vint_byte) =
                        F_BYTE(CINT_T80_BASE + vint_byte, 1)) severity failure;
                end loop;
                for vint_byte in 0 to CINT_BOARD_BYTES - 1 loop
                    assert (su512_board_load(8*vint_byte + 7 downto 8*vint_byte) =
                        F_BYTE(CINT_BOARD_BASE + vint_byte, 1)) severity failure;
                end loop;
                su256_t80 <= su256_t80_load;
                su512_board <= su512_board_load;
                sint_wide_loads <= sint_wide_loads + 1;
            end if;
        end if;
    end process;
    stimulus : process
        procedure cycles(vint_count : positive := 1) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until rising_edge(s_clk);
                wait for 1 ns;
            end loop;
        end procedure;
        procedure access_byte(vint_address, vint_epoch : natural; s_is_write, s_expected_error : std_logic) is
        begin
            su18_address <= to_unsigned(vint_address, 18);
            su8_data <= F_BYTE(vint_address, vint_epoch);
            s_write <= s_is_write;
            s_request <= '1';
            wait for 1 ns;
            while (s_ready /= '1') loop
                cycles;
            end loop;
            cycles;
            s_request <= '0';
            for vint_timeout in 0 to 31 loop
                exit when s_response = '1';
                cycles;
                assert (vint_timeout < 31) severity failure;
            end loop;
            assert (s_error = s_expected_error) report "Unexpected body byte error" severity failure;
            if (s_is_write = '0' and s_expected_error = '0') then
                assert (su8_read_data = F_BYTE(vint_address, vint_epoch))
                    report "Body byte mismatch at" & integer'image(vint_address) severity failure;
            end if;
            cycles;
        end procedure;
        procedure commit_body(s_expected_error : std_logic) is
        begin
            s_commit <= '1';
            cycles;
            s_commit <= '0';
            while (s_committed /= '1') loop
                cycles;
            end loop;
            assert (s_commit_error = s_expected_error) severity failure;
            cycles;
        end procedure;
    begin
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        -- Every bank byte, including hidden/padding bits, is observed.
        for vint_byte in 0 to CINT_BODY_BYTES - 1 loop
            access_byte(vint_byte, 0, '0', '0');
        end loop;
        access_byte(CINT_BODY_BYTES, 0, '0', '1');
        access_byte(0, 1, '1', '1');
        commit_body('1');
        s_begin <= '1';
        cycles;
        s_begin <= '0';
        access_byte(0, 0, '1', '0');
        access_byte(2, 0, '1', '1');
        commit_body('1');
        assert (sint_wide_loads = 0) severity failure;
        s_begin <= '1';
        cycles;
        s_begin <= '0';
        for vint_byte in 0 to CINT_BODY_BYTES - 1 loop
            access_byte(vint_byte, 1, '1', '0');
        end loop;
        assert (sint_wide_loads = 0) report "Wide registers loaded before final commit" severity failure;
        commit_body('0');
        assert (sint_main_writes = 20 and sint_fm_writes = 126 and
            sint_adpcm_writes = 6 and sint_wide_loads = 1) severity failure;
        for vint_byte in 0 to CINT_BODY_BYTES - 1 loop
            access_byte(vint_byte, 1, '0', '0');
        end loop;
        -- Losing the held session after RAM acceptance must retire its reply
        -- as an error, without issuing a second RAM request or committing.
        su18_address <= to_unsigned(5, 18);
        s_write <= '0';
        s_request <= '1';
        wait for 1 ns;
        while (s_ready /= '1') loop
            cycles;
        end loop;
        cycles;
        s_request <= '0';
        s_session <= '0';
        assert (s_idle = '0') severity failure;
        while (s_response /= '1') loop
            cycles;
        end loop;
        assert (s_error = '1' and s_idle = '1') severity failure;
        s_session <= '1';
        cycles;
        commit_body('1');
        su18_address <= to_unsigned(7, 18);
        s_request <= '1';
        wait for 1 ns;
        while (s_ready /= '1') loop
            cycles;
        end loop;
        cycles;
        s_request <= '0';
        s_initialize <= '1';
        cycles;
        s_initialize <= '0';
        assert (s_idle = '0') report "Reset discarded body RAM debt" severity failure;
        while (s_response /= '1') loop
            cycles;
        end loop;
        assert (s_error = '1' and s_idle = '1')
            report "Late reset reply entered a new body session" severity failure;
        report "STATE_BANKS_PASS all body bytes,two patterns,canonical padding,scan writes,wide commit,invalid order,debt" severity note;
        stop;
        wait;
    end process;
end architecture;
