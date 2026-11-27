"""Record the numeric RC1 bus and passenger-train town experiment, not a save importer.

Args: opening.sav completed-tick.log output.lua February.sav ... June.sav
Source and checkpoint saves come from one uninterrupted vanilla 16.0-RC1 run.
:source: src/openttd.cpp StateGameLoop, after CallLandscapeTick.
"""
import sys
from pathlib import Path
import openttd_save_inspect as inspect
from openttd_save_map import snapshot, decode_map
from openttd_save_tables import decode_tables
from record_rc1_subsidy_reference import lua
from itertools import groupby
from record_rc1_town_reference import TOWN_FIELDS
inspect.VERSIONS={368}
source=Path(sys.argv[1])
data=source.read_bytes()
raw=decode_tables(data,(b'CITY',b'DATE',b'STNN',b'PLYR',b'PATS',b'ENGN',b'VEHS'))
game,opts,company,town=(raw[k][0] for k in (b'DATE',b'PATS',b'PLYR',b'CITY'))
assert game['tick_counter']==1502 and game['date_fract']==0 and len(raw[b'STNN'])==4
formats=[(0,'roadveh'),(1,'train'),(2,'train')]
parts=[(raw[b'VEHS'][i][n][0],raw[b'VEHS'][i][n][0]['common'][0]) for i,n in formats]
road,bus=parts[0]
assert bus['engine_type']==116 and all(n==0 for n in bus['cargo.action_counts'])
assert [item[1]['engine_type'] for item in parts]==[116,0,27]
version,_,w,h,grid,_=decode_map(data)
assert (version,w,h)==(368,64,64)
rails={2256,2257,2258,2259,2260,2261,2262}
board=snapshot(data)
houses,roads,stops,runs={},{},{},[]
def word(key,i):return int.from_bytes(grid[key][2*i:2*i+2],'big')
for i, typ in enumerate(grid[b'MAPT']):
 kind=typ>>4
 m1,m5,m3=(grid[k][i] for k in (b'MAPO',b'MAP5',b'M3LO'))
 if i in rails:
  assert kind in (1,5)
  # Re-establish rail via actual construction commands on the same corner grid.
  runs.append((grid[b'MAPH'][i],0,0,3,0,0));continue
 if kind in (2,5):
  tile=board['road_tiles'][str(i)]
  if tile['kind']=='road':
   roads[i]=[m5&15,word(b'MAP2',i),m1&31]
  elif tile['kind']=='drive_stop':
   stops[i]=[1,tile['road_bits'],tile['station_id'],tile['station_owner']]
  else:
   assert tile['kind']=='depot'
   stops[i]=[2,tile['road_bits'],tile['depot_id'],tile['depot_owner']]
 elif kind==3:
  completed=bool(m3&128)
  houses[i]=[word(b'MAP8',i)&4095,int(completed),3 if completed else m5>>3&3,
       0 if completed else m5&7,m5 if completed else 0,word(b'MAP2',i)]
 runs.append((grid[b'MAPH'][i],kind,m1 if kind in (3,4,6) else 0,
   m5 if kind in (0,4,6) else 0,m3 if kind==4 else 0,word(b'MAP2',i) if kind==4 else 0))
goods={}
for i,r in raw[b'STNN'].items():
 st=r['normal'][0];p=st['goods'][0]
 goods[i]=[st['time_since_load'],st['time_since_unload'],p['rating'],p['last_age'],p['last_speed'],
     p['time_since_pickup'],p['amount_fract'],p['status'],st['base'][0]['delete_ctr']]
model=raw[b'ENGN'][116]
rail_model=raw[b'ENGN'][0]
train_service={
 'interval':company['settings'][0]['settings.vehicle.servint_trains'],
 'percent':bool(company['settings'][0]['settings.vehicle.servint_ispercent']),
 'breakdowns':opts['difficulty.vehicle_breakdowns'],
 'no_servicing_if_no_breakdowns':bool(opts['order.no_servicing_if_no_breakdowns'])}
assert train_service['interval']==150 and train_service['breakdowns']==1
train_engine=dict(version=1,stock_id=0,climate_matches=True,startup_public=True,startup_date=712223,
  aging_stop_year=2050,**{k:rail_model[n] for k,n in dict(startup_age='age',phase1='duration_phase_1',
    phase2='duration_phase_2',phase3='duration_phase_3',intro_date='intro_date',reliability_decay='reliability_spd_dec',
    reliability_start='reliability_start',reliability_max='reliability_max',reliability_final='reliability_final').items()})
