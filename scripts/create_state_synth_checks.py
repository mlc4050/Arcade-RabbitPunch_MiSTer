# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 RabbitPunch contributors
"""Generate registered-boundary Quartus checks for state-capable VHDL."""
import argparse
import json
from coretools import core_root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', action='append', help='Generate only this named target; may repeat')
    args = parser.parse_args()
    root = core_root()
    targets = []
    for chip in ('jt51', 'jt7759'):
        source = root/'rtl/state/generated'/(chip+'_state_netlist.vhd')
        metadata = json.loads(source.with_suffix('.json').read_text())
        targets.append((chip+'_state', chip+'_state_check', source, metadata['entity'],
                        ['set_global_assignment -name VHDL_FILE ../../state/generated/'+chip+'_state_netlist.vhd']))
    t80_sources = ['set_global_assignment -name VHDL_FILE ../../state/vendor/meatsauce_t80/'+name+
                   '.vhd -library state_t80' for name in ('T80_Reg', 'T80_MCode', 'T80_ALU', 'T80')]
    t80_sources += ['set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_t80_capture.vhd']
    targets.append(('t80_capture', 't80_capture_check', root/'rtl/state/rabbitpunch_t80_capture.vhd',
                    'rabbitpunch_t80_capture', t80_sources))
    for block in ('state_header', 'state_slot_writer', 'state_slot_reader', 'state_image_buffer', 'state_snapshot'):
        assignments = ['set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_'+block+'.vhd']
        if block == 'state_header':
            assignments.insert(0, 'set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_state_crc.vhd')
        if block == 'state_snapshot':
            assignments[:0] = ['set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_state_crc.vhd',
                               'set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_state_header.vhd']
        targets.append((block, block+'_check', root/'rtl/state'/('rabbitpunch_'+block+'.vhd'),
                        'rabbitpunch_'+block, assignments))
    for block, dependencies in (
            ('state_image_validator', ('state_layout', 'state_crc', 'state_preflight', 'state_semantics')),
            ('state_apply', ('state_layout',)),
            ('state_banks', ('state_layout', 'state_memory', 'state_body')),
            ('state_publish', ('state_layout', 'state_image_words', 'state_slot_writer')),
            ('state_service', ('state_layout', 'state_crc', 'state_header', 'state_preflight',
                'state_semantics', 'state_image_buffer', 'state_snapshot', 'state_slot_reader',
                'state_image_validator', 'state_apply', 'state_image_words', 'state_slot_writer',
                'state_publish'))):
        assignments = ['set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_'+name+'.vhd'
                       for name in (*dependencies, block)]
        targets.append((block, block+'_check', root/'rtl/state'/('rabbitpunch_'+block+'.vhd'),
                        'rabbitpunch_'+block, assignments))
    main_sources = ['set_global_assignment -name SEARCH_PATH ../../..']
    main_sources += ['set_global_assignment -name SYSTEMVERILOG_FILE ../../state/vendor/konamigx/fx68k/'+name
                     for name in ('fx68k.sv', 'fx68kAlu.sv', 'uaddrPla.sv')]
    main_sources += ['set_global_assignment -name SYSTEMVERILOG_FILE ../../state/vendor/konamigx/gx_ss_m68k.sv']
    main_sources += ['set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_'+name+'.vhd'
                     for name in ('state_fx68k', 'm68k_capture', 'capture_stack_undo', 'capture_phase', 'state_maincpu')]
    targets.append(('state_maincpu', 'state_maincpu_check', root/'rtl/state/rabbitpunch_state_maincpu.vhd',
                    'rabbitpunch_state_maincpu', main_sources))
    board_sources = list(main_sources)
    for line in (root/'rtl/synth_check/board/board_check.qsf').read_text().splitlines():
        if '_FILE ../../' in line and '../../cpu/fx68k/' not in line:
            if line.endswith('../../rabbitpunch_board.vhd'):
                board_sources.append('set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_state_main_bus.vhd')
            board_sources.append(line)
    targets.append(('state_board', 'state_board_check', root/'rtl/rabbitpunch_board.vhd',
                    'rabbitpunch_board', board_sources))
    audio_sources = list(t80_sources)
    audio_sources += ['set_global_assignment -name VHDL_FILE ../../state/generated/'+chip+'_state_netlist.vhd'
                      for chip in ('jt51', 'jt7759')]
    audio_sources += ['set_global_assignment -name VHDL_FILE ../../rabbitpunch_'+name+'.vhd'
                      for name in ('z80', 'soundcpu', 'ram8', 'sound_bus', 'ym2151', 'upd7759_control', 'upd7759_playback', 'upd7759',
                                   'adpcm', 'sound_board', 'audio')]
    targets.append(('state_audio', 'state_audio_check', root/'rtl/rabbitpunch_audio.vhd',
                    'rabbitpunch_audio', audio_sources))
    scanout_sources = ['set_global_assignment -name VHDL_FILE ../../rabbitpunch_'+name+'.vhd'
                       for name in ('clock_enables', 'raster')]
    scanout_sources += ['set_global_assignment -name VHDL_FILE ../../state/rabbitpunch_state_game_timing.vhd']
    scanout_sources += ['set_global_assignment -name VHDL_FILE ../../rabbitpunch_'+name+'.vhd'
                       for name in ('scanline_scheduler', 'video_output', 'scanout')]
    targets.append(('state_scanout', 'state_scanout_check', root/'rtl/rabbitpunch_scanout.vhd',
                    'rabbitpunch_scanout', scanout_sources))
    if args.target:
        unknown = set(args.target) - {item[0] for item in targets}
        assert not unknown, 'Unknown state synthesis target: '+', '.join(sorted(unknown))
    for block, entity, source, implementation, source_assignments in targets:
        if args.target and block not in args.target:
            continue
        ports = source.read_text().split('    port (\n', 1)[1].split('\n    );', 1)[0]
        rows = []
        for declaration in ports.splitlines():
            name, definition = declaration.strip().rstrip(';').split(' : ', 1)
            direction, datatype = definition.split(' ', 1)
            datatype = datatype.split(' := ', 1)[0]
            rows.append((name, direction, datatype))
        lines = ['-- SPDX-License-Identifier: GPL-3.0-or-later',
                 '-- Copyright (C) 2026 RabbitPunch contributors',
                 '-- Generated by scripts/create_state_synth_checks.py.',
                 '-- Same-clock launch/capture registers; no paths are exempted.',
                 'library ieee;', 'use ieee.std_logic_1164.all;', 'use ieee.numeric_std.all;',
                 '', 'entity '+entity+' is', '    port (', ports, '    );', 'end entity;',
                 '', 'architecture evaluation of '+entity+' is']
        if block == 'state_board':
            lines.insert(lines.index('use ieee.numeric_std.all;') + 1, 'use work.rabbitpunch_layout.all;')
        boundaries = {}
        for name, _, datatype in rows:
            if name == 'i_clk':
                boundaries[name] = name
                continue
            prefix = 's_' if datatype == 'std_logic' else 'su'+name.split('_', 1)[0][2:]+'_'
            boundaries[name] = prefix+'boundary_'+name
            lines.append(f'    signal {boundaries[name]} : {datatype};')
        lines += ['begin', '    boundary : process(i_clk)', '    begin',
                  '        if (rising_edge(i_clk)) then']
        for name, direction, _ in rows:
            if name == 'i_clk':
                continue
            target, value = (boundaries[name], name) if direction == 'in' else (name, boundaries[name])
            lines.append(f'            {target} <= {value};')
        lines += ['        end if;', '    end process;', '    state_chip : entity work.'+implementation]
        parameters = {'state_header': ('GINT_BODY_BYTES', 107216),
                      'state_snapshot': ('GINT_BODY_BYTES', 107216),
                      'state_maincpu': ('GBOOL_EXTERNAL_PHASE_ENABLE', 'true'),
                      'state_board': ('GBOOL_STATE_CAPABLE', 'true'),
                      'state_audio': ('GBOOL_STATE_CAPABLE', 'true'),
                      'state_scanout': ('GBOOL_STATE_CAPABLE', 'true'),
                      'state_slot_writer': ('GINT_PAYLOAD_BYTES', 107280),
                      'state_slot_reader': ('GINT_PAYLOAD_BYTES', 107280),
                      'state_image_buffer': ('GINT_IMAGE_BYTES', 107280)}
        if block in parameters:
            name, value = parameters[block]
            assignments = [(name, value)]
            if block == 'state_board':
                assignments.append(('GBOOL_EXTERNAL_PHASE_ENABLE', 'true'))
            lines += ['        generic map (',
                      ',\n'.join(f'            {name} => {value}' for name, value in assignments), '        )']
        lines += ['        port map (',
                  ',\n'.join('            '+name+' => '+boundaries[name] for name, _, _ in rows),
                  '        );', 'end architecture;']
        out = root/'rtl/synth_check'/block
        out.mkdir(parents=True, exist_ok=True)
        (out/(entity+'.vhd')).write_text('\n'.join(lines)+'\n', encoding='utf-8', newline='\n')
        qsf = ['# SPDX-License-Identifier: GPL-3.0-or-later',
               '# Copyright (C) 2026 RabbitPunch contributors',
               'set_global_assignment -name FAMILY "Cyclone V"',
               'set_global_assignment -name DEVICE 5CSEBA6U23I7',
               'set_global_assignment -name TOP_LEVEL_ENTITY '+entity,
               'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
               'set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008',
               'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2',
               'set_global_assignment -name SEED 3',
               *source_assignments,
               'set_global_assignment -name VHDL_FILE '+entity+'.vhd',
               'set_global_assignment -name SDC_FILE '+entity+'.sdc',
               'set_location_assignment PIN_V11 -to i_clk']
        for name, _, datatype in rows:
            if name != 'i_clk':
                qsf.append('set_instance_assignment -name VIRTUAL_PIN ON -to '+name+
                           ('[*]' if datatype != 'std_logic' else ''))
        (out/(entity+'.qsf')).write_text('\n'.join(qsf)+'\n', encoding='utf-8', newline='\n')
        (out/(entity+'.qpf')).write_text('PROJECT_REVISION = "'+entity+'"\n', encoding='utf-8', newline='\n')
        sdc = (root/'rtl/synth_check/raster/raster_check.sdc').read_text()
        (out/(entity+'.sdc')).write_text(sdc, encoding='utf-8', newline='\n')
        print(out.as_posix(), flush=True)


if __name__ == '__main__':
    main()
