#!/usr/bin/env python3
"""Read the numeric parts of a stock RC1 controlled subsidy run."""
from itertools import groupby
from pathlib import Path
import argparse

import openttd_save_inspect as inspect
from openttd_save_map import decode_map
from openttd_save_tables import decode_tables

inspect.VERSIONS = {368}
TOWN = ('xy', 'flags', 'grow_counter', 'growth_rate', 'time_until_rebuild',
        'fund_buildings_months', 'road_build_months', 'layout')


def read(path, include_map):
    blob = path.read_bytes()
    pool = decode_tables(blob, (b'CITY', b'DATE', b'PATS', b'SUBS'))
    version, _, w, h, data, _ = decode_map(blob)
    assert (version, w, h) == (368, 128, 128)
    date, config = pool[b'DATE'][0], pool[b'PATS'][0]
    assert config['difficulty.subsidy_duration'] == 1
    assert config['economy.town_growth_rate'] == 2
    assert sorted(pool[b'CITY']) == [0, 1, 2]

    def value(k, i):
        return int.from_bytes(data[k][i * 2:i * 2 + 2], 'big')

    roads, houses, runs = {}, {}, []
    for i, raw in enumerate(data[b'MAPT']):
        kind = raw >> 4
        m1, m5, m3 = (data[k][i] for k in (b'MAPO', b'MAP5', b'M3LO'))
        if kind == 2:
            assert m1 & 31 == 15
            roads[i] = (m5 & 15, value(b'MAP2', i) + 1)
        if kind == 3:
            complete = bool(m3 & 128)
            houses[i] = (value(b'MAP8', i) & 4095, int(complete),
                         3 if complete else m5 >> 3 & 3,
                         0 if complete else m5 & 7, m5 if complete else 0,
                         value(b'MAP2', i) + 1)
        if include_map:
            runs.append((data[b'MAPH'][i], kind, m1 if kind in (3, 4, 6) else 0,
                         m5 if kind in (0, 4, 6) else 0, m3 if kind == 4 else 0,
                         value(b'MAP2', i) if kind == 4 else 0))
    clock = [date['date'] - 712223, date['date_fract'], date['tick_counter'],
             date['cur_tileloop_tile'], date['random_state[0]'], date['random_state[1]'],
             date['trees_tick_counter']]
    out = {'towns': {i + 1: {k: row[k] for k in TOWN} for i, row in pool[b'CITY'].items()},
           'clock': clock, 'settings': [2, config['construction.extra_tree_placement']],
           'houses': houses, 'roads': roads, 'width': w, 'depth': h,
           'subsidies': {i: {k: row[k] for k in ('cargo_type', 'src', 'dst', 'remaining')}
                         for i, row in pool[b'SUBS'].items()},
           'duration': 1}
    if include_map:
        out['runs'] = [(len(list(same)), *key) for key, same in groupby(runs)]
    return out


def lua(data):
    if isinstance(data, dict):
        return '{' + ','.join(
            (f'[{k}]' if isinstance(k, int) else k) + '=' + lua(v)
            for k, v in data.items()) + '}'
    if isinstance(data, (list, tuple)):
        return '{' + ','.join(lua(v) for v in data) + '}'
    assert isinstance(data, int)
    return str(data)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('seed', type=int)
    p.add_argument('initial', type=Path)
    p.add_argument('later', type=Path)
    p.add_argument('out', type=Path)
    a = p.parse_args()
    initial, later = read(a.initial, True), read(a.later, False)
    assert initial['clock'][:3] == [1, 0, 1354]
    assert later['clock'][:3] == [90, 0, 7940]
    assert not initial['subsidies']
    # No saves/engine/art are published here; only stock numerical facts.
    header = f'''-- Vanilla OpenTTD 16.0-RC1, official Linux build SHA256:
-- 7fb8e95000d2ce25c9abfa89fa8b1ced44018ebbc9509492a89b5d036f6e18e8
-- Seed {a.seed}, three Temperate towns with vanilla six-day GameScript growth.
-- No transport companies, industries or initial forests. Normal subsidy duration.
-- January 2 and April 1 observations. Numeric data only.
'''
    runs = initial.pop('runs')
    text = header + 'return {initial=' + lua(initial) + ',runs={\n'
    for i in range(0, len(runs), 8):
        text += '  ' + ','.join(lua(row) for row in runs[i:i+8]) + ',\n'
    a.out.write_text(text + '},checks={[90]=' + lua(later) + '}}\n', encoding='utf-8')


if __name__ == '__main__':
    main()
