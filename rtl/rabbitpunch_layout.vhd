library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rabbitpunch_layout is
    -- Byte offsets in the index-0 ROM download stream and SDRAM image.
    constant CINT_ROM_MAINCPU_BASE : natural := 16#000000#;
    constant CINT_ROM_MAINCPU_SIZE : natural := 16#040000#;
    constant CINT_ROM_AUDIOCPU_BASE : natural := 16#040000#;
    constant CINT_ROM_AUDIOCPU_SIZE : natural := 16#010000#;
    constant CINT_ROM_TILES1_BASE : natural := 16#050000#;
    constant CINT_ROM_TILES1_SIZE : natural := 16#080000#;
    constant CINT_ROM_TILES2_BASE : natural := 16#0D0000#;
    constant CINT_ROM_TILES2_SIZE : natural := 16#080000#;
    constant CINT_ROM_SPRITES_BASE : natural := 16#150000#;
    constant CINT_ROM_SPRITES_SIZE : natural := 16#080000#;
    constant CINT_ROM_UPD_BASE : natural := 16#1D0000#;
    constant CINT_ROM_UPD_SIZE : natural := 16#040000#;
    constant CINT_ROM_IMAGE_SIZE : natural := 16#210000#;

    -- MiSTer joystick slot numbers; directions occupy bits 0..3.
    constant CINT_JOY_FIRE_PUNCH : natural := 4;
    constant CINT_JOY_MISSILE : natural := 5;
    constant CINT_JOY_START : natural := 10;
    constant CINT_JOY_COIN : natural := 11;
    constant CINT_JOY_PAUSE : natural := 12;
    constant CINT_JOY_SERVICE : natural := 13;
    constant CINT_JOY_TEST : natural := 14;

    subtype target_t is unsigned(4 downto 0);
    constant CU5_TARGET_NONE : target_t := "00000";
    constant CU5_TARGET_ROM : target_t := "00001";
    constant CU5_TARGET_BITMAP : target_t := "00010";
    constant CU5_TARGET_SPRITES : target_t := "00011";
    constant CU5_TARGET_TILES : target_t := "00100";
    constant CU5_TARGET_PALETTE : target_t := "00101";
    constant CU5_TARGET_SCROLL : target_t := "00110";
    constant CU5_TARGET_GGA_DATA : target_t := "00111";
    constant CU5_TARGET_GGA_SELECT : target_t := "01000";
    constant CU5_TARGET_VIDEO_FLAGS : target_t := "01001";
    constant CU5_TARGET_SOUND_COMMAND : target_t := "01010";
    constant CU5_TARGET_SPRITE_COUNT : target_t := "01011";
    constant CU5_TARGET_SPRITE_PRIORITY : target_t := "01100";
    constant CU5_TARGET_P1 : target_t := "01101";
    constant CU5_TARGET_P2 : target_t := "01110";
    constant CU5_TARGET_DSW : target_t := "01111";
    constant CU5_TARGET_SOUND_PENDING : target_t := "10000";
    constant CU5_TARGET_WORKRAM : target_t := "10001";
end package;
