library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rabbitpunch_layout.all;

-- Sequential 16-bit raw-image stream, independent of game reset.
-- A word is accepted only on valid/ready. The memory transport remains live.
entity rabbitpunch_download is
    generic (
        GINT_IMAGE_BYTES : positive := CINT_ROM_IMAGE_SIZE
    );
    port (
        i_clk : in std_logic;
        i_download : in std_logic;
        i_word_valid : in std_logic;
        o_word_ready : out std_logic;
        iu27_word_byte_address : in unsigned(26 downto 0);
        iu16_word_data : in unsigned(15 downto 0);
        i_transport_idle : in std_logic;
        i_loader_ready : in std_logic;
        i_loader_response_valid : in std_logic;
        o_loading : out std_logic;
        o_loader_request : out std_logic;
        ou27_loader_byte_address : out unsigned(26 downto 0);
        ou16_loader_data : out unsigned(15 downto 0);
        ou2_loader_bytes : out unsigned(1 downto 0);
        o_game_reset : out std_logic;
        o_image_valid : out std_logic;
        o_error : out std_logic;
        o_done : out std_logic;
        ou27_bytes_loaded : out unsigned(26 downto 0)
    );
end entity;

architecture rtl of rabbitpunch_download is
    type t_state is (STATE_NO_IMAGE, STATE_WAIT_DRAIN, STATE_LOAD_IDLE,
        STATE_WORD_ISSUE, STATE_WORD_REPLY, STATE_FINISH_DRAIN, STATE_ERROR_DRAIN,
        STATE_IMAGE_READY);
    signal styp_state : t_state := STATE_NO_IMAGE;
    signal s_loading, s_image_valid, s_error : std_logic := '0';
    signal su27_bytes_loaded : unsigned(26 downto 0) := (others => '0');
begin
    assert (GINT_IMAGE_BYTES mod 2 = 0 and GINT_IMAGE_BYTES <= CINT_ROM_IMAGE_SIZE)
        report "Download size must be an even, bounded raw image" severity failure;
    o_loading <= s_loading;
    o_image_valid <= s_image_valid;
    o_error <= s_error;
    o_game_reset <= not s_image_valid or i_download or s_loading;
    ou27_bytes_loaded <= su27_bytes_loaded;
    ou2_loader_bytes <= "11";
    o_word_ready <= '1' when styp_state = STATE_LOAD_IDLE and i_download = '1' and
        su27_bytes_loaded < GINT_IMAGE_BYTES else '0';
    process(i_clk)
    begin
        if (rising_edge(i_clk)) then
            o_loader_request <= '0';
            o_done <= '0';
            assert (i_loader_response_valid /= '1' or styp_state = STATE_WORD_REPLY)
                report "Unexpected download write response" severity failure;
            case styp_state is
                when STATE_NO_IMAGE | STATE_IMAGE_READY =>
                    if (i_download = '1') then
                        s_image_valid <= '0';
                        s_error <= '0';
                        su27_bytes_loaded <= (others => '0');
                        styp_state <= STATE_WAIT_DRAIN;
                    end if;
                when STATE_WAIT_DRAIN =>
                    if (i_transport_idle = '1') then
                        s_loading <= '1';
                        styp_state <= STATE_LOAD_IDLE;
                    end if;
                when STATE_LOAD_IDLE =>
                    if (i_download = '0') then
                        if (su27_bytes_loaded = GINT_IMAGE_BYTES) then
                            styp_state <= STATE_FINISH_DRAIN;
                        else
                            s_error <= '1';
                            styp_state <= STATE_ERROR_DRAIN;
                        end if;
                    elsif (i_word_valid = '1' and o_word_ready = '1') then
                        if (iu27_word_byte_address = su27_bytes_loaded) then
                            ou27_loader_byte_address <= iu27_word_byte_address;
                            ou16_loader_data <= iu16_word_data;
                            styp_state <= STATE_WORD_ISSUE;
                        else
                            s_error <= '1';
                            styp_state <= STATE_ERROR_DRAIN;
                        end if;
                    end if;
                when STATE_WORD_ISSUE =>
                    if (i_loader_ready = '1') then
                        o_loader_request <= '1';
                        styp_state <= STATE_WORD_REPLY;
                    end if;
                when STATE_WORD_REPLY =>
                    if (i_loader_response_valid = '1') then
                        su27_bytes_loaded <= su27_bytes_loaded + 2;
                        styp_state <= STATE_LOAD_IDLE;
                    end if;
                when STATE_FINISH_DRAIN =>
                    if (i_transport_idle = '1') then
                        s_loading <= '0';
                        s_image_valid <= '1';
                        o_done <= '1';
                        styp_state <= STATE_IMAGE_READY;
                    end if;
                when STATE_ERROR_DRAIN =>
                    if (i_download = '0' and i_transport_idle = '1') then
                        s_loading <= '0';
                        styp_state <= STATE_NO_IMAGE;
                    end if;
            end case;
        end if;
    end process;
end architecture;

