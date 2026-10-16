library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rabbitpunch_layout is
    -- Byte offsets in the index-0 ROM download stream and SDRAM image.
    constant ROM_MAINCPU_BASE : natural := 16#000000#;
    constant ROM_MAINCPU_SIZE : natural := 16#040000#;
    constant ROM_AUDIOCPU_BASE : natural := 16#040000#;
    constant ROM_AUDIOCPU_SIZE : natural := 16#010000#;
    constant ROM_TILES1_BASE : natural := 16#050000#;
    constant ROM_TILES1_SIZE : natural := 16#080000#;
    constant ROM_TILES2_BASE : natural := 16#0D0000#;
    constant ROM_TILES2_SIZE : natural := 16#080000#;
    constant ROM_SPRITES_BASE : natural := 16#150000#;
    constant ROM_SPRITES_SIZE : natural := 16#080000#;
    constant ROM_UPD_BASE : natural := 16#1D0000#;
    constant ROM_UPD_SIZE : natural := 16#040000#;
    constant ROM_IMAGE_SIZE : natural := 16#210000#;

    -- MiSTer joystick slot numbers; directions occupy bits 0..3.
    constant JOY_MISSILE : natural := 4;
    constant JOY_PUNCH : natural := 5;
    constant JOY_START : natural := 10;
    constant JOY_COIN : natural := 11;
    constant JOY_PAUSE : natural := 12;
    constant JOY_SERVICE : natural := 13;
    constant JOY_TEST : natural := 14;

    subtype target_t is std_logic_vector(4 downto 0);
    constant TARGET_NONE : target_t := "00000";
    constant TARGET_ROM : target_t := "00001";
    constant TARGET_BITMAP : target_t := "00010";
    constant TARGET_SPRITES : target_t := "00011";
    constant TARGET_TILES : target_t := "00100";
    constant TARGET_PALETTE : target_t := "00101";
    constant TARGET_SCROLL : target_t := "00110";
    constant TARGET_GGA_DATA : target_t := "00111";
    constant TARGET_GGA_SELECT : target_t := "01000";
    constant TARGET_VIDEO_FLAGS : target_t := "01001";
    constant TARGET_SOUND_COMMAND : target_t := "01010";
    constant TARGET_SPRITE_COUNT : target_t := "01011";
    constant TARGET_SPRITE_PRIORITY : target_t := "01100";
    constant TARGET_P1 : target_t := "01101";
    constant TARGET_P2 : target_t := "01110";
    constant TARGET_DSW : target_t := "01111";
    constant TARGET_SOUND_PENDING : target_t := "10000";
    constant TARGET_WORKRAM : target_t := "10001";
end package;
