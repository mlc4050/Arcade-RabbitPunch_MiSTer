library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_sdram_types.all;

-- Always-running read-only transport. Client 0 sprites, 1 tiles, 2 main CPU.
-- Accept one pulse per requester; queue it until the SDRAM client is ready.
-- Consumers must drain outstanding replies before restarting their transaction
-- stream. Game reset must not reset the shared transport or ROM contents.
entity rabbitpunch_rom_requests is
    port (
        i_clk : in std_logic;
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
        o_idle : out std_logic;
        ou3_backend_requests : out unsigned(2 downto 0);
        iu3_backend_ready : in unsigned(2 downto 0);
        ou27_backend_byte_addresses : out t_sdram_addresses;
        iu3_backend_response_valid : in unsigned(2 downto 0);
        iu64_backend_read_data : in t_sdram_read_data
    );
end entity;

architecture rtl of rabbitpunch_rom_requests is
    signal su3_pending, su3_queued : unsigned(2 downto 0) := "000";
    signal su3_incoming : unsigned(2 downto 0);
    signal su27_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su27_incoming_addresses : t_sdram_addresses;
    type t_offsets is array (0 to 2) of unsigned(2 downto 0);
    signal su3_offsets : t_offsets := (others => (others => '0'));
    signal s_sprite_valid, s_tile_valid, s_cpu_valid : std_logic := '0';
    signal su16_cpu_word : unsigned(15 downto 0);
begin
    su3_incoming <= i_cpu_request & i_tile_request & i_sprite_request;
    su27_incoming_addresses(0) <= to_unsigned(CINT_ROM_SPRITES_BASE, 27) + shift_left(resize(iu17_sprite_word_address, 27), 2);
    su27_incoming_addresses(1) <= to_unsigned(CINT_ROM_TILES2_BASE, 27) + shift_left(resize(iu17_tile_word_address, 27), 2)
        when i_tile_foreground = '1' else
        to_unsigned(CINT_ROM_TILES1_BASE, 27) + shift_left(resize(iu17_tile_word_address, 27), 2);
    su27_incoming_addresses(2) <= resize(iu18_cpu_byte_address, 27);
    ou27_backend_byte_addresses <= su27_addresses;
    ou3_backend_requests <= su3_queued and iu3_backend_ready;
    o_idle <= '1' when su3_pending = "000" else '0';
    o_sprite_response_valid <= s_sprite_valid;
    o_tile_response_valid <= s_tile_valid;
    o_cpu_response_valid <= s_cpu_valid;
    -- Raw stream bytes occupy ascending byte lanes. 68000 words are big endian.
    ou16_cpu_response_data <= su16_cpu_word(7 downto 0) & su16_cpu_word(15 downto 8);

    process(i_clk)
        variable vint_offset : natural range 0 to 48;
    begin
        if (rising_edge(i_clk)) then
            s_sprite_valid <= '0';
            s_tile_valid <= '0';
            s_cpu_valid <= '0';
            for vint_client in 0 to 2 loop
                if (su3_queued(vint_client) = '1' and iu3_backend_ready(vint_client) = '1') then
                    su3_queued(vint_client) <= '0';
                end if;
                if (iu3_backend_response_valid(vint_client) = '1') then
                    assert (su3_pending(vint_client) = '1' and su3_queued(vint_client) = '0')
                        report "Unexpected ROM transport reply" severity failure;
                    su3_pending(vint_client) <= '0';
                    vint_offset := to_integer(su3_offsets(vint_client)) * 8;
                    case vint_client is
                        when 0 =>
                            ou32_sprite_response_data <= iu64_backend_read_data(0)(vint_offset + 31 downto vint_offset);
                            s_sprite_valid <= '1';
                        when 1 =>
                            ou32_tile_response_data <= iu64_backend_read_data(1)(vint_offset + 31 downto vint_offset);
                            s_tile_valid <= '1';
                        when 2 =>
                            su16_cpu_word <= iu64_backend_read_data(2)(vint_offset + 15 downto vint_offset);
                            s_cpu_valid <= '1';
                    end case;
                end if;
                if (su3_incoming(vint_client) = '1') then
                    assert (su3_pending(vint_client) = '0') report "ROM requester has more than one pending request" severity failure;
                    if (vint_client = 2) then
                        assert (iu18_cpu_byte_address(0) = '0') report "Unaligned 68000 ROM word" severity failure;
                    end if;
                    su3_offsets(vint_client) <= su27_incoming_addresses(vint_client)(2 downto 0);
                    su27_addresses(vint_client) <= su27_incoming_addresses(vint_client)(26 downto 3) & "000";
                    su3_pending(vint_client) <= '1';
                    su3_queued(vint_client) <= '1';
                end if;
            end loop;
        end if;
    end process;
end architecture;
