library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Logical sound board. The caller supplies synchronous 4 MHz/2 MHz enables,
-- an audio-ROM byte transport, and the main board's existing command latch.
entity rabbitpunch_sound_board is
    generic (
        GBOOL_STATE_CAPABLE : boolean := false
    );
    port (
        i_clk : in std_logic;
        i_reset : in std_logic;
        i_cpu_enable : in std_logic;
        i_ym_enable : in std_logic;
        i_ym_half_enable : in std_logic;
        i_pause : in std_logic;
        o_paused : out std_logic;
        iu8_command : in unsigned(7 downto 0);
        i_command_pending : in std_logic;
        o_command_read : out std_logic;
        o_rom_request : out std_logic;
        ou16_rom_address : out unsigned(15 downto 0);
        i_rom_ready : in std_logic;
        i_rom_response_valid : in std_logic;
        iu8_rom_response_data : in unsigned(7 downto 0);
        o_adpcm_control_write : out std_logic;
        o_adpcm_command_write : out std_logic;
        ou8_adpcm_data : out unsigned(7 downto 0);
        ou16_left_pcm : out unsigned(15 downto 0);
        ou16_right_pcm : out unsigned(15 downto 0);
        o_sample_marker : out std_logic;
        i_view_enable : in std_logic;
        iu11_view_address : in unsigned(10 downto 0);
        ou8_view_data : out unsigned(7 downto 0);
        o_debug_request : out std_logic;
        o_debug_write : out std_logic;
        ou16_debug_address : out unsigned(15 downto 0);
        ou8_debug_data : out unsigned(7 downto 0);
        i_capture_request : in std_logic := '0';
        i_capture_cancel : in std_logic := '0';
        o_capture_pending : out std_logic := '0';
        o_state_held : out std_logic := '0';
        o_state_cpu_drained : out std_logic := '0';
        i_state_resume : in std_logic := '0';
        i_cpu_state_write : in std_logic := '0';
        iu256_cpu_state : in unsigned(255 downto 0) := (others => '0');
        ou256_cpu_state : out unsigned(255 downto 0) := (others => '0');
        i_state_hold : in std_logic := '0';
        i_fm_state_write : in std_logic := '0';
        iu16_chip_state_word_address : in unsigned(15 downto 0) := (others => '0');
        iu32_chip_state_write_data : in unsigned(31 downto 0) := (others => '0');
        ou32_fm_state_read_data : out unsigned(31 downto 0) := (others => '0');
        i_state_memory_access : in std_logic := '0';
        i_state_memory_request : in std_logic := '0';
        i_state_memory_write : in std_logic := '0';
        iu16_state_memory_address : in unsigned(15 downto 0) := (others => '0');
        iu8_state_memory_data : in unsigned(7 downto 0) := (others => '0');
        o_state_memory_response : out std_logic := '0';
        ou8_state_memory_data : out unsigned(7 downto 0) := (others => '0');
        o_state_bus_idle : out std_logic := '0'
    );
end entity;

architecture rtl of rabbitpunch_sound_board is
    signal s_request, s_write, s_response, s_ym_write, s_ym_data, s_ym_interrupt, s_paused : std_logic;
    signal s_cpu_held, s_bus_idle, s_bus_request, s_bus_write, s_cpu_response : std_logic;
    signal s_state_response_owner : std_logic := '0';
    signal s_cpu_resume, s_cpu_reset : std_logic;
    signal s_state_reset_drain : std_logic := '0';
    signal su16_bus_address : unsigned(15 downto 0);
    signal su8_bus_data : unsigned(7 downto 0);
    signal su16_address : unsigned(15 downto 0);
    signal su8_data, su8_reply, su8_ym_status, su8_ym_data : unsigned(7 downto 0);
