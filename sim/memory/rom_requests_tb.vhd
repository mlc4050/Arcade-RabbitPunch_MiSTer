library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.rabbitpunch_sdram_types.all;

entity rom_requests_tb is
    generic (USE_PIN_BACKEND : boolean := false);
end entity;

architecture test of rom_requests_tb is
    signal s_clk : std_logic := '0';
    signal s_sprite_request, s_tile_request, s_cpu_request : std_logic := '0';
    signal su17_sprite_address, su17_tile_address : unsigned(16 downto 0) := (others => '0');
    signal su18_cpu_address : unsigned(17 downto 0) := (others => '0');
    signal s_foreground : std_logic := '0';
    signal s_sprite_valid, s_tile_valid, s_cpu_valid, s_idle : std_logic;
    signal su32_sprite_data, su32_tile_data : unsigned(31 downto 0);
    signal su16_cpu_data : unsigned(15 downto 0);
    signal su3_requests, su3_ready : unsigned(2 downto 0);
    signal su3_valid : unsigned(2 downto 0) := "000";
    signal su27_addresses : t_sdram_addresses;
    signal su64_data : t_sdram_read_data := (others => (others => '0'));
    type t_test_addresses is array (natural range <>) of natural;
    constant GRAPHICS_ADDRESSES : t_test_addresses := (0, 1, 2, 3, 127, 128, 511, 512, 65535, 65536, 131070, 131071);
    constant CPU_ADDRESSES : t_test_addresses := (0, 2, 4, 6, 16#100#, 16#7FFE#, 16#10000#, 16#3FFF8#, 16#3FFFA#, 16#3FFFC#, 16#3FFFE#, 16#20000#);
    signal s_loaded : std_logic;
    type t_counts is array (0 to 2) of natural;
    signal sint_cycle : natural := 0;
    function byte_value(vint_address : natural) return unsigned is
    begin
        -- Full address bits participate, including the region/bank bits.
        return to_unsigned((vint_address + (vint_address / 256) * 17 + (vint_address / 65536) * 29) mod 256, 8);
    end function;
begin
    s_clk <= not s_clk after 10 ns;
    dut : entity work.rabbitpunch_rom_requests
        port map (
            i_clk => s_clk,
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
            o_idle => s_idle,
            ou3_backend_requests => su3_requests,
            iu3_backend_ready => su3_ready,
            ou27_backend_byte_addresses => su27_addresses,
            iu3_backend_response_valid => su3_valid,
            iu64_backend_read_data => su64_data
        );

    synthetic_backend : if (not USE_PIN_BACKEND) generate
        s_loaded <= '1';
    process(s_clk)
        variable vint_wait : t_counts := (others => 0);
        variable vint_addresses : t_counts := (others => 0);
        variable vu3_active : unsigned(2 downto 0) := "000";
    begin
        if (rising_edge(s_clk)) then
            sint_cycle <= sint_cycle + 1;
            su3_valid <= "000";
            for vint_client in 0 to 2 loop
                if (vu3_active(vint_client) = '1') then
                    if (vint_wait(vint_client) = 0) then
                        for vint_byte in 0 to 7 loop
                            su64_data(vint_client)(vint_byte * 8 + 7 downto vint_byte * 8) <= byte_value(vint_addresses(vint_client) + vint_byte);
                        end loop;
                        su3_valid(vint_client) <= '1';
                        vu3_active(vint_client) := '0';
                    else
                        vint_wait(vint_client) := vint_wait(vint_client) - 1;
                    end if;
                elsif (su3_requests(vint_client) = '1' and su3_ready(vint_client) = '1') then
                    assert (su27_addresses(vint_client)(2 downto 0) = "000") report "Unaligned backend burst" severity failure;
                    vint_addresses(vint_client) := to_integer(su27_addresses(vint_client));
                    assert (vint_addresses(vint_client) <= 16#20FFF8#) report "Backend address outside selected ROM image" severity failure;
                    vint_wait(vint_client) := (sint_cycle + vint_client * 11) mod 23;
                    vu3_active(vint_client) := '1';
                end if;
            end loop;
        end if;
    end process;
    -- Backpressure the initial request as well as arbitrary later ones.
    su3_ready(0) <= '1' when sint_cycle > 40 and sint_cycle mod 7 < 3 else '0';
    su3_ready(1) <= '1' when sint_cycle > 60 and sint_cycle mod 11 < 4 else '0';
    su3_ready(2) <= '1' when sint_cycle > 20 and sint_cycle mod 5 < 2 else '0';
    end generate;

    pin_backend : if (USE_PIN_BACKEND) generate
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
        signal su3_memory_requests, su3_memory_ready, su3_memory_writes, su3_memory_valid : unsigned(2 downto 0);
        signal su27_memory_addresses : t_sdram_addresses;
        signal su16_memory_data : t_sdram_write_data := (others => (others => '0'));
        signal su3_loader_requests : unsigned(2 downto 0) := "000";
        signal su27_loader_addresses : t_sdram_addresses := (others => (others => '0'));
        signal su16_dq : unsigned(15 downto 0);
        signal su13_address : unsigned(12 downto 0);
        signal su2_bank, su2_mask : unsigned(1 downto 0);
        signal s_chip, s_write_n, s_row_n, s_column_n, s_cke, s_initialized : std_logic;
    begin
        su3_valid <= su3_memory_valid when s_loaded = '1' else "000";
        su3_ready <= su3_memory_ready when s_loaded = '1' else "000";
        su3_memory_requests <= su3_requests when s_loaded = '1' else su3_loader_requests;
        su27_memory_addresses <= su27_addresses when s_loaded = '1' else su27_loader_addresses;
        su3_memory_writes <= "000" when s_loaded = '1' else "100";
        memory_transport : entity work.rabbitpunch_sdram
            port map (
                i_clk => s_clk,
                i_initialize => '0',
                o_initialized => s_initialized,
                iu3_requests => su3_memory_requests,
                ou3_ready => su3_memory_ready,
                iu3_writes => su3_memory_writes,
                iu27_byte_addresses => su27_memory_addresses,
                iu16_write_data => su16_memory_data,
                iu2_byte_enables => (others => "11"),
                ou3_response_valid => su3_memory_valid,
                ou64_read_data => su64_data,
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
        process
            variable vint_base, vint_address : natural;
        begin
            s_loaded <= '0';
            wait until s_initialized = '1';
            report "PIN_ROM initialized";
            for vint_region in 0 to 3 loop
                report "PIN_ROM loading region " & integer'image(vint_region);
                for vint_index in GRAPHICS_ADDRESSES'range loop
                    case vint_region is
                        when 0 =>
                            vint_base := CPU_ADDRESSES(vint_index);
                        when 1 =>
                            vint_base := 16#50000# + GRAPHICS_ADDRESSES(vint_index) * 4;
                        when 2 =>
                            vint_base := 16#D0000# + GRAPHICS_ADDRESSES(vint_index) * 4;
                        when 3 =>
                            vint_base := 16#150000# + GRAPHICS_ADDRESSES(vint_index) * 4;
                        when others =>
                            null;
                    end case;
                    vint_base := (vint_base / 8) * 8;
                    for vint_word in 0 to 3 loop
                        vint_address := vint_base + vint_word * 2;
                        wait until falling_edge(s_clk);
                        assert (su3_memory_ready(2) = '1') report "Preload backend busy" severity failure;
                        su27_loader_addresses(2) <= to_unsigned(vint_address, 27);
                        su16_memory_data(2) <= byte_value(vint_address + 1) & byte_value(vint_address);
                        su3_loader_requests <= "100";
                        wait until falling_edge(s_clk);
                        su3_loader_requests <= "000";
                        wait until su3_memory_valid(2) = '1';
                        wait until su3_memory_valid(2) = '0';
                    end loop;
                end loop;
            end loop;
            wait until falling_edge(s_clk);
            report "PIN_ROM preload complete";
            s_loaded <= '1';
            wait;
        end process;
    end generate;

    process
        variable vu3_seen : unsigned(2 downto 0);
        variable vu32_expected : unsigned(31 downto 0);
        variable vu16_expected : unsigned(15 downto 0);
        variable vint_sprite, vint_tile, vint_cpu, vint_tile_base, vint_checks : natural := 0;
        procedure tick is
        begin
            wait until rising_edge(s_clk);
            wait for 1 ns;
        end procedure;
    begin
        wait until s_loaded = '1';
        tick;
        for vint_round in 0 to 95 loop
            vint_sprite := GRAPHICS_ADDRESSES(vint_round mod GRAPHICS_ADDRESSES'length);
            vint_tile := GRAPHICS_ADDRESSES((vint_round * 7) mod GRAPHICS_ADDRESSES'length);
            vint_cpu := CPU_ADDRESSES(vint_round mod CPU_ADDRESSES'length);
            vint_tile_base := 16#50000#;
            s_foreground <= '0';
            if (vint_round mod 2 = 1) then
                vint_tile_base := 16#D0000#;
                s_foreground <= '1';
            end if;
            su17_sprite_address <= to_unsigned(vint_sprite, 17);
            su17_tile_address <= to_unsigned(vint_tile, 17);
            su18_cpu_address <= to_unsigned(vint_cpu, 18);
            s_sprite_request <= '1';
            s_tile_request <= '1';
            s_cpu_request <= '1';
            tick;
            s_sprite_request <= '0';
            s_tile_request <= '0';
            s_cpu_request <= '0';
            su17_sprite_address <= not to_unsigned(vint_sprite, 17);
            su17_tile_address <= not to_unsigned(vint_tile, 17);
            su18_cpu_address <= not to_unsigned(vint_cpu, 18);
            s_foreground <= not s_foreground;
            vu3_seen := "000";
            for vint_wait in 0 to 150 loop
                tick;
                if (s_sprite_valid = '1') then
                    for vint_byte in 0 to 3 loop
                        vu32_expected(vint_byte * 8 + 7 downto vint_byte * 8) := byte_value(16#150000# + vint_sprite * 4 + vint_byte);
                    end loop;
                    assert (su32_sprite_data = vu32_expected and vu3_seen(0) = '0') report "Sprite ROM mapping/lane mismatch" severity failure;
                    vu3_seen(0) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                if (s_tile_valid = '1') then
                    for vint_byte in 0 to 3 loop
                        vu32_expected(vint_byte * 8 + 7 downto vint_byte * 8) := byte_value(vint_tile_base + vint_tile * 4 + vint_byte);
                    end loop;
                    assert (su32_tile_data = vu32_expected and vu3_seen(1) = '0') report "Tile ROM bank/lane mismatch" severity failure;
                    vu3_seen(1) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                if (s_cpu_valid = '1') then
                    vu16_expected := byte_value(vint_cpu) & byte_value(vint_cpu + 1);
                    assert (su16_cpu_data = vu16_expected and vu3_seen(2) = '0') report "68000 ROM byte order mismatch" severity failure;
                    vu3_seen(2) := '1';
                    vint_checks := vint_checks + 1;
                end if;
                exit when vu3_seen = "111";
            end loop;
            assert (vu3_seen = "111" and s_idle = '1') report "Lost queued ROM request" severity failure;
            tick;
        end loop;
        for vint_wait in 0 to 100 loop
            tick;
            assert (s_sprite_valid = '0' and s_tile_valid = '0' and s_cpu_valid = '0') report "Duplicate ROM response" severity failure;
        end loop;
        report "ROM_REQUESTS_PASS checked_replies=" & integer'image(vint_checks);
        finish;
        wait;
    end process;
    process
    begin
        wait for 1 ms;
        assert false report "ROM request test timeout" severity failure;
    end process;
end architecture;

