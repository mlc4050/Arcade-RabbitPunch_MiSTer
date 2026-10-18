# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Repeat the real load-frontend scenarios through the rotation DDR transport."""
import hashlib
import json
from coretools import core_root
from run_baselines import run_case
root = core_root()
template = root / 'sim/memory/load_frontend_tb.vhd'
text = template.read_text(encoding='utf-8').replace('load_frontend_tb', 'load_frontend_rotation_tb')
text = text.replace('        generic map (GINT_IMAGE_BYTES => 64)', '        generic map (\n            GINT_IMAGE_BYTES => 64\n        )')
marker = 'begin\n    s_clk <='
assert text.count(marker) == 1
text = text.replace(marker, '''    signal s_loader_busy, s_loader_valid, s_loader_read, s_loader_write : std_logic;
    signal su8_loader_burst, su8_loader_bytes : unsigned(7 downto 0);
    signal su29_loader_address : unsigned(28 downto 0);
    signal su64_loader_read_data, su64_loader_write_data : unsigned(63 downto 0);
    signal s_presentation_sync, s_presentation_write, s_presentation_empty : std_logic;
    signal s_presentation_valid, s_presentation_overflow : std_logic;
    signal sint_presentation_phase : natural range 0 to 31 := 0;
    signal sint_presentation_writes, sint_pending_takeovers : natural := 0;
begin
    s_clk <=''')
old="s_ddr_busy <= '1' when sint_cycles < 24 or sint_cycles mod 19 < 5 else '0';"
assert text.count(old) == 1
text = text.replace(old, "s_ddr_busy <= '1' when sint_cycles < 24 or sint_cycles mod 19 < 5 or\n        (s_host_download = '1' and s_start_ready = '0') else '0';")
# Only the frontend's formal map is translated. The existing backend continues
# observing the actual shared DDR bus, not a behavioral replacement of the mux.
for old, new in [('i_ddr_busy => s_ddr_busy', 'i_ddr_busy => s_loader_busy'),
                 ('ou8_ddr_burst_count => su8_burst', 'ou8_ddr_burst_count => su8_loader_burst'),
                 ('ou29_ddr_word_address => su29_address', 'ou29_ddr_word_address => su29_loader_address'),
                 ('iu64_ddr_read_data => su64_read_data', 'iu64_ddr_read_data => su64_loader_read_data'),
                 ('i_ddr_read_valid => s_ddr_valid', 'i_ddr_read_valid => s_loader_valid'),
                 ('o_ddr_read => s_ddr_read', 'o_ddr_read => s_loader_read'),
                 ('ou64_ddr_write_data => su64_write_data', 'ou64_ddr_write_data => su64_loader_write_data'),
                 ('ou8_ddr_byte_enables => su8_bytes', 'ou8_ddr_byte_enables => su8_loader_bytes'),
                 ('o_ddr_write => s_ddr_write', 'o_ddr_write => s_loader_write')]:
    assert text.count(old) == 1
    text = text.replace(old, new)
marker = '    backend : process(s_clk)'
assert text.count(marker) == 1
text = text.replace(marker, '''    s_presentation_sync <= '1' when sint_presentation_phase = 0 else '0';
    s_presentation_write <= '1' when sint_presentation_phase = 8 or sint_presentation_phase = 10 or
        sint_presentation_phase = 12 or sint_presentation_phase = 14 else '0';
    presentation_clock_enable : process(s_clk)
    begin
        if (rising_edge(s_clk)) then
            if (sint_presentation_phase = 31) then
                sint_presentation_phase <= 0;
            else
                sint_presentation_phase <= sint_presentation_phase + 1;
            end if;
        end if;
    end process;
    presentation : entity work.rabbitpunch_rotation_transport
        generic map (
            GINT_FRAME_PIXELS => 4
        )
        port map (
            i_clk => s_clk,
            i_initialize => s_initialize,
            i_enable => '1',
            i_game_ready => '1',
            i_loader_active => s_active,
            i_vertical_sync => s_presentation_sync,
            i_donor_enabled => '1',
            i_pixel_write => s_presentation_write,
            iu29_pixel_word_address => to_unsigned(16#04800000#, 29),
            iu64_pixel_data => x"1122334455667788",
            iu8_pixel_byte_enables => to_unsigned(16#0F#, 8),
            iu2_framebuffer_read_slot => to_unsigned(1, 2),
            o_framebuffer_valid => s_presentation_valid,
            o_discard_frame => open,
            o_queue_empty => s_presentation_empty,
            o_queue_overflow => s_presentation_overflow,
            iu8_loader_burst_count => su8_loader_burst,
            iu29_loader_word_address => su29_loader_address,
            iu64_loader_write_data => su64_loader_write_data,
            iu8_loader_byte_enables => su8_loader_bytes,
            i_loader_read => s_loader_read,
            i_loader_write => s_loader_write,
            o_loader_busy => s_loader_busy,
            o_loader_read_valid => s_loader_valid,
            ou64_loader_read_data => su64_loader_read_data,
            i_ddr_busy => s_ddr_busy,
            i_ddr_read_valid => s_ddr_valid,
            iu64_ddr_read_data => su64_read_data,
            ou8_ddr_burst_count => su8_burst,
            ou29_ddr_word_address => su29_address,
            ou64_ddr_write_data => su64_write_data,
            ou8_ddr_byte_enables => su8_bytes,
            o_ddr_read => s_ddr_read,
            o_ddr_write => s_ddr_write
        );
''' + marker)
text = text.replace('        variable v_pending, v_stalled : boolean := false;',
                    "        variable v_pending, v_stalled : boolean := false;\n        variable v_previous_owner : std_logic := '0';")
