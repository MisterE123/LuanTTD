#!/usr/bin/env python3
"""Record the pinned, single-town vanilla experiment from its RC1 saves."""
from pathlib import Path
from itertools import groupby
import sys
import openttd_save_inspect as inspect
inspect.VERSIONS={368}
from openttd_save_map import decode_map
from openttd_save_tables import decode_tables

if len(sys.argv)<4:
    raise SystemExit("usage: record_rc1_town_reference.py OUTPUT JAN2_SAVE LATER_SAVE [...]")
out=Path(sys.argv[1])
initial=Path(sys.argv[2])
matches=[initial,*map(Path,sys.argv[3:])]

def get(f):
    blob=f.read_bytes()
    s=decode_tables(blob,[b'CITY',b'DATE',b'PATS'])
    c,d,p=s[b'CITY'][0],s[b'DATE'][0],s[b'PATS'][0]
    version,_,w,h,g,_=decode_map(blob)
    assert (version,w,h)==(368,64,64)
    for col in ('MAPH','MAPT','MAPO','MAP5','M3LO'):
        assert len(g[col.encode()])==4096
    def field16(name,i):
        return int.from_bytes(g[name][i*2:i*2+2],'big')
    houses={}
    roads={}
    rows=[]
    for i,original in enumerate(g[b'MAPT']):
        kind=original>>4
        h,m1,m5,m3=(g[b'MAPH'][i],g[b'MAPO'][i],g[b'MAP5'][i],g[b'M3LO'][i])
        m2=0
        if kind==2:
            assert m1&31==15
            roads[i]=m5&15
        if kind==3:
            hid=field16(b'MAP8',i)&4095
            complete=bool(m3&128)
            houses[i]=(hid,int(complete),3 if complete else m5>>3&3,0 if complete else m5&7,m5 if complete else 0)
        if kind==4: m2=field16(b'MAP2',i)
        rows.append((h,kind,m1 if kind in (3,4,6) else 0,m5 if kind in (0,4,6) else 0,m3 if kind==4 else 0,m2))
    return c,d,p,rows,houses,roads

def lit(values):return '{'+','.join(map(str,values))+'}'
def hash_intro(): return """-- Vanilla OpenTTD 16.0-RC1, blob SHA-256
-- 7fb8e95000d2ce25c9abfa89fa8b1ced44018ebbc9509492a89b5d036f6e18e8.
-- Clean 64x64 Temperate, seed 1751, 1950, one original-layout town.
-- No industry, initial forest, transport companies, NewGRFs or subsidies.
-- Vanilla GameScript sets GSTown.SetGrowthRate(town, 6), then pauses
-- on measured dates/fractions. Pre-February samples from the identical
-- opening are unchanged by the subsidy toggle. These are numeric
-- observations only: no engine, artwork, third-party or player saves.
-- Tile, house and road ids here are all zero-based, as in OpenTTD.
return {
"""
c,d,p,rows,houses,roads=get(initial)
townfields=('xy','flags','grow_counter','growth_rate','time_until_rebuild','fund_buildings_months','road_build_months','layout')
assert d['date']==712224 and d['tick_counter']==1354 and d['date_fract']==0
assert p['economy.town_growth_rate']==2
samples=sorted((get(f) for f in matches),key=lambda x:x[1]['tick_counter'])
assert len({x[1]['tick_counter'] for x in samples})==len(samples), "Duplicate stock timestamps"
with out.open('w',encoding='utf-8',newline='\n') as o:
    o.write(hash_intro())
    o.write('  initial={town={'+','.join(f'{k}={c[k]}' for k in townfields)+'},\n')
    o.write('    settings='+lit([p['economy.town_growth_rate'],p['construction.extra_tree_placement'],d['trees_tick_counter']])+',\n')
    o.write('    runs={\n')
    grouped=[lit((len(list(group)),*key)) for key,group in groupby(rows)]
    for j in range(0,len(grouped),7):o.write('      '+','.join(grouped[j:j+7])+',\n')
    o.write('    },\n  },\n  stock={\n')
    for s,sd,_,sr,sh,rr in samples:
        tick=sd['tick_counter']
        o.write(f'    [{tick}]={{clock='+lit([sd['date']-712223,sd['date_fract'],sd['cur_tileloop_tile'],
              sd['random_state[0]'],sd['random_state[1]'],s['flags'],s['grow_counter'],s['growth_rate'],s['time_until_rebuild']])+',\n')
        o.write('      roads={'+','.join(f'[{k}]={v}' for k,v in rr.items())+'},\n')
        o.write('      houses={'+','.join(f'[{k}]={lit(v)}' for k,v in sh.items())+'},\n')
        if tick in (4410,4411):
            chosen=[2127,2128,2191,2192]
            o.write('      grade={'+','.join(f'[{k}]={lit((sr[k][0],sr[k][1],sr[k][3]))}' for k in chosen)+'},\n')
        o.write('    },\n')
    o.write('  },\n}\n')
