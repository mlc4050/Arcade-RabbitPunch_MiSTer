library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_sdram_types.all;

-- Cached ROM requesters and word loader share one physical SDRAM module.
-- Hold gameplay reset externally while loading. Change loading mode only when
-- o_idle is high; keep it asserted until the final loader reply is consumed.
-- Word data uses raw stream byte lanes: low byte is the even byte address.
entity rabbitpunch_roms is
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
end entity;

architecture rtl of rabbitpunch_roms is
    signal s_initialized, s_front_idle, s_cache_idle, s_idle : std_logic;
    signal s_previous_loading, s_loader_pending : std_logic := '0';
    signal s_invalidate : std_logic;
    signal su3_front_requests, su3_front_ready, su3_front_valid : unsigned(2 downto 0);
    signal su27_front_addresses : t_sdram_addresses;
    signal su64_front_data : t_sdram_read_data;
    signal su3_cache_requests, su3_cache_ready, su3_cache_valid : unsigned(2 downto 0);
    signal su27_cache_addresses : t_sdram_addresses;
    signal su64_cache_data : t_sdram_read_data;
    signal su3_memory_requests, su3_memory_ready, su3_memory_valid, su3_memory_writes : unsigned(2 downto 0);
    signal su27_memory_addresses : t_sdram_addresses;
    signal su16_memory_data : t_sdram_write_data;
    signal su2_memory_bytes : t_sdram_byte_enables;
    signal su64_memory_data : t_sdram_read_data;
begin
    s_idle <= '1' when s_front_idle = '1' and s_cache_idle = '1' and
        s_loader_pending = '0' and su3_memory_ready = "111" else '0';
    o_idle <= s_idle;
    o_ready <= s_initialized and not i_loading;
    o_loader_ready <= s_initialized and i_loading and su3_memory_ready(2) and not s_loader_pending;
    s_invalidate <= i_loading and not s_previous_loading;
    su3_cache_ready <= su3_memory_ready when i_loading = '0' else "000";
    su3_cache_valid <= su3_memory_valid when s_loader_pending = '0' else su3_memory_valid and "011";
    su64_cache_data <= su64_memory_data;
    su3_memory_requests <= su3_cache_requests when i_loading = '0' else
        (2 => i_loader_request, others => '0');
    su27_memory_addresses(0) <= su27_cache_addresses(0);
    su27_memory_addresses(1) <= su27_cache_addresses(1);
    su27_memory_addresses(2) <= iu27_loader_byte_address when i_loading = '1' else su27_cache_addresses(2);
    su3_memory_writes <= "100" when i_loading = '1' else "000";
    su16_memory_data <= (2 => iu16_loader_data, others => (others => '0'));
    su2_memory_bytes <= (2 => iu2_loader_bytes, others => "00");

    requests : entity work.rabbitpunch_rom_requests
        port map (
            i_clk => i_clk,
            i_sprite_request => i_sprite_request,
            iu17_sprite_word_address => iu17_sprite_word_address,
            o_sprite_response_valid => o_sprite_response_valid,
            ou32_sprite_response_data => ou32_sprite_response_data,
            i_tile_request => i_tile_request,
            iu17_tile_word_address => iu17_tile_word_address,
            i_tile_foreground => i_tile_foreground,
            o_tile_response_valid => o_tile_response_valid,
            ou32_tile_response_data => ou32_tile_response_data,
            i_cpu_request => i_cpu_request,
            iu18_cpu_byte_address => iu18_cpu_byte_address,
            o_cpu_response_valid => o_cpu_response_valid,
            ou16_cpu_response_data => ou16_cpu_response_data,
            o_idle => s_front_idle,
            ou3_backend_requests => su3_front_requests,
            iu3_backend_ready => su3_front_ready,
            ou27_backend_byte_addresses => su27_front_addresses,
            iu3_backend_response_valid => su3_front_valid,
            iu64_backend_read_data => su64_front_data
        );
    cache : entity work.rabbitpunch_rom_cache
        port map (
            i_clk => i_clk,
            i_invalidate => s_invalidate,
            o_idle => s_cache_idle,
            iu3_requests => su3_front_requests,
            ou3_ready => su3_front_ready,
            iu27_byte_addresses => su27_front_addresses,
            ou3_response_valid => su3_front_valid,
            ou64_read_data => su64_front_data,
            ou3_backend_requests => su3_cache_requests,
            iu3_backend_ready => su3_cache_ready,
            ou27_backend_byte_addresses => su27_cache_addresses,
            iu3_backend_response_valid => su3_cache_valid,
            iu64_backend_read_data => su64_cache_data
        );
    memory_transport : entity work.rabbitpunch_sdram
        port map (
            i_clk => i_clk,
            i_initialize => i_initialize,
            o_initialized => s_initialized,
            iu3_requests => su3_memory_requests,
            ou3_ready => su3_memory_ready,
            iu3_writes => su3_memory_writes,
            iu27_byte_addresses => su27_memory_addresses,
            iu16_write_data => su16_memory_data,
            iu2_byte_enables => su2_memory_bytes,
            ou3_response_valid => su3_memory_valid,
            ou64_read_data => su64_memory_data,
            iou16_sdram_data => iou16_sdram_data,
            ou13_sdram_address => ou13_sdram_address,
            ou2_sdram_bank => ou2_sdram_bank,
            ou2_sdram_byte_mask => ou2_sdram_byte_mask,
            o_sdram_chip_select => o_sdram_chip_select,
            o_sdram_write_n => o_sdram_write_n,
            o_sdram_row_n => o_sdram_row_n,
            o_sdram_column_n => o_sdram_column_n,
            o_sdram_clock_enable => o_sdram_clock_enable
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_loader_response_valid <= '0';
            if (i_loading /= s_previous_loading) then
                assert ((s_front_idle = '1' and s_cache_idle = '1' and s_loader_pending = '0') and
                    (su3_memory_ready = "111" or s_initialized = '0'))
                    report "ROM loading mode changed before transport drained" severity failure;
            end if;
            s_previous_loading <= i_loading;
            if (s_loader_pending = '1' and su3_memory_valid(2) = '1') then
                o_loader_response_valid <= '1';
                s_loader_pending <= '0';
            end if;
            if (i_loader_request = '1') then
                assert (o_loader_ready = '1') report "Loader requested while not ready" severity failure;
                assert (to_integer(iu27_loader_byte_address) < ROM_IMAGE_SIZE and iu2_loader_bytes /= "00")
                    report "Loader request outside selected image or empty byte mask" severity failure;
                s_loader_pending <= '1';
            end if;
            if (i_sprite_request = '1' or i_tile_request = '1' or i_cpu_request = '1') then
                assert (o_ready = '1') report "ROM request during initialization/download" severity failure;
            end if;
        end if;
    end process;
end architecture;
