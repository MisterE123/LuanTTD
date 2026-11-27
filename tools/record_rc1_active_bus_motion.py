#!/usr/bin/env python3
"""Record one fixed, privately played stock RC1 bus experiment as numeric Lua."""
import argparse
from itertools import groupby
from pathlib import Path

import openttd_save_inspect as inspect
from openttd_save_map import decode_map, snapshot
from openttd_save_tables import decode_tables
from record_rc1_town_reference import TOWN_FIELDS
from record_rc1_subsidy_reference import lua

inspect.VERSIONS = {368}
HEADER = """-- Numeric observations from the official Linux generic OpenTTD 16.0-RC1 binary.
-- SHA256 7fb8e95000d2ce25c9abfa89fa8b1ced44018ebbc9509492a89b5d036f6e18e8.
-- This 64×64 ordinary Temperate seed 1751 has one town. The stock GameScript
-- uses the normal commands to take a loan, build two drive-through stops and
-- a depot on town roads, buy a Regal, add both stops, and start the vehicle.
-- At 1950-01-02, stock vehicle 0's own tick counter is 62. Later stock captures
-- are keyed by elapsed vehicle ticks, not by the enclosing save tick: a
-- script pause can take effect after the vehicle has advanced on that tick.
-- No save, engine or base assets are reproduced; these are gameplay values.
"""

def read(path, with_board):
    blob = path.read_bytes()
    tables = decode_tables(blob, (b'CITY', b'DATE', b'VEHS', b'PATS', b'STNN', b'PLYR'))
    date, config = tables[b'DATE'][0], tables[b'PATS'][0]
    assert sorted(tables[b'VEHS']) == sorted(tables[b'CITY']) == [0]
    assert sorted(tables[b'STNN']) == [0, 1]
    assert config['vehicle.roadveh_acceleration_model'] == 1
    assert config['vehicle.roadveh_slope_steepness'] == 7
    vehicle = tables[b'VEHS'][0]['roadveh'][0]
    raw = vehicle['common'][0]
    assert (raw['engine_type'], raw['owner'], raw['cargo_type'], raw['cargo_cap']) == (116, 0, 0, 31)
    assert raw['breakdown_ctr'] == vehicle['blocked_ctr'] == vehicle['overtaking'] == 0
    assert raw['cargo.action_counts'] == [0, 0, 0, 0]
    state, frame, inclination = vehicle['state'], vehicle['frame'], vehicle['gv_flags']
    pos = [raw[k] for k in ('tile','x_pos','y_pos','direction','progress','cur_speed','subspeed')]
    bus_tick = raw['tick_counter']
    if not with_board:
        assert 1354 < date['tick_counter'] < 1580
        return bus_tick, [*pos, state, frame, -1 if inclination & 2 else inclination & 1]

    version, _, w, h, grid, _ = decode_map(blob)
    assert (version, w, h, date['tick_counter'], date['date_fract']) == (368, 64, 64, 1354, 0)
    board = snapshot(blob)
    def field(key, i):
        return int.from_bytes(grid[key][2*i:2*i+2], 'big')
    houses, roads, stops, runs = {}, {}, {}, []
    for i, typ in enumerate(grid[b'MAPT']):
        kind = typ >> 4
        m1, m5, m3 = (grid[k][i] for k in (b'MAPO', b'MAP5', b'M3LO'))
        if kind in (2, 5):
            tile = board['road_tiles'][str(i)]
            if tile['kind'] == 'road':
                roads[i] = [m5 & 15, field(b'MAP2', i), m1 & 31]
            elif tile['kind'] == 'drive_stop':
                assert tile['stop_type'] == 'bus'
                stops[i] = [1, tile['road_bits'], tile['station_id'], tile['station_owner']]
            else:
                assert tile['kind'] == 'depot'
                stops[i] = [2, tile['road_bits'], tile['depot_id'], tile['depot_owner']]
        elif kind == 3:
            complete = bool(m3 & 128)
            houses[i] = [field(b'MAP8', i) & 4095, int(complete), 3 if complete else (m5 >> 3) & 3,
                         0 if complete else m5 & 7, m5 if complete else 0, field(b'MAP2', i)]
        runs.append((grid[b'MAPH'][i], kind, m1 if kind in (3, 4, 6) else 0,
                     m5 if kind in (0, 4, 6) else 0, m3 if kind == 4 else 0,
                     field(b'MAP2', i) if kind == 4 else 0))
    assert sorted(stops) == [2122,2191,2382]
    runs = [(len(list(group)), *row) for row, group in groupby(runs)]
    town = tables[b'CITY'][0]
    goods = {}
    for i, item in tables[b'STNN'].items():
        st = item['normal'][0]
        g = st['goods'][0]
        goods[i] = [st['time_since_load'], st['time_since_unload'], g['rating'], g['last_age'],
                    g['last_speed'], g['time_since_pickup'], g['amount_fract'], g['status'],
                    st['base'][0]['delete_ctr']]
    opening = dict(clock=[date[k] for k in
                       ('tick_counter','date','cur_tileloop_tile','random_state[0]','random_state[1]','trees_tick_counter')],
        town={k:town[k] for k in TOWN_FIELDS},
        supply={row['cargo']:[entry[k] for entry in row['history'][:2] for k in ('production','transported')]
                for row in town['supplied']},
        houses=houses,roads=roads,stops=stops,goods=goods,cash=tables[b'PLYR'][0]['money'],
        settings=[config[k] for k in ('economy.town_growth_rate','construction.extra_tree_placement')],
        bus=pos,motion=[state,frame],bus_tick=bus_tick,
        day_state=[tables[b'PLYR'][0]['money_fraction'],*[raw[k] for k in
                   ('running_ticks','day_counter','cargo_age_counter','reliability','reliability_spd_dec',
                    'age','max_age','date_of_last_service','date_of_last_service_newgrf','breakdown_chance')]])
    return opening,runs

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('output', type=Path)
    p.add_argument('opening', type=Path)
    p.add_argument('samples', nargs='+', type=Path)
    a = p.parse_args()
    expected, runs = read(a.opening, True)
    assert expected['bus_tick'] == 62
    samples = {}
    for path in a.samples:
        tick,row = read(path, False)
        elapsed = (tick - expected['bus_tick']) % 256
        assert 0 < elapsed < 230 and samples.setdefault(elapsed,row) == row
    rows = ['    ' + ','.join(lua(row) for row in runs[n:n+7]) + ','
            for n in range(0,len(runs),7)]
    text = HEADER + 'return {\n  start=' + lua(expected)[:-1] + ',runs={\n'
    text += '\n'.join(rows) + '\n  }},\n  samples={\n'
    text += ''.join(f'    [{k}]={lua(v)},\n' for k,v in sorted(samples.items())) + '  },\n}\n'
    a.output.write_text(text, encoding='utf-8')

if __name__ == '__main__':
    main()
