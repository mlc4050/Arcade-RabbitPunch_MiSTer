library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- ROM transport and the five main-CPU RAM banks. Register targets belong to board I/O.
-- No CPU reset input: accepted accesses complete and RAM survives CPU reset.
entity rabbitpunch_memory is
    port (
        i_clk : in std_logic;
        i_request : in std_logic;
        i_request_write : in std_logic;
        iu24_request_address : in unsigned(23 downto 0);
        iu16_request_data : in unsigned(15 downto 0);
        iu2_request_bytes : in unsigned(1 downto 0);
        o_request_supported : out std_logic;
        o_response_valid : out std_logic;
        ou16_response_data : out unsigned(15 downto 0);
        o_rom_request : out std_logic;
        ou18_rom_byte_address : out unsigned(17 downto 0);
        i_rom_response_valid : in std_logic;
        iu16_rom_response_data : in unsigned(15 downto 0);
        i_view_enable : in std_logic;
        iu5_view_target : in target_t;
        iu15_view_word_address : in unsigned(14 downto 0);
        o_view_valid : out std_logic;
        ou16_view_data : out unsigned(15 downto 0)
    );
end entity;

-- Compatibility adapter for CPU-only diagnostics. The integrated board uses
-- rabbitpunch_board_memory directly, including its independent video ports.
architecture rtl of rabbitpunch_memory is
begin
    memory : entity work.rabbitpunch_board_memory
        port map (
            i_clk => i_clk,
            i_request => i_request,
            i_request_write => i_request_write,
            iu24_request_address => iu24_request_address,
            iu16_request_data => iu16_request_data,
            iu2_request_bytes => iu2_request_bytes,
            o_request_supported => o_request_supported,
            o_response_valid => o_response_valid,
            ou16_response_data => ou16_response_data,
            o_rom_request => o_rom_request,
            ou18_rom_byte_address => ou18_rom_byte_address,
            i_rom_response_valid => i_rom_response_valid,
            iu16_rom_response_data => iu16_rom_response_data,
            i_view_enable => i_view_enable,
            iu5_view_target => iu5_view_target,
            iu15_view_word_address => iu15_view_word_address,
            o_view_valid => o_view_valid,
            ou16_view_data => ou16_view_data,
            i_bitmap_read_enable => '0',
            iu15_bitmap_word_address => (others => '0'),
            ou16_bitmap_data => open,
            i_palette_read_enable => '0',
            iu10_palette_word_address => (others => '0'),
            ou16_palette_data => open,
            i_sprite_request => '0',
            iu11_sprite_word_address => (others => '0'),
            o_sprite_response_valid => open,
            ou16_sprite_data => open,
            i_tile_request => '0',
            iu13_tile_word_address => (others => '0'),
            o_tile_response_valid => open,
            ou16_tile_data => open
        );
end architecture;
