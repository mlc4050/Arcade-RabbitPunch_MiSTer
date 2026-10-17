library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.rabbitpunch_layout.all;

entity cpu_sdram_boot_tb is
    generic (
        WRITE_LIMIT : positive := 10000;
        DIP_DEFAULT : natural := 0
    );
end entity;

architecture test of cpu_sdram_boot_tb is
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
    signal s_reset : std_logic := '1';
    signal s_pause : std_logic := '0';
    signal s_request, s_write, s_paused, s_response_valid : std_logic;
    signal su24_address : unsigned(23 downto 0);
    signal su16_write_data, su16_response_data : unsigned(15 downto 0);
    signal su2_bytes : unsigned(1 downto 0);
    signal s_memory_valid, s_memory_supported, s_rom_request, s_rom_valid, s_io_valid : std_logic;
    signal su16_memory_data, su16_rom_data, su16_io_data : unsigned(15 downto 0);
    signal su18_rom_address : unsigned(17 downto 0);
    signal s_rom_ready, s_rom_idle : std_logic;
    signal s_sound_pending, s_irq_configure, s_irq_twice, s_irq_pending, s_irq_ack : std_logic;
    signal su16_flags : unsigned(15 downto 0);
    signal su9_scroll0_y, su9_scroll0_x, su9_scroll1_y, su9_scroll1_x : unsigned(8 downto 0);
    signal su6_count, su6_priority : unsigned(5 downto 0);
    signal su4_gga_selected : unsigned(3 downto 0);
    signal su4_gga_view : unsigned(3 downto 0) := (others => '0');
    signal su8_gga_data : unsigned(7 downto 0);
    signal su16_dq : unsigned(15 downto 0);
    signal su13_sdram_address : unsigned(12 downto 0);
    signal su2_bank, su2_mask : unsigned(1 downto 0);
    signal s_chip, s_write_n, s_row_n, s_column_n, s_cke : std_logic;
    signal sint_writes, sint_reads : natural := 0;