begin
    o_state_held <= s_cpu_held;
    o_state_cpu_drained <= s_cpu_held and s_bus_idle;
    o_state_bus_idle <= s_bus_idle and not s_state_response_owner;
    s_bus_request <= i_state_memory_request when i_state_memory_access = '1' else s_request;
    s_bus_write <= i_state_memory_write when i_state_memory_access = '1' else s_write;
    su16_bus_address <= iu16_state_memory_address when i_state_memory_access = '1' else su16_address;
    su8_bus_data <= iu8_state_memory_data when i_state_memory_access = '1' else su8_data;
    -- Accepted response ownership outlives a canceled access mode. In
    -- particular, a late state-RAM reply must never become a CPU reply.
    s_cpu_response <= s_response and not s_state_response_owner;
    o_state_memory_response <= s_response and s_state_response_owner;
    s_cpu_reset <= i_reset or s_state_reset_drain;
    s_cpu_resume <= i_state_resume and not s_cpu_reset and s_bus_idle and
        not s_state_response_owner and not i_state_memory_access;
    ou8_state_memory_data <= su8_reply;
    response_owner : process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            assert (i_state_memory_access = '0' or ((s_cpu_held = '1' or s_cpu_reset = '1') and s_request = '0'))
                report "Sound state RAM access requires a captured CPU" severity failure;
            assert (i_state_memory_request = '0' or (i_state_memory_access = '1' and iu16_state_memory_address >= x"F800"))
                report "Sound state memory request escaped work RAM" severity failure;
            assert (i_state_hold = '0' or s_cpu_reset = '1' or (s_cpu_held = '1' and
                (s_bus_idle = '1' or i_state_memory_access = '1' or s_state_response_owner = '1')))
                report "Sound chip hold requires drained CPU/backend transactions: held=" & std_logic'image(s_cpu_held) &
                    " idle=" & std_logic'image(s_bus_idle) & " access=" & std_logic'image(i_state_memory_access) &
                    " owner=" & std_logic'image(s_state_response_owner) & " reset=" & std_logic'image(s_cpu_reset) severity failure;
            assert (i_reset = '1' or i_state_resume = '0' or (s_bus_idle = '1' and s_state_response_owner = '0' and i_state_memory_access = '0'))
                report "Sound CPU resume requires retired RAM response ownership" severity failure;
            -- Gameplay reset does not erase accepted backend debt. The bus
            -- remains live and retires its reply before another owner starts.
            if (s_bus_request = '1') then
                s_state_response_owner <= i_state_memory_access;
            elsif (s_response = '1') then
                s_state_response_owner <= '0';
            end if;
            if (i_reset = '1' and (s_state_response_owner = '1' or i_state_memory_access = '1')) then
                s_state_reset_drain <= '1';
            elsif (s_state_reset_drain = '1' and s_state_response_owner = '0' and i_state_memory_access = '0') then
                s_state_reset_drain <= '0';
            end if;
        end if;
    end process;
    o_paused <= s_paused;
    o_debug_request <= s_request;
    o_debug_write <= s_write;
    ou16_debug_address <= su16_address;
    ou8_debug_data <= su8_data;
    assert (i_view_enable /= '1' or s_paused = '1')
        report "Sound RAM inspection requires drained CPU pause" severity failure;
    sound_cpu : entity work.rabbitpunch_soundcpu
        generic map (
            GBOOL_STATE_CAPABLE => GBOOL_STATE_CAPABLE
        )
        port map (
            i_clk => i_clk,
            i_reset => s_cpu_reset,
            i_enable => i_cpu_enable,
            i_pause => i_pause,
            i_interrupt => s_ym_interrupt or i_command_pending,
            o_request => s_request,
            o_request_write => s_write,
            ou16_request_address => su16_address,
            ou8_request_data => su8_data,
            i_response_valid => s_cpu_response,
            iu8_response_data => su8_reply,
            o_paused => s_paused,
            o_halted => open,
            i_capture_request => i_capture_request,
            i_capture_cancel => i_capture_cancel,
            o_capture_pending => o_capture_pending,
            o_state_held => s_cpu_held,
            i_state_resume => s_cpu_resume,
            i_state_write => i_cpu_state_write and not s_cpu_reset,
            iu256_state_data => iu256_cpu_state,
            ou256_state_data => ou256_cpu_state
        );
    sound_bus : entity work.rabbitpunch_sound_bus
        port map (
            i_clk => i_clk,
            i_request => s_bus_request,
            i_request_write => s_bus_write,
            iu16_request_address => su16_bus_address,
            iu8_request_data => su8_bus_data,
            o_response_valid => s_response,
            ou8_response_data => su8_reply,
            o_rom_request => o_rom_request,
            ou16_rom_address => ou16_rom_address,
            i_rom_ready => i_rom_ready,
            i_rom_response_valid => i_rom_response_valid,
            iu8_rom_response_data => iu8_rom_response_data,
            i_ym_write_enable => i_ym_half_enable,
            iu8_ym_status => su8_ym_status,
            o_ym_write => s_ym_write,
            o_ym_data_register => s_ym_data,
            ou8_ym_write_data => su8_ym_data,
            iu8_command => iu8_command,
            o_command_read => o_command_read,
            o_adpcm_control_write => o_adpcm_control_write,
            o_adpcm_command_write => o_adpcm_command_write,
            ou8_adpcm_data => ou8_adpcm_data,
            i_view_enable => i_view_enable,
            iu11_view_address => iu11_view_address,
            ou8_view_data => ou8_view_data,
            o_idle => s_bus_idle
        );
    ym2151 : entity work.rabbitpunch_ym2151
        generic map (
            GBOOL_STATE_CAPABLE => GBOOL_STATE_CAPABLE
        )
        port map (
            i_clk => i_clk,
            i_reset => i_reset,
            i_chip_enable => i_ym_enable,
            i_half_chip_enable => i_ym_half_enable,
            i_chip_select => s_ym_write,
            i_write => s_ym_write,
            i_data_register => s_ym_data,
            iu8_write_data => su8_ym_data,
            ou8_status => su8_ym_status,
            o_interrupt => s_ym_interrupt,
            o_sample_marker => o_sample_marker,
            ou16_left_pcm => ou16_left_pcm,
            ou16_right_pcm => ou16_right_pcm,
            ou16_full_left_pcm => open,
            ou16_full_right_pcm => open,
            i_state_hold => i_state_hold and not i_reset,
            i_state_write => i_fm_state_write and not i_reset,
            iu16_state_word_address => iu16_chip_state_word_address,
            iu32_state_write_data => iu32_chip_state_write_data,
            ou32_state_read_data => ou32_fm_state_read_data
        );
end architecture;
