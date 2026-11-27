#!/usr/bin/env python3
"""Extract same-execution stock RC1 checkpoints; never import a player save."""
import argparse
from pathlib import Path

from openttd_save_tables import decode_tables
from openttd_save_map import decode_map
from record_rc1_active_bus_motion import read
from record_rc1_active_bus_day import sample
from record_rc1_subsidy_reference import lua

def record(path):
    tick, observations = sample(path)
    blob = path.read_bytes()
    version, _, width, height, grid, _ = decode_map(blob)
    assert (version,width,height) == (368,64,64)
    raw = decode_tables(blob,(b'CITY',b'PLYR',b'VEHS'))
    town, comp=raw[b'CITY'][0],raw[b'PLYR'][0]
    bus=raw[b'VEHS'][0]['roadveh'][0]
    v=bus['common'][0]
    def tileword(key, i):
        return int.from_bytes(grid[key][2*i:2*i+2],"big")
    roads, houses={},{}
    for i,t in enumerate(grid[b'MAPT']):
        tiletype=t>>4
        m5=grid[b'MAP5'][i]
        if tiletype==2 and m5<16:
            roads[i]=[m5&15,tileword(b'MAP2',i),grid[b'MAPO'][i]&31]
        elif tiletype==3:
            complete=bool(grid[b'M3LO'][i]&128)
            houses[i]=[tileword(b'MAP8',i)&4095,tileword(b'MAP2',i),
                int(complete),3 if complete else (m5>>3)&3,
                0 if complete else m5&7,m5 if complete else 0,
                grid[b'MAPO'][i]]
    quarters=[[r['income'],r['expenses'],r['delivered_cargo'][0]]
              for r in [comp['cur_economy'][0],*comp['old_economy'][:4]]]
    town_passenger=next((r for r in town['accepted'] if r['cargo']==0),None)
    received=town['received'][1]
    observations.update(
        rating=town['ratings'][0],
        vehicle_service=[v[k] for k in ('date_of_last_service','date_of_last_service_newgrf',
                                         'breakdowns_since_last_service')],
        accepted=[e['accepted'] for e in town_passenger['history'][:2]] if town_passenger else [0,0],
        received=[received[k] for k in ('new_act','old_act','new_max','old_max')],
        quarters=quarters, lifetime=sum(r[2] for r in quarters),
        loans=[comp['current_loan'],comp['money_fraction']],
        roads=roads,houses=houses,flags=town['flags'],
        timers=[town['fund_buildings_months'],town['road_build_months']],
        bus=[*[v[k] for k in ('tile','x_pos','y_pos','z_pos','direction','progress','cur_speed','subspeed','tick_counter')],
             bus['state'],bus['frame']],
    )
    return tick,observations,grid[b"MAPH"]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('output',type=Path)
    p.add_argument('snapshots',nargs='+',type=Path)
    a=p.parse_args()
    assert len(a.snapshots)>=2
    first,*rest=[record(f) for f in a.snapshots]
    assert first[0]==1354
    initial,runs=read(a.snapshots[0],True)
    initial['quarter']=first[1]['quarters'][0]
    company=decode_tables(a.snapshots[0].read_bytes(),(b'PLYR',))[b'PLYR'][0]
    saved_options=company['settings'][0]
    initial['service_options']={
        'interval':saved_options['settings.vehicle.servint_roadveh'],
        'percent':saved_options['settings.vehicle.servint_ispercent'],
    }
    e=decode_tables(a.snapshots[0].read_bytes(),(b'ENGN',))[b'ENGN'][116]
    assert e['flags'] & 1 and e['company_avail'] & 1
    initial['engine']={
        'startup_age':e['age'],'intro_date':e['intro_date'],
        'phase1':e['duration_phase_1'],'phase2':e['duration_phase_2'],'phase3':e['duration_phase_3'],
        'reliability_start':e['reliability_start'],'reliability_max':e['reliability_max'],
        'reliability_final':e['reliability_final'],'reliability_decay':e['reliability_spd_dec'],
    }
    for _,state,heights in (first,*rest):
        state['grade_changes']={i:h for i,h in enumerate(heights) if h!=first[2][i]}
    header="""-- One continuous run of OpenTTD 16.0-RC1 07b339c0aaeb0a87be9490b2f1c3f17c6b00b837.
-- Ordinary 64x64 Temperate seed 1751, standard roads and houses. One company,
-- one MPS Regal, two drive-through stations, stock Reduced/Low defaults.
-- Observer saves at the end of complete simulation ticks from the single run.
-- No synthetic rewards, paused restarts, commercial assets, or full saves.
return {
  start="""
    text=header+lua(initial)[:-1]+',runs={\n'
    text+=''.join('    '+','.join(lua(r) for r in runs[n:n+7])+',\n' for n in range(0,len(runs),7))
    text+='  }},\n  checks={\n'
    text+=''.join(f'    [{tick}]={lua(state)},\n' for tick,state,_ in [first,*rest])
    text+='  },\n}\n'
    a.output.write_text(text,encoding='utf-8')

if __name__=='__main__':
    main()