begin
    s_clk <= not s_clk after 10417 ps;
    s_response_valid <= s_memory_valid or s_io_valid;
    su16_response_data <= su16_memory_data when s_memory_valid = '1' else su16_io_data;
    cpu : entity work.rabbitpunch_maincpu
        port map (
            i_clk => s_clk,
            i_reset => s_reset,
            i_pause => s_pause,
            i_interrupt_level1 => s_irq_pending,
            o_interrupt_acknowledge => s_irq_ack,
            o_request => s_request,
            o_request_write => s_write,
            ou24_request_address => su24_address,
            ou16_request_data => su16_write_data,
            ou2_request_bytes => su2_bytes,
            i_response_valid => s_response_valid,
            iu16_response_data => su16_response_data,
            o_paused => s_paused
        );
    memory : entity work.rabbitpunch_memory
        port map (
            i_clk => s_clk,
            i_request => s_request,
            i_request_write => s_write,
            iu24_request_address => su24_address,
            iu16_request_data => su16_write_data,
            iu2_request_bytes => su2_bytes,
            o_request_supported => s_memory_supported,
            o_response_valid => s_memory_valid,
            ou16_response_data => su16_memory_data,
            o_rom_request => s_rom_request,
            ou18_rom_byte_address => su18_rom_address,
            i_rom_response_valid => s_rom_valid,
            iu16_rom_response_data => su16_rom_data,
            i_view_enable => '0',
            iu5_view_target => TARGET_NONE,
            iu15_view_word_address => (others => '0'),
            o_view_valid => open,
            ou16_view_data => open
        );
    io_registers : entity work.rabbitpunch_io
        port map (
            i_clk => s_clk,
            i_initialize => s_reset,
            i_request => s_request and not s_memory_supported,
            i_request_write => s_write,
            iu24_request_address => su24_address,
            iu16_request_data => su16_write_data,
            iu2_request_bytes => su2_bytes,
            o_response_valid => s_io_valid,
            ou16_response_data => su16_io_data,
            iu8_player1 => (others => '0'),
            iu8_player2 => (others => '0'),
            iu8_service => (others => '0'),
            iu16_dips => to_unsigned(DIP_DEFAULT, 16),
            i_sound_command_read => '0',
            o_sound_command_write => open,
            ou8_sound_command => open,
            o_sound_pending => s_sound_pending,
            ou16_video_flags => su16_flags,
            ou9_scroll0_y => su9_scroll0_y,
            ou9_scroll0_x => su9_scroll0_x,
            ou9_scroll1_y => su9_scroll1_y,
            ou9_scroll1_x => su9_scroll1_x,
            ou6_sprite_count => su6_count,
            ou6_sprite_priority => su6_priority,
            ou4_gga_selected => su4_gga_selected,
            iu4_gga_view_address => su4_gga_view,
            ou8_gga_view_data => su8_gga_data,
            o_gga_write => open,
            ou4_gga_write_address => open,
            ou8_gga_write_data => open,
            o_irq_configure => s_irq_configure,
            o_irq_twice_per_frame => s_irq_twice
        );
    interrupts : entity work.rabbitpunch_irq
        port map (
            i_clk => s_clk,
            i_initialize => s_reset,
            i_configure => s_irq_configure,
            i_twice_per_frame => s_irq_twice,
            i_vblank_start => '0',
            i_half_frame => '0',
            i_acknowledge => s_irq_ack,
            o_level1_pending => s_irq_pending
        );
    roms : entity work.rabbitpunch_roms
        port map (
            i_clk => s_clk,
            i_initialize => '0',
            o_ready => s_rom_ready,
            o_idle => s_rom_idle,
            i_loading => '0',
            i_loader_request => '0',
            o_loader_ready => open,
            iu27_loader_byte_address => (others => '0'),
            iu16_loader_data => (others => '0'),
            iu2_loader_bytes => "00",
            o_loader_response_valid => open,
            i_sprite_request => '0',
            iu17_sprite_word_address => (others => '0'),
            o_sprite_response_valid => open,
            ou32_sprite_response_data => open,
            i_tile_request => '0',
            iu17_tile_word_address => (others => '0'),
            i_tile_foreground => '0',
            o_tile_response_valid => open,
            ou32_tile_response_data => open,
            i_cpu_request => s_rom_request,
            iu18_cpu_byte_address => su18_rom_address,
            o_cpu_response_valid => s_rom_valid,
            ou16_cpu_response_data => su16_rom_data,
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

    trace : process(s_clk)
        file v_trace : text open write_mode is "rtl_writes.txt";
        variable v_line : line;
        variable vu16_mask : unsigned(15 downto 0);
        variable vint_writes, vint_reads : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            if (s_request = '1') then
                if (s_write = '1') then
                    vu16_mask := (others => '0');
                    if (su2_bytes(0) = '1') then
                        vu16_mask(7 downto 0) := (others => '1');
                    end if;
                    if (su2_bytes(1) = '1') then
                        vu16_mask(15 downto 8) := (others => '1');
                    end if;
                    write(v_line, to_hstring(resize(su24_address(19 downto 0), 24)) & " " &
                        to_hstring(vu16_mask) & " " & to_hstring(su16_write_data and vu16_mask));
                    writeline(v_trace, v_line);
                    flush(v_trace);
                    vint_writes := vint_writes + 1;
                else
                    assert (not (su24_address(19 downto 0) = 16#C001E# and s_sound_pending = '1'))
                        report "Boot prefix requires an executing sound CPU" severity failure;
                    vint_reads := vint_reads + 1;
                end if;
            end if;
            sint_writes <= vint_writes;
            sint_reads <= vint_reads;
        end if;
    end process;
    stimulus : process
        file v_state : text open write_mode is "rtl_io_state.txt";
        variable v_line : line;
        constant HEX_CHARACTERS : string := "0123456789abcdef";
        procedure state_word(v_name : string; vu_word : unsigned) is
        begin
            write(v_line, v_name & " " & to_hstring(resize(vu_word, 16)));
            writeline(v_state, v_line);
        end procedure;
    begin
        wait until s_rom_ready = '1';
        for vint_wait in 0 to 99 loop
            wait until falling_edge(s_clk);
        end loop;
        s_reset <= '0';
        wait until sint_writes = WRITE_LIMIT;
        wait until falling_edge(s_clk);
        s_pause <= '1';
        wait until s_paused = '1';
        for vint_wait in 0 to 2 loop
            wait until falling_edge(s_clk);
        end loop;
        assert (sint_writes = WRITE_LIMIT and s_rom_idle = '1') report "CPU or ROM transport did not drain" severity failure;
        state_word("flags", su16_flags);
        state_word("scroll0_y", su9_scroll0_y);
        state_word("scroll0_x", su9_scroll0_x);
        state_word("scroll1_y", su9_scroll1_y);
        state_word("scroll1_x", su9_scroll1_x);
        state_word("sprite_count", su6_count);
        state_word("sprite_priority", su6_priority);
        state_word("gga_selected", su4_gga_selected);
        for vint_register in 0 to 15 loop
            wait until falling_edge(s_clk);
            su4_gga_view <= to_unsigned(vint_register, 4);
            wait for 1 ns;
            state_word("gga0" & HEX_CHARACTERS(vint_register + 1), su8_gga_data);
        end loop;
        file_close(v_state);
        report "CPU_SDRAM_BOOT_PASS writes=" & integer'image(sint_writes) & " reads=" & integer'image(sint_reads);
        finish;
        wait;
    end process;
    progress : process
        file v_progress : text open write_mode is "boot_progress.txt";
        variable v_line : line;
    begin
        loop
            wait for 250 us;
            write(v_line, time'image(now) & "; writes=" & integer'image(sint_writes) & "; reads=" & integer'image(sint_reads));
            writeline(v_progress, v_line);
            flush(v_progress);
        end loop;
    end process;
    process
    begin
        wait for 100 ms;
        assert false report "CPU SDRAM boot prefix timeout" severity failure;
    end process;
end architecture;
