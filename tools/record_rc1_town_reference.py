#!/usr/bin/env python3
"""Extract numeric evidence from the 64-square vanilla RC1 town experiments."""
from itertools import groupby
from pathlib import Path
import sys

import openttd_save_inspect as inspect
from openttd_save_map import decode_map
from openttd_save_tables import decode_tables

# This tool is deliberately narrower than an ordinary save importer.
inspect.VERSIONS = {368}
TOWN_FIELDS = ('xy', 'flags', 'grow_counter', 'growth_rate', 'time_until_rebuild',
               'fund_buildings_months', 'road_build_months', 'layout')
DATE_1950 = 712223


def sample(path):
    data = path.read_bytes()
    sections = decode_tables(data, [b'CITY', b'DATE', b'PATS'])
    towns = sections[b'CITY']
    date, settings = sections[b'DATE'][0], sections[b'PATS'][0]
    version, _, width, depth, grid, _ = decode_map(data)
    assert (version, width, depth) == (368, 64, 64)
    assert sorted(towns) == list(range(len(towns))) and 1 <= len(towns) <= 2
    assert settings['economy.town_growth_rate'] == 2
    for key in (b'MAPH', b'MAPT', b'MAPO', b'MAP5', b'M3LO'):
        assert len(grid[key]) == 4096

    def field16(key, index):
        return int.from_bytes(grid[key][index * 2:index * 2 + 2], 'big')

    houses, roads, rows = {}, {}, []
    for i, value in enumerate(grid[b'MAPT']):
        kind = value >> 4
        h, m1, m5, m3 = (grid[k][i] for k in (b'MAPH', b'MAPO', b'MAP5', b'M3LO'))
        if kind == 2:
            assert m1 & 31 == 15
            roads[i] = (m5 & 15, field16(b'MAP2', i))
        if kind == 3:
            house = field16(b'MAP8', i) & 4095
            completed = bool(m3 & 128)
            houses[i] = (house, int(completed), 3 if completed else m5 >> 3 & 3,
                         0 if completed else m5 & 7, m5 if completed else 0, field16(b'MAP2', i))
        rows.append((h, kind, m1 if kind in (3, 4, 6) else 0,
                     m5 if kind in (0, 4, 6) else 0, m3 if kind == 4 else 0,
                     field16(b'MAP2', i) if kind == 4 else 0))
    return towns, date, settings, rows, houses, roads


def array(values):
    return '{' + ','.join(map(str, values)) + '}'


def keyed(mapping):
    return '{' + ','.join(f'[{i}]={array(row)}' for i, row in mapping.items()) + '}'


def write(output, initial, paths):
    first = sample(initial)
    towns, date, settings, rows, _, _ = first
    assert (date['date'], date['date_fract'], date['tick_counter']) == (DATE_1950 + 1, 0, 1354)
    samples = sorted([first, *map(sample, paths)], key=lambda s: s[1]['tick_counter'])
    assert len({s[1]['tick_counter'] for s in samples}) == len(samples), 'Duplicate stock timestamps'
    assert all(len(s[0]) == len(towns) for s in samples)
    with output.open('w', encoding='utf-8', newline='\n') as out:
        out.write("""-- Vanilla OpenTTD 16.0-RC1 Linux generic AMD64 release SHA-256:
-- 7fb8e95000d2ce25c9abfa89fa8b1ced44018ebbc9509492a89b5d036f6e18e8.
-- Clean 64x64 Temperate, seed 1751, 1950, original town roads.
-- No industry, initial forest, companies, NewGRFs or effective subsidies.
-- Town growth uses the default economy setting. In the custom growth
-- sample, stock GameScript sets the six-day town growth interval.
-- Samples before February are unaffected by the monthly subsidy toggle.
-- Numeric observations only: no engine, artwork or player saves.
-- Tile indices, TownIDs and HouseIDs are all zero-based, as in OpenTTD.
return {
  initial={towns={
""")
        for town in towns.values():
            out.write('      {' + ','.join(f'{k}={town[k]}' for k in TOWN_FIELDS) + '},\n')
        values = [settings['economy.town_growth_rate'], settings['construction.extra_tree_placement'],
                  date['trees_tick_counter']]
        out.write('    },settings=' + array(values) + ',\n    runs={\n')
        runs = [array((len(list(group)), *row)) for row, group in groupby(rows)]
        for i in range(0, len(runs), 7):
            out.write('      ' + ','.join(runs[i:i + 7]) + ',\n')
        out.write('    },\n  },\n  stock={\n')
        for towns, date, _, rows, houses, roads in samples:
            tick = date['tick_counter']
            clock = [date['date'] - DATE_1950, date['date_fract'], date['cur_tileloop_tile'],
                     date['random_state[0]'], date['random_state[1]']]
            out.write(f'    [{tick}]={{clock={array(clock)},\n')
            out.write('      towns={' + ','.join(array(t[k] for k in TOWN_FIELDS[1:5])
                                               for t in towns.values()) + '},\n')
            out.write(f'      roads={keyed(roads)},\n      houses={keyed(houses)},\n')
            if len(towns) == 1 and tick in (4410, 4411):
                grade = {i: (rows[i][0], rows[i][1], rows[i][3]) for i in (2127, 2128, 2191, 2192)}
                out.write('      grade=' + keyed(grade) + ',\n')
            out.write('    },\n')
        out.write('  },\n}\n')


if __name__ == '__main__':
    if len(sys.argv) < 4:
        raise SystemExit('usage: record_rc1_town_reference.py OUTPUT JAN2_SAVE LATER_SAVE [...]')
    output, initial, *paths = map(Path, sys.argv[1:])
    write(output, initial, paths)