old='            assert (s_ddr_write = \'0\') report "Load-only DDR transport wrote staging memory" severity failure;'
assert text.count(old) == 1
text = text.replace(old, '''            assert (s_presentation_overflow = '0') report "Presentation queue overflowed during frontend test" severity failure;
            if (s_active = '1' and v_previous_owner = '0' and s_presentation_empty = '0') then
                sint_pending_takeovers <= sint_pending_takeovers + 1;
            end if;
            v_previous_owner := s_active;
            if (v_pending or s_word_valid = '1') then
                assert (s_active = '1') report "Loader ownership dropped before read/word drain" severity failure;
            end if;
            if (s_active = '1') then
                assert (s_ddr_write = '0' and s_presentation_valid = '0')
                    report "Presentation escaped while frontend owned DDR" severity failure;
            end if;
            if (s_ddr_write = '1') then
                assert (s_active = '0' and s_ddr_busy = '0' and su29_address = to_unsigned(16#04800000#, 29) and
                    su64_write_data = x"1122334455667788" and su8_bytes = x"0F")
                    report "Presentation packet corrupted or wrote loader staging memory" severity failure;
                sint_presentation_writes <= sint_presentation_writes + 1;
            end if;''')
marker='        report "LOAD_FRONTEND_PASS'
assert text.count(marker) == 1
text = text.replace(marker, '''        assert (sint_presentation_writes > 0 and sint_pending_takeovers > 0)
            report "Frontend test did not exercise presentation traffic and pending-queue takeover" severity failure;
        report "PRESENTATION_HANDOFF writes=" & integer'image(sint_presentation_writes) &
            " pending_takeovers=" & integer'image(sint_pending_takeovers);
''' + marker)
text = text.replace('LOAD_FRONTEND_PASS', 'LOAD_FRONTEND_ROTATION_PASS')
bench = root / 'debug/load_frontend_rotation_tb.vhd'
bench.write_text(text, encoding='utf-8')
sources = ['rtl/rabbitpunch_layout.vhd', 'rtl/memory/ddram/ddram_phy.sv', 'rtl/memory/ddram/rom_loader.sv',
           'rtl/rabbitpunch_ddr_copy.vhd', 'rtl/rabbitpunch_load_frontend.vhd',
           'rtl/rabbitpunch_ddr_write_queue.vhd', 'rtl/rabbitpunch_frame_publication.vhd',
           'rtl/rabbitpunch_rotation_transport.vhd', bench.relative_to(root).as_posix()]
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result = run_case('load_frontend_rotation', sources, 'load_frontend_rotation_tb', '1 ms', 'LOAD_FRONTEND_ROTATION_PASS')
assert hashes == {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
result.update(source_sha256=hashes, template_sha256=hashlib.sha256(template.read_bytes()).hexdigest(),
              log_sha256=hashlib.sha256((root / result['log']).read_bytes()).hexdigest(),
              ddr_reads=24, accepted_words=129,
              scope='Actual load frontend, unchanged native DDR PHY/copier, word-credit wrapper and VHDL rotation transport/queue/publication. Existing DDR/direct-byte/metadata/reset/overlap/recovery cases retain all expected words and addresses, now with concurrent synthetic presentation traffic, pending-queue takeover, no presentation write while loader owns DDR, and ownership retained through delayed reads and output-word backpressure. Synthetic DDR/word sink and presentation source; not HPS hardware, actual rotator traffic or physical timing.')
(root / 'docs/reference/load_frontend_rotation_checks.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
