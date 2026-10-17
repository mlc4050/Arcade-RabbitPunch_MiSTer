library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;
use work.rabbitpunch_sdram_types.all;

-- Byte clients around the existing read-only burst cache: port 0 sound CPU,
-- port 1 sample chip, port 2 unused. Invalidate only after clients/transport drain.
entity rabbitpunch_audio_roms is
    port (
        i_clk : in std_logic;
        i_invalidate : in std_logic;
        o_idle : out std_logic;
        i_program_request : in std_logic;
        o_program_ready : out std_logic;
        iu16_program_address : in unsigned(15 downto 0);
        o_program_response_valid : out std_logic;
        ou8_program_data : out unsigned(7 downto 0);
        i_sample_request : in std_logic;
        iu18_sample_address : in unsigned(17 downto 0);
        o_sample_valid : out std_logic;
        ou8_sample_data : out unsigned(7 downto 0);
        ou3_backend_requests : out unsigned(2 downto 0);
        iu3_backend_ready : in unsigned(2 downto 0);
        ou27_backend_byte_addresses : out t_sdram_addresses;
        iu3_backend_response_valid : in unsigned(2 downto 0);
        iu64_backend_read_data : in t_sdram_read_data
    );
end entity;

architecture rtl of rabbitpunch_audio_roms is
    type t_state is (STATE_IDLE, STATE_REQUEST, STATE_RESPONSE);
    type t_states is array (0 to 1) of t_state;
    signal styp_states : t_states := (others => STATE_IDLE);
    type t_offsets is array (0 to 1) of unsigned(2 downto 0);
    signal su3_offsets : t_offsets := (others => "000");
    signal su3_cache_requests, su3_cache_ready, su3_cache_valid : unsigned(2 downto 0);
    signal su27_cache_addresses : t_sdram_addresses := (others => (others => '0'));
    signal su64_cache_data : t_sdram_read_data;
    signal s_cache_idle, s_front_idle, s_sample_cached, s_sample_valid : std_logic := '0';
    signal su18_requested_sample, su18_sample_tag : unsigned(17 downto 0) := (others => '0');
    signal su8_sample_data : unsigned(7 downto 0);
    function select_byte(vu64_data : unsigned(63 downto 0); vu3_offset : unsigned(2 downto 0)) return unsigned is
        variable vu64_shifted : unsigned(63 downto 0);
    begin
        vu64_shifted := shift_right(vu64_data, to_integer(vu3_offset & "000"));
        return vu64_shifted(7 downto 0);
    end function;
begin
    s_front_idle <= '1' when styp_states(0) = STATE_IDLE and styp_states(1) = STATE_IDLE else '0';
    o_idle <= s_front_idle and s_cache_idle;
    o_program_ready <= '1' when styp_states(0) = STATE_IDLE and i_invalidate = '0' else '0';
    s_sample_valid <= '1' when s_sample_cached = '1' and i_sample_request = '1' and
        iu18_sample_address = su18_sample_tag and i_invalidate = '0' else '0';
    o_sample_valid <= s_sample_valid;
    ou8_sample_data <= su8_sample_data;
    su3_cache_requests(2) <= '0';
    su27_cache_addresses(2) <= (others => '0');
    clients : for gint_client in 0 to 1 generate
        su3_cache_requests(gint_client) <= '1' when styp_states(gint_client) = STATE_REQUEST and
            su3_cache_ready(gint_client) = '1' else '0';
    end generate;
    cache : entity work.rabbitpunch_rom_cache
        port map (
            i_clk => i_clk,
            i_invalidate => i_invalidate,
            o_idle => s_cache_idle,
            iu3_requests => su3_cache_requests,
            ou3_ready => su3_cache_ready,
            iu27_byte_addresses => su27_cache_addresses,
            ou3_response_valid => su3_cache_valid,
            ou64_read_data => su64_cache_data,
            ou3_backend_requests => ou3_backend_requests,
            iu3_backend_ready => iu3_backend_ready,
            ou27_backend_byte_addresses => ou27_backend_byte_addresses,
            iu3_backend_response_valid => iu3_backend_response_valid,
            iu64_backend_read_data => iu64_backend_read_data
        );
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_program_response_valid <= '0';
            if (i_invalidate = '1') then
                assert (s_front_idle = '1' and s_cache_idle = '1')
                    report "Audio ROM frontend must drain before image invalidation" severity failure;
                assert (i_program_request = '0' and i_sample_request = '0')
                    report "Audio ROM clients must quiesce during invalidation" severity failure;
                s_sample_cached <= '0';
            else
                case styp_states(0) is
                    when STATE_IDLE =>
                        if (i_program_request = '1') then
                            su3_offsets(0) <= iu16_program_address(2 downto 0);
                            su27_cache_addresses(0) <= to_unsigned(CINT_ROM_AUDIOCPU_BASE, 27) +
                                resize(iu16_program_address(15 downto 3) & "000", 27);
                            styp_states(0) <= STATE_REQUEST;
                        end if;
                    when STATE_REQUEST =>
                        if (su3_cache_ready(0) = '1') then
                            styp_states(0) <= STATE_RESPONSE;
                        end if;
                    when STATE_RESPONSE =>
                        if (su3_cache_valid(0) = '1') then
                            ou8_program_data <= select_byte(su64_cache_data(0), su3_offsets(0));
                            o_program_response_valid <= '1';
                            styp_states(0) <= STATE_IDLE;
                        end if;
                end case;
                case styp_states(1) is
                    when STATE_IDLE =>
                        if (i_sample_request = '1' and s_sample_valid = '0') then
                            su3_offsets(1) <= iu18_sample_address(2 downto 0);
                            su18_requested_sample <= iu18_sample_address;
                            su27_cache_addresses(1) <= to_unsigned(CINT_ROM_UPD_BASE, 27) +
                                resize(iu18_sample_address(17 downto 3) & "000", 27);
                            styp_states(1) <= STATE_REQUEST;
                        end if;
                    when STATE_REQUEST =>
                        if (su3_cache_ready(1) = '1') then
                            styp_states(1) <= STATE_RESPONSE;
                        end if;
                    when STATE_RESPONSE =>
                        if (su3_cache_valid(1) = '1') then
                            su8_sample_data <= select_byte(su64_cache_data(1), su3_offsets(1));
                            su18_sample_tag <= su18_requested_sample;
                            s_sample_cached <= '1';
                            styp_states(1) <= STATE_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
