#!/usr/bin/env python3
"""Record numeric source vehicle/economy observations for the active-town experiment."""
import argparse
from pathlib import Path

import openttd_save_inspect as inspect
from openttd_save_tables import decode_tables
from record_rc1_subsidy_reference import lua

inspect.VERSIONS = {368}
FIELDS = ('reliability','breakdown_chance','breakdown_ctr','age')
DATE_1950 = 712223

def sample(path):
    a = decode_tables(path.read_bytes(), (b'CITY',b'DATE',b'VEHS',b'PATS',b'STNN',b'PLYR'))
    time, opts = a[b'DATE'][0], a[b'PATS'][0]
    assert sorted(a[b'VEHS']) == sorted(a[b'CITY']) == sorted(a[b'PLYR']) == [0]
    assert sorted(a[b'STNN']) == [0,1]
    assert opts['difficulty.vehicle_breakdowns'] == 1 and opts['difficulty.vehicle_costs'] == 0
    assert opts['vehicle.roadveh_acceleration_model'] == 1 and opts['economy.inflation'] == 0
    v = a[b'VEHS'][0]['roadveh'][0]['common'][0]
    assert v['engine_type'] == 116 and v['owner'] == 0
    town = a[b'CITY'][0]
    st = [row['normal'][0] for row in a[b'STNN'].values()]
    c = a[b'PLYR'][0]
    day = time['economy_date'] - DATE_1950
    d = dict(day=day, fraction=time['economy_date_fract'],
             rng=[time['random_state[0]'],time['random_state[1]']],
             town=[town[k] for k in ('grow_counter','growth_rate','time_until_rebuild')],
             service=[[r['time_since_load'],r['time_since_unload'],r['goods'][0]['rating']] for r in st],
             fault=[v[k] for k in FIELDS],cash=c['money'],
             triggers=[v['random_bits'],v['waiting_triggers']],
             delivered=c['cur_economy'][0]['delivered_cargo'][0],
             supply={row['cargo']:[entry[k] for entry in row['history'][:2]
                                  for k in ('production','transported')] for row in town['supplied']})
    return time['tick_counter'],d

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('output', type=Path)
    p.add_argument('samples', nargs='+', type=Path)
    a=p.parse_args()
    data = dict(sample(p) for p in a.samples)
    assert len(data)==len(a.samples)
    assert 1354 in data and 3574 in data and 5646 in data
    head = """-- Numeric observations from owned saves of official OpenTTD 16.0-RC1.
-- Same board, bus and stops as rc1-active-bus-motion.lua.
-- Economy tests key observations to the source game/date tick, NOT the
-- vehicle tick used in the physics test. Official dated checks include
-- January and the February/March boundaries, as far as each field matches.
return {
"""
    a.output.write_text(head+"".join(f'  [{tick}]={lua(row)},\n' for tick,row in sorted(data.items()))+'}\n')

if __name__=='__main__':
    main()
