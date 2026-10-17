library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity roms_tb is
end entity;

architecture test of roms_tb is
    component rabbitpunch_roms is
        port (
            i_clk : in std_logic;
            i_initialize : in std_logic;
            o_ready : out std_logic;
            o_idle : out std_logic;
            i_loading : in std_logic;
            i_loader_request : in std_logic;
            o_loader_ready : out std_logic;
            iu27_loader_byte_address : in unsigned(26 downto 0);
            iu16_loader_data : in unsigned(15 downto 0);
            iu2_loader_bytes : in unsigned(1 downto 0);
            o_loader_response_valid : out std_logic;
            i_sprite_request : in std_logic;
            iu17_sprite_word_address : in unsigned(16 downto 0);
            o_sprite_response_valid : out std_logic;
            ou32_sprite_response_data : out unsigned(31 downto 0);
            i_tile_request : in std_logic;
            iu17_tile_word_address : in unsigned(16 downto 0);
            i_tile_foreground : in std_logic;
            o_tile_response_valid : out std_logic;
            ou32_tile_response_data : out unsigned(31 downto 0);
            i_cpu_request : in std_logic;
            iu18_cpu_byte_address : in unsigned(17 downto 0);
            o_cpu_response_valid : out std_logic;
            ou16_cpu_response_data : out unsigned(15 downto 0);
            i_audio_request : in std_logic := '0';
            o_audio_ready : out std_logic;
            iu16_audio_byte_address : in unsigned(15 downto 0) := (others => '0');
            o_audio_response_valid : out std_logic;
            ou8_audio_response_data : out unsigned(7 downto 0);
            i_sample_request : in std_logic := '0';
            iu18_sample_byte_address : in unsigned(17 downto 0) := (others => '0');
            o_sample_valid : out std_logic;
            ou8_sample_data : out unsigned(7 downto 0);
            iou16_sdram_data : inout unsigned(15 downto 0);
            ou13_sdram_address : out unsigned(12 downto 0);
            ou2_sdram_bank : out unsigned(1 downto 0);
            ou2_sdram_byte_mask : out unsigned(1 downto 0);
            o_sdram_chip_select : out std_logic;
            o_sdram_write_n : out std_logic;
            o_sdram_row_n : out std_logic;
            o_sdram_column_n : out std_logic;
            o_sdram_clock_enable : out std_logic
        );
    end component;
    component sdram_chip_model_wide is
        port (
            clk : in std_logic;
            SDRAM_DQ : inout unsigned(15 downto 0);
            SDRAM_A : in unsigned(12 downto 0);
            SDRAM_BA : in unsigned(1 downto 0);
            SDRAM_nCS : in std_logic;
            SDRAM_nWE : in std_logic;
            SDRAM_nRAS : in std_logic;
            SDRAM_nCAS : in std_logic
        );
    end component;
    signal s_clk : std_logic := '0';
    signal s_loading : std_logic := '1';
    signal s_ready, s_idle, s_loader_ready, s_loader_valid : std_logic;
    signal s_loader_request : std_logic := '0';
    signal su27_loader_address : unsigned(26 downto 0) := (others => '0');
    signal su16_loader_data : unsigned(15 downto 0) := (others => '0');
    signal su2_loader_bytes : unsigned(1 downto 0) := "11";
    signal s_sprite_request, s_tile_request, s_cpu_request : std_logic := '0';
    signal su17_sprite_address, su17_tile_address : unsigned(16 downto 0) := (others => '0');
    signal su18_cpu_address : unsigned(17 downto 0) := (others => '0');
    signal s_foreground : std_logic := '0';
    signal s_audio_request, s_sample_request : std_logic := '0';
    signal s_audio_ready, s_audio_valid, s_sample_valid : std_logic;
    signal su16_audio_address : unsigned(15 downto 0) := (others => '0');
    signal su18_sample_address : unsigned(17 downto 0) := (others => '0');
    signal su8_audio_data, su8_sample_data : unsigned(7 downto 0);
    signal s_sprite_valid, s_tile_valid, s_cpu_valid : std_logic;
    signal su32_sprite_data, su32_tile_data : unsigned(31 downto 0);
    signal su16_cpu_data, su16_dq : unsigned(15 downto 0);
    signal su13_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_reads : natural := 0;
    function byte_value(vint_address, vint_epoch : natural) return unsigned is
    begin
        if (vint_address = 0) then
            return x"7E";
        end if;
        return to_unsigned((vint_address + (vint_address / 65536) * 17 + vint_epoch * 64) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 10417 ps;
    dut : rabbitpunch_roms
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            o_ready => s_ready,
            o_idle => s_idle,
            i_loading => s_loading,
            i_loader_request => s_loader_request,
            o_loader_ready => s_loader_ready,
            iu27_loader_byte_address => su27_loader_address,
            iu16_loader_data => su16_loader_data,
            iu2_loader_bytes => su2_loader_bytes,
            o_loader_response_valid => s_loader_valid,
            i_sprite_request => s_sprite_request,
            iu17_sprite_word_address => su17_sprite_address,
            o_sprite_response_valid => s_sprite_valid,
            ou32_sprite_response_data => su32_sprite_data,
            i_tile_request => s_tile_request,
            iu17_tile_word_address => su17_tile_address,
            i_tile_foreground => s_foreground,
            o_tile_response_valid => s_tile_valid,
            ou32_tile_response_data => su32_tile_data,
            i_cpu_request => s_cpu_request,
            iu18_cpu_byte_address => su18_cpu_address,
            o_cpu_response_valid => s_cpu_valid,
            ou16_cpu_response_data => su16_cpu_data,
            i_audio_request => s_audio_request,
            o_audio_ready => s_audio_ready,
            iu16_audio_byte_address => su16_audio_address,
            o_audio_response_valid => s_audio_valid,
            ou8_audio_response_data => su8_audio_data,
            i_sample_request => s_sample_request,
            iu18_sample_byte_address => su18_sample_address,
            o_sample_valid => s_sample_valid,
            ou8_sample_data => su8_sample_data,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_address,
            ou2_sdram_bank => su2_bank,
            ou2_sdram_byte_mask => su2_mask,
            o_sdram_chip_select => s_chip,
            o_sdram_write_n => s_write_n,
            o_sdram_row_n => s_row_n,
            o_sdram_column_n => s_column_n,
            o_sdram_clock_enable => s_cke
        );
    chip : sdram_chip_model_wide
        port map (
            clk => s_clk,
            SDRAM_DQ => su16_dq,
            SDRAM_A => su13_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_chip,
            SDRAM_nWE => s_write_n,
            SDRAM_nRAS => s_row_n,
            SDRAM_nCAS => s_column_n
        );
    process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (s_row_n = '1' and s_column_n = '0' and s_write_n = '1') then
                sint_reads <= sint_reads + 1;
            end if;
        end if;
    end process;
    process
        type t_bases is array (0 to 6) of natural;
        constant BASES : t_bases := (0, 16#50000#, 16#D0000#, 16#150000#, 16#40000#, 16#1D0000#, 16#1F0000#);
        variable vu5_seen : unsigned(4 downto 0);
        variable vu32_expected : unsigned(31 downto 0);
        variable vu16_expected : unsigned(15 downto 0);
        variable vint_address, vint_before, vint_checks, vint_writes : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
        procedure write_word(vint_address : natural; vu16_word : unsigned(15 downto 0); vu2_bytes : unsigned(1 downto 0)) is
            variable v_done : boolean := false;
        begin
            assert (s_loader_ready = '1') report "Loader not ready" severity failure;
            su27_loader_address <= to_unsigned(vint_address, 27);
            su16_loader_data <= vu16_word;
            su2_loader_bytes <= vu2_bytes;
            s_loader_request <= '1';
            tick;
            s_loader_request <= '0';
            su27_loader_address <= (others => '1');
            su16_loader_data <= not vu16_word;
            for vint_wait in 0 to 200 loop
                tick;
                assert (s_cpu_valid = '0' and s_tile_valid = '0' and s_sprite_valid = '0' and s_audio_valid = '0' and s_sample_valid = '0') report "Loader acknowledgment leaked to a ROM client" severity failure;
                if (s_loader_valid = '1') then
                    v_done := true;
                    exit;
                end if;
            end loop;
            assert (v_done) report "Word loader stalled" severity failure;
            vint_writes := vint_writes + 1;
            tick;
        end procedure;
        procedure read_set(vint_cpu_word, vint_graphics_word, vint_bank, vint_epoch : natural) is
        begin
            assert (s_ready = '1' and s_idle = '1') report "ROM subsystem not ready" severity failure;
            su18_cpu_address <= to_unsigned(vint_cpu_word * 2, 18);
            su17_sprite_address <= to_unsigned(vint_graphics_word, 17);
            su17_tile_address <= to_unsigned(vint_graphics_word, 17);
            s_foreground <= '0';
            if (vint_bank = 1) then
                s_foreground <= '1';
            end if;
            assert (s_audio_ready = '1') report "Audio requester not ready" severity failure;
            su16_audio_address <= to_unsigned(vint_cpu_word * 2, 16);
            su18_sample_address <= to_unsigned(vint_bank * 16#20000# + vint_cpu_word * 2, 18);
            s_audio_request <= '1';
            s_sample_request <= '1';
            s_sprite_request <= '1';
            s_tile_request <= '1';
            s_cpu_request <= '1';
            wait for 1 ns;
            assert (s_idle = '0') report "Offered ROM requests must prevent loader ownership" severity failure;
            tick;
            s_audio_request <= '0';
            s_sprite_request <= '0';
            s_tile_request <= '0';
            s_cpu_request <= '0';
            vu5_seen := "00000";
            for vint_wait in 0 to 200 loop
                tick;
                if (s_sprite_valid = '1') then
                    for vint_byte in 0 to 3 loop
                        vu32_expected(vint_byte * 8 + 7 downto vint_byte * 8) := byte_value(16#150000# + vint_graphics_word * 4 + vint_byte, vint_epoch);
                    end loop;
                    assert (su32_sprite_data = vu32_expected and vu5_seen(0) = '0') report "Loaded sprite data/cache mismatch" severity failure;
                    vu5_seen(0) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                if (s_tile_valid = '1') then
                    for vint_byte in 0 to 3 loop
                        vu32_expected(vint_byte * 8 + 7 downto vint_byte * 8) := byte_value(16#50000# + vint_bank * 16#80000# + vint_graphics_word * 4 + vint_byte, vint_epoch);
                    end loop;
                    assert (su32_tile_data = vu32_expected and vu5_seen(1) = '0') report "Loaded tile bank/cache mismatch" severity failure;
                    vu5_seen(1) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                if (s_cpu_valid = '1') then
                    vu16_expected := byte_value(vint_cpu_word * 2, vint_epoch) & byte_value(vint_cpu_word * 2 + 1, vint_epoch);
                    assert (su16_cpu_data = vu16_expected and vu5_seen(2) = '0') report "Loaded 68000 byte order/cache mismatch" severity failure;
                    vu5_seen(2) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                if (s_audio_valid = '1') then
                    assert (su8_audio_data = byte_value(16#40000# + vint_cpu_word * 2, vint_epoch) and vu5_seen(3) = '0')
                        report "Audio program byte/cache mismatch" severity failure;
                    vu5_seen(3) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                if (s_sample_valid = '1' and vu5_seen(4) = '0') then
                    assert (su8_sample_data = byte_value(16#1D0000# + vint_bank * 16#20000# + vint_cpu_word * 2, vint_epoch))
                        report "Sample bank byte/cache mismatch" severity failure;
                    vu5_seen(4) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                exit when vu5_seen = "11111";
            end loop;
            assert (vu5_seen = "11111") report "ROM subsystem reply lost" severity failure;
            s_sample_request <= '0';
            tick;
        end procedure;
    begin
        while (s_loader_ready /= '1') loop
            tick;
        end loop;
        for vint_epoch in 0 to 1 loop
            if (vint_epoch = 1) then
                assert (s_idle = '1') report "Subsystem did not drain before replacement image" severity failure;
                s_loading <= '1';
                tick;
            end if;
            for vint_region in BASES'range loop
                for vint_word in 0 to 3 loop
                    vint_address := BASES(vint_region) + vint_word * 2;
                    -- The even byte at zero is replaced below using a single lane.
                    vu16_expected := byte_value(vint_address + 1, vint_epoch) & byte_value(vint_address, vint_epoch);
                    if (vint_address = 0) then
                        vu16_expected(7 downto 0) := x"00";
                    end if;
                    write_word(vint_address, vu16_expected, "11");
                end loop;
            end loop;
            write_word(0, x"007E", "01");
            assert (s_idle = '1') report "Loader response did not drain ownership" severity failure;
            s_loading <= '0';
            tick;
            vint_before := sint_reads;
            read_set(0, 0, 0, vint_epoch);
            assert (sint_reads = vint_before + 5) report "New image did not invalidate graphics, main and audio caches" severity failure;
            vint_before := sint_reads;
            for vint_word in 0 to 3 loop
                read_set(vint_word, vint_word mod 2, 0, vint_epoch);
            end loop;
            assert (sint_reads = vint_before) report "Adjacent CPU/graphics words refetched a cached burst" severity failure;
            read_set(0, 0, 1, vint_epoch);
            read_set(0, 0, 0, vint_epoch);
        end loop;
        report "ROMS_PASS checked_replies=" & integer'image(vint_checks) & " loader_words=" & integer'image(vint_writes) & " read_bursts=" & integer'image(sint_reads);
        finish;
        wait;
    end process;
    process
    begin
        wait for 2 ms;
        assert false report "ROM subsystem test timeout" severity failure;
    end process;
end architecture;
