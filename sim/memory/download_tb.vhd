library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity download_tb is
end entity;

architecture test of download_tb is
    signal s_clk : std_logic := '0';
    signal s_download, s_word_valid : std_logic := '0';
    signal s_word_ready, s_loading, s_request, s_reset, s_image_valid, s_error, s_done : std_logic;
    signal s_idle_allow, s_accept_allow : std_logic := '0';
    signal s_pending, s_response : std_logic := '0';
    signal s_idle, s_loader_ready : std_logic;
    signal su27_address, su27_loader_address, su27_loaded : unsigned(26 downto 0) := (others => '0');
    signal su16_data, su16_loader_data : unsigned(15 downto 0) := (others => '0');
    signal su2_bytes : unsigned(1 downto 0);
    signal sint_writes : natural := 0;
    signal sint_epoch : natural := 0;
    signal sint_done_count : natural := 0;
begin
    s_clk <= not s_clk after 5 ns;
    s_idle <= s_idle_allow and not s_pending;
    s_loader_ready <= s_loading and s_accept_allow and not s_pending;
    dut : entity work.rabbitpunch_download
        generic map (sint_IMAGE_BYTES => 16)
        port map (
            i_clk => s_clk,
            i_download => s_download,
            i_word_valid => s_word_valid,
            o_word_ready => s_word_ready,
            iu27_word_byte_address => su27_address,
            iu16_word_data => su16_data,
            i_transport_idle => s_idle,
            i_loader_ready => s_loader_ready,
            i_loader_response_valid => s_response,
            o_loading => s_loading,
            o_loader_request => s_request,
            ou27_loader_byte_address => su27_loader_address,
            ou16_loader_data => su16_loader_data,
            ou2_loader_bytes => su2_bytes,
            o_game_reset => s_reset,
            o_image_valid => s_image_valid,
            o_error => s_error,
            o_done => s_done,
            ou27_bytes_loaded => su27_loaded
        );
    backend : process(s_clk)
        variable vint_delay : natural := 0;
        variable vint_writes : natural := 0;
    begin
        if (rising_edge(s_clk)) then
            s_response <= '0';
            if (s_done = '1') then
                sint_done_count <= sint_done_count + 1;
            end if;
            if (s_request = '1') then
                assert (s_loader_ready = '1' and s_pending = '0' and su2_bytes = "11")
                    report "Bad or duplicated physical loader request" severity failure;
                assert (su16_loader_data = sint_epoch * 256 + to_integer(su27_loader_address))
                    report "Loader did not retain accepted word data" severity failure;
                vint_writes := vint_writes + 1;
                sint_writes <= vint_writes;
                vint_delay := vint_writes mod 7 + 1;
                s_pending <= '1';
            elsif (s_pending = '1') then
                if (vint_delay = 0) then
                    s_response <= '1';
                    s_pending <= '0';
                else
                    vint_delay := vint_delay - 1;
                end if;
            end if;
        end if;
    end process;
    stimulus : process
        procedure cycles(vint_count : positive) is
        begin
            for vint_cycle in 1 to vint_count loop
                wait until falling_edge(s_clk);
            end loop;
        end procedure;
        procedure offer_word(vint_address : natural) is
        begin
            if (s_word_ready /= '1') then
                wait until s_word_ready = '1' for 2 us;
            end if;
            assert (s_word_ready = '1') report "Stream never became ready" severity failure;
            wait until falling_edge(s_clk);
            su27_address <= to_unsigned(vint_address, 27);
            su16_data <= to_unsigned(sint_epoch * 256 + vint_address, 16);
            s_word_valid <= '1';
            cycles(1);
            s_word_valid <= '0';
            su27_address <= (others => '1');
            su16_data <= (others => '1');
        end procedure;
        procedure begin_image(vint_epoch : natural) is
        begin
            sint_epoch <= vint_epoch;
            s_download <= '1';
            wait until s_loading = '1' for 2 us;
            assert (s_loading = '1' and s_reset = '1' and s_image_valid = '0')
                report "Image start did not hold game reset" severity failure;
            cycles(1);
        end procedure;
    begin
        cycles(3);
        assert (s_reset = '1' and s_image_valid = '0' and s_loading = '0')
            report "Game released before first image" severity failure;
        -- Old gameplay traffic must drain before loading mode/cache invalidation.
        s_download <= '1';
        cycles(9);
        assert (s_loading = '0' and s_word_ready = '0' and sint_writes = 0)
            report "Loading began before transport drained" severity failure;
        s_idle_allow <= '1';
        wait until s_loading = '1';
        offer_word(0);
        cycles(9);
        assert (s_word_ready = '0' and sint_writes = 0 and su27_loaded = 0)
            report "Unready backend lost backpressure" severity failure;
        s_accept_allow <= '1';
        for vint_word in 1 to 7 loop
            offer_word(vint_word * 2);
        end loop;
        -- End the stream before the final accepted word has received its reply.
        s_download <= '0';
        s_idle_allow <= '0';
        cycles(20);
        assert (su27_loaded = 16 and s_loading = '1' and s_reset = '1' and s_image_valid = '0')
            report "Image released before final transport drain" severity failure;
        s_idle_allow <= '1';
        wait until s_image_valid = '1' for 2 us;
        cycles(2);
        assert (s_reset = '0' and s_error = '0' and sint_writes = 8 and sint_done_count = 1)
            report "Complete image was not committed exactly once" severity failure;
        cycles(15);
        assert (s_loading = '0' and sint_writes = 8 and sint_done_count = 1)
            report "Idle image triggered another copy" severity failure;
        -- Replacing an image resets ownership/count and cannot reuse old validity.
        begin_image(1);
        for vint_word in 0 to 7 loop
            offer_word(vint_word * 2);
        end loop;
        s_download <= '0';
        wait until s_image_valid = '1' for 2 us;
        cycles(2);
        assert (s_reset = '0' and s_error = '0' and sint_writes = 16 and sint_done_count = 2)
            report "Replacement image failed" severity failure;
        -- A short image remains unusable after its accepted write drains.
        begin_image(2);
        offer_word(0);
        s_download <= '0';
        cycles(30);
        assert (s_error = '1' and s_reset = '1' and s_image_valid = '0' and
            s_loading = '0' and su27_loaded = 2 and sint_writes = 17)
            report "Short image was accepted" severity failure;
        -- Wrong or odd addresses are rejected before any memory write is issued.
        begin_image(3);
        offer_word(1);
        s_download <= '0';
        cycles(12);
        assert (s_error = '1' and s_reset = '1' and s_loading = '0' and sint_writes = 17)
            report "Malformed stream reached memory" severity failure;
        -- A fresh full image recovers from earlier errors.
        begin_image(4);
        for vint_word in 0 to 7 loop
            offer_word(vint_word * 2);
        end loop;
        s_download <= '0';
        wait until s_image_valid = '1' for 2 us;
        cycles(2);
        assert (s_error = '0' and s_reset = '0' and sint_writes = 25 and sint_done_count = 3)
            report "Download failed to recover after bad image" severity failure;
        report "DOWNLOAD_PASS writes=" & integer'image(sint_writes);
        finish;
        wait;
    end process;
    process
    begin
        wait for 30 us;
        assert false report "Download test timeout" severity failure;
    end process;
end architecture;
