library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity download_sdram_tb is
end entity;

architecture test of download_sdram_tb is
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
    signal s_download, s_word_valid, s_cpu_request : std_logic := '0';
    signal s_word_ready, s_loading, s_loader_request, s_loader_ready, s_loader_valid : std_logic;
    signal s_reset, s_image_valid, s_error, s_done, s_rom_ready, s_rom_idle, s_cpu_valid : std_logic;
    signal su27_address, su27_loader_address, su27_loaded : unsigned(26 downto 0) := (others => '0');
    signal su16_data, su16_loader_data, su16_cpu_data : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes : unsigned(1 downto 0);
    signal su18_cpu_address : unsigned(17 downto 0) := (others => '0');
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
begin
    s_clk <= not s_clk after 10417 ps;
    download : entity work.rabbitpunch_download
        generic map (GINT_IMAGE_BYTES => 16)
        port map (
            i_clk => s_clk,
            i_download => s_download,
            i_word_valid => s_word_valid,
            o_word_ready => s_word_ready,
            iu27_word_byte_address => su27_address,
            iu16_word_data => su16_data,
            i_transport_idle => s_rom_idle,
            i_loader_ready => s_loader_ready,
            i_loader_response_valid => s_loader_valid,
            o_loading => s_loading,
            o_loader_request => s_loader_request,
            ou27_loader_byte_address => su27_loader_address,
            ou16_loader_data => su16_loader_data,
            ou2_loader_bytes => su2_bytes,
            o_game_reset => s_reset,
            o_image_valid => s_image_valid,
            o_error => s_error,
            o_done => s_done,
            ou27_bytes_loaded => su27_loaded
        );
    roms : entity work.rabbitpunch_roms
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            o_ready => s_rom_ready,
            o_idle => s_rom_idle,
            i_loading => s_loading,
            i_loader_request => s_loader_request,
            o_loader_ready => s_loader_ready,
            iu27_loader_byte_address => su27_loader_address,
            iu16_loader_data => su16_loader_data,
            iu2_loader_bytes => su2_bytes,
            o_loader_response_valid => s_loader_valid,
            i_sprite_request => '0',
            iu17_sprite_word_address => (others => '0'),
            o_sprite_response_valid => open,
            ou32_sprite_response_data => open,
            i_tile_request => '0',
            iu17_tile_word_address => (others => '0'),
            i_tile_foreground => '0',
            o_tile_response_valid => open,
            ou32_tile_response_data => open,
            i_cpu_request => s_cpu_request,
            iu18_cpu_byte_address => su18_cpu_address,
            o_cpu_response_valid => s_cpu_valid,
            ou16_cpu_response_data => su16_cpu_data,
            i_audio_request => '0',
            o_audio_ready => open,
            iu16_audio_byte_address => (others => '0'),
            o_audio_response_valid => open,
            ou8_audio_response_data => open,
            i_sample_request => '0',
            iu18_sample_byte_address => (others => '0'),
            o_sample_valid => open,
            ou8_sample_data => open,
            iou16_sdram_data => su16_dq,
            ou13_sdram_address => su13_sdram_address,
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
            SDRAM_A => su13_sdram_address,
            SDRAM_BA => su2_bank,
            SDRAM_nCS => s_chip,
            SDRAM_nWE => s_write_n,
            SDRAM_nRAS => s_row_n,
            SDRAM_nCAS => s_column_n
        );

    stimulus : process
        variable vu16_expected : unsigned(15 downto 0);
        variable vint_reads : natural := 0;
    begin
        wait until falling_edge(s_clk);
        for vint_image in 0 to 1 loop
            s_download <= '1';
            wait for 1 ns;
            assert (s_reset = '1') report "Game did not stop at download start" severity failure;
            for vint_word in 0 to 7 loop
                if (s_word_ready /= '1') then
                    wait until s_word_ready = '1' for 200 us;
                end if;
                assert (s_word_ready = '1') report "Physical loader never became ready" severity failure;
                wait until falling_edge(s_clk);
                su27_address <= to_unsigned(vint_word * 2, 27);
                su16_data <= to_unsigned(16#3000# + vint_image * 256 + vint_word, 16);
                s_word_valid <= '1';
                wait until falling_edge(s_clk);
                s_word_valid <= '0';
                su27_address <= (others => '1');
                su16_data <= (others => '1');
            end loop;
            s_download <= '0';
            assert (s_reset = '1' and s_image_valid = '0')
                report "Game released before accepted final word drained" severity failure;
            wait until s_image_valid = '1' for 10 us;
            wait until falling_edge(s_clk);
            assert (s_image_valid = '1' and s_reset = '0' and s_loading = '0' and
                s_error = '0' and su27_loaded = 16 and s_rom_ready = '1')
                report "Physical image did not complete" severity failure;
            -- Warm every CPU cache lane, then replace the image and read again.
            for vint_word in 0 to 7 loop
                su18_cpu_address <= to_unsigned(vint_word * 2, 18);
                s_cpu_request <= '1';
                wait until falling_edge(s_clk);
                s_cpu_request <= '0';
                wait until s_cpu_valid = '1' for 3 us;
                vu16_expected := to_unsigned(16#3000# + vint_image * 256 + vint_word, 16);
                assert (s_cpu_valid = '1' and su16_cpu_data =
                    (vu16_expected(7 downto 0) & vu16_expected(15 downto 8)))
                    report "Downloaded CPU ROM byte order or image replacement failed" severity failure;
                vint_reads := vint_reads + 1;
                wait until falling_edge(s_clk);
            end loop;
            if (s_rom_idle /= '1') then
                wait until s_rom_idle = '1' for 3 us;
            end if;
            wait until falling_edge(s_clk);
        end loop;
        assert (vint_reads = 16) report "Missing downloaded read checks" severity failure;
        report "DOWNLOAD_SDRAM_PASS writes=16 reads=16 images=2";
        finish;
        wait;
    end process;
    process
    begin
        wait for 300 us;
        assert false report "Physical download integration timeout" severity failure;
    end process;
end architecture;