train_engine['expiry_age']=sum(train_engine[f'phase{i}'] for i in range(1,4))
opening=dict(
 train_service=train_service,train_engine=train_engine,
 clock=[game[k] for k in ('tick_counter','date','cur_tileloop_tile','random_state[0]','random_state[1]','trees_tick_counter')],
 town={k:town[k] for k in TOWN_FIELDS},
 supply={row['cargo']:[e[k] for e in row['history'][:2] for k in ('production','transported')] for row in town['supplied']},
 houses=houses,roads=roads,stops=stops,goods={k:v for k,v in goods.items() if k<2},train_goods={k:v for k,v in goods.items() if k>=2},
 settings=[opts[k] for k in ('economy.town_growth_rate','construction.extra_tree_placement')],
 cash=company['money'],loan=company['current_loan'],
 bus=[bus[k] for k in ('tile','x_pos','y_pos','direction','progress','cur_speed','subspeed')],
 motion=[road['state'],road['frame']],bus_tick=bus['tick_counter'],
 day_state=[company['money_fraction'],*[bus[k] for k in ('running_ticks','day_counter','cargo_age_counter','reliability','reliability_spd_dec',
   'age','max_age','date_of_last_service','date_of_last_service_newgrf','breakdown_chance','random_bits','waiting_triggers')]],
 engine={k:model[v] for k,v in dict(startup_age='age',intro_date='intro_date',phase1='duration_phase_1',
   phase2='duration_phase_2',phase3='duration_phase_3',reliability_start='reliability_start',reliability_max='reliability_max',
   reliability_final='reliability_final',reliability_decay='reliability_spd_dec').items()},
 service_options={'interval':company['settings'][0]['settings.vehicle.servint_roadveh'],
                  'percent':company['settings'][0]['settings.vehicle.servint_ispercent']},
 train=[{**{k:r[k] for k in ('tile','x_pos','y_pos','z_pos','direction','cur_speed','subspeed','progress','dest_tile',
          'age','cargo_age_counter','last_loading_station','cur_real_order_index','running_ticks','current_order_time',
          'tick_counter','reliability','reliability_spd_dec','max_age','breakdown_chance','breakdown_ctr','breakdown_delay','breakdowns_since_last_service','date_of_last_service','date_of_last_service_newgrf','random_bits','waiting_triggers')},
          'track':v['track'],'flags':v['gv_flags']} for v,r in parts[1:]],
 rails=sorted(rails),
)
c=company['cur_economy'][0]
opening['quarter']=[c['income'],c['expenses'],c['delivered_cargo'][0]]
opening['runs']=[(len(list(g)),*r) for r,g in groupby(runs)]
# Hash under 2^53 with the same code in the Lua fixture. Keep a digest
# of each independently checked every-tick subsystem, not raw traces.
def digest(h,*xs):
 for x in xs:
  h=(h*65599+int(x))%2147483647
 return h

out=Path(sys.argv[3])
ticks={}
for line in Path(sys.argv[2]).read_text().splitlines():
 words=line.split()
 tag=words[0] if words else ""
 if tag not in {"LTTD_RNG_WORDS","LTTD_TRAIN","LTTD_MULTI_BUS_FRAME","LTTD_FINAL_WAIT"}: continue
 t=int(words[1])
 if not 1502<t<=28290: continue
 row=ticks.setdefault(t,{})
 if tag=="LTTD_FINAL_WAIT":
  row.setdefault(tag,{})[int(words[2])]=words[3:6]
 else: row[tag]=words
assert sorted(ticks)==list(range(1503,28291))
periods=(3574,5646,7940,10160,12454,14674,16968,19262,21482,23776,25996,28290)
checked={}
actual_services=[]
state=[1,1,1,1]
for t,row in sorted(ticks.items()):
 train=row["LTTD_TRAIN"]
 state[0]=digest(state[0],t,*row["LTTD_RNG_WORDS"][2:])
 bus=row["LTTD_MULTI_BUS_FRAME"]
 fixed=bus[3:11] if int(bus[11])!=254 else [bus[3],-1,-1,-1,-1,bus[8],0,bus[10]]
 state[1]=digest(state[1],t,*fixed)
 if int(train[10])==5: actual_services.append(t)
 state[2]=digest(state[2],t,*(train[i] for i in (2,3,4,7,8,9,12,13,14,15,17,18,19)))
 for station,stats in sorted(row["LTTD_FINAL_WAIT"].items()):
  state[3]=digest(state[3],t,station,*stats)
 if t in periods: checked[t]=state.copy()
assert actual_services==[12922,24415]
checkpoints={}
for path in map(Path,sys.argv[4:]):
 blob=path.read_bytes()
 _,_,w,h,g,_=decode_map(blob)
 assert (w,h)==(64,64)
 r=decode_tables(blob,(b"DATE",b"CITY",b"PLYR"))
 tick=r[b"DATE"][0]["tick_counter"]
 tz,co=r[b"CITY"][0],r[b"PLYR"][0]
 th=1
 for i,tile in enumerate(g[b"MAPT"]):
  typ=tile>>4
  if typ==2 and g[b"MAP5"][i]<16:
   th=digest(th,i,typ,g[b"MAP5"][i]&15,int.from_bytes(g[b"MAP2"][2*i:2*i+2],"big"))
  elif typ==3:
   htype=int.from_bytes(g[b"MAP8"][2*i:2*i+2],"big")&4095
   done=bool(g[b"M3LO"][i]&128);m5=g[b"MAP5"][i]
   th=digest(th,i,typ,htype,int(done),3 if done else (m5>>3)&3,0 if done else m5&7,m5 if done else 0,g[b"MAPO"][i])
 history=[co["cur_economy"][0],*co["old_economy"][:4]]
 checkpoints[tick]={
  "town":[tz[k] for k in ("grow_counter","growth_rate","time_until_rebuild")],
  "supply":{c:[a[k] for a in ent["history"][:2] for k in ("production","transported")]
            for ent in tz["supplied"] if (c:=ent["cargo"]) in (0,2)},
  "map":th,
  "finance":[co["money"],co["money_fraction"],co["current_loan"]],
  "quarters":[[q["income"],q["expenses"],q["delivered_cargo"][0]] for q in history],
  "paid":sum(q["delivered_cargo"][0] for q in history)
 }
assert sorted(checkpoints)==list(periods)
header="""-- Numeric observations from OpenTTD 16.0-RC1 (07b339c0aaeb0a87be9490b2f1c3f17c6b00b837).
-- Stock 64x64 Temperate seed 1751. One Regal bus, one Kirby with a real coach,
-- two road stops and two separate rail platforms, one company and one town.
-- Exact original scenario has its stock subsidy duration set to zero.
-- Captured continuously from January 4 to the following January 1.
-- No stock save files, graphics, or text strings are redistributed.
"""
out.write_text(header+"return {start="+lua(opening)+",digest="+lua(checked)+",checks="+lua(checkpoints)+",services="+lua(actual_services)+"}\n")
