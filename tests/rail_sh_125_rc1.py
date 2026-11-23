#!/usr/bin/env python3
"""Direct pinned RC1 compare: SH '125' power car, Mail Van and formation."""
from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
import re
import subprocess
p=ArgumentParser(description=__doc__);p.add_argument('engines',type=Path);p.add_argument('--lua',default='lua5.1')
a=p.parse_args()
blob=a.engines.read_bytes()
assert sha256(blob).hexdigest()=='d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74'
text=blob.decode()
checks=['local R=dofile("mods/luanttd_core/openttd/rail_roster.lua")']
for uid,meta_name,category in [(22,"SH '125' (Diesel)",'MT'),(28,'Mail Van','MW')]:
    label=re.escape(meta_name)
    row=re.search(rf'^\s*{category}\(([^\n]+)\), //\s*{uid} {label}\s*$',text,re.M)[1]
    veh=re.search(rf'^\s*RVI\(([^\n]+)\), //\s*{uid} {label}\s*$',text,re.M)[1]
    m=list(map(str.strip,row.split(',')))
    v=list(map(str.strip,veh.split(',')))
    assert m[4]=='CT_MAIL' and v[1]==('M' if uid==22 else 'W')
    fields=dict(zip(('base_intro','decay_speed','vehicle_life'),map(int,m[:3])))
    fields['model_life' if uid==22 else 'source_model_life']=int(m[3])
    fields.update(zip(('image_index','cost_factor','speed','power','tare','running_factor','capacity'),
                      (int(v[i]) for i in (0,2,3,4,5,6,8))))
    checks += [f'local q=assert(R.entry({uid}));assert(q.cargo=="mail")']
    checks += [f'assert(q.{k}=={n},{uid})' for k,n in fields.items()]
checks += ['''
local eq=assert(R.stats({22,27}))
assert(#eq.parts==3 and eq.parts[1].mate==3 and eq.parts[3].mate==1)
assert(eq.total_length==24 and eq.power==4500 and eq.weight==165 and eq.max_track_speed==200)
assert(R.display(22).capacity==8 and R.display(22).vehicles==2)
assert(R.stats({{stock_id=22,cargo_count=4,rear_cargo_count=4}}).weight==142)
''']
subprocess.run([a.lua,'-'],cwd=Path(__file__).resolve().parents[1],input='\n'.join(checks),text=True,check=True)
print("PASS RC1 #22, #28, reciprocal physical bodies, capacity and cargo mass")
