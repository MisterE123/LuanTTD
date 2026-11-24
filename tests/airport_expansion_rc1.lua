local dir="mods/luanttd_core/openttd/"
local data=dofile(dir.."airport_expansion_data.lua")
local Policy=dofile(dir.."airport_terminal_policy.lua")
local actual={
  metropolitan={1980,6,6,6,8,28,1,3,0,28},
  commuter={1983,5,4,4,4,20,1,3,2,38},
  international={1990,7,7,8,17,42,2,6,2,53},
  intercontinental={2002,9,11,10,25,72,2,8,2,77},
}
for k,want in pairs(actual) do
  local a=assert(data[k])
  local total=0
  for _,n in ipairs(a.terminal_groups) do total=total+n end
  local got={a.intro_year,a.W,a.H,a.catchment,a.noise,a.maintenance,#a.hangars,total,a.num_helipads,#a.points+1}
  assert(table.concat(got,",")==table.concat(want,","),k)
  for _,n in pairs(a.entries) do assert(a.points[n]) end
  for _,t in ipairs(a.tiles) do assert(t[1]<a.W and t[2]<a.H and t[3]>=0) end
end
local metro=Policy(data.metropolitan)
local a,v={flags=1},{pos=7,state=10}
assert(metro.terminal(a,v) and a.flags==3 and v.state==3)
a.flags,v.state=7,10
assert(not metro.helipad(a,v) and a.flags==7 and v.state==10)
local inter=Policy(data.intercontinental)
a.flags,v.pos,v.state=64,48,18
assert(inter.helipad(a,v) and a.flags==192 and v.state==9)
a.flags=192
assert(not inter.helipad(a,v))
-- Group row tests: check source row order, skip a reserved approach,
-- never cross a non-group transition, and fall back only at list end.
local kernel=Policy({terminal_groups={2,2},num_helipads=0,terminal_mapping=data.intercontinental.terminal_mapping,
  layout={
    [0]={{255,0,0},{255,2^14,1},{255,2^15,0},{1,0,0}},
    {{0,0,0},{255,2^14,1},{1,0,0},{255,2^15,0}},
    {{0,0,0},{255,2^14,1}},
  }})
a.flags,v.pos=2^14,0
assert(kernel.terminal(a,v) and v.state==2 and a.flags==2^14+1)
a.flags,v.pos,v.state=2^14,1,10
assert(not kernel.terminal(a,v) and v.state==10 and a.flags==2^14)
a.flags,v.pos=2^14,2
assert(kernel.terminal(a,v) and v.state==2 and a.flags==2^14+1)
print("PASS pinned RC1 four airfield data sets and stock terminal groups, fallback and helipad reservations")
