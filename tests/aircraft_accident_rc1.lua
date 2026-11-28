local A=dofile("mods/luanttd_core/openttd/aircraft_accident.lua")
local function prohibited() error("unexpected random draw, terrain query or effect") end
local function plane()
  return {x=51,y=52,z=53,direction=3}
end
local p=plane()
A.begin(p,false)
local field={flags=2^8+2^29+1}
local words={3*65536+17,0xABC}
local draws=0
local effects={}
assert(A.pass(p,field,prohibited,function()
  draws=draws+1
  return assert(words[draws])
end,function(...) effects[#effects+1]={...} end))
local e=effects[1]
assert(p.crashed and p.stopped and p.crashed_counter==3 and p.direction==4 and draws==2)
assert(e[1]=="explosion_small" and e[2]==59 and e[3]==62 and e[4]==60)

p.crashed_counter=647
assert(A.pass(p,field,prohibited,prohibited,prohibited) and p.crashed_counter==650)
p.crashed_counter=9997
assert(not A.pass(p,field,prohibited,prohibited,prohibited))
assert(p.crashed_counter==10000 and field.flags==1)

local missing=plane()
missing.y=7
A.begin(missing,false)
local ground=function(x,z) assert(x==51 and z==53);return 5 end
for _,y in ipairs({6,6}) do
  assert(A.pass(missing,nil,ground,function() return 2048 end,prohibited) and missing.y==y)
end
assert(missing.crashed_counter==500)
local wet=plane()
A.begin(wet,true)
assert(A.pass(wet,nil,prohibited,prohibited,prohibited) and wet.crashed_counter==9003)

A.smoke(p,function(kind,x,y,z)
  assert(kind=="aircraft_smoke" and x==46 and y==54 and z==48)
end)
print("PASS RC1 aircraft crash controller: exact conditional random words, falling, rubble clearance and smoke offset")

local PoolView=dofile("mods/luanttd_core/openttd/industry_chimney_effect.lua")
local world={}
-- Physical future IDs tick on the creation frame; past IDs do not.
PoolView.add_timed(world,7,"aircraft_smoke",10,8,6,5)
PoolView.add_timed(world,4,"explosion_large",10,8,6,5)
PoolView.add_timed(world,8,"explosion_small",10,8,6,5)
local effects=world.stock_effect_vehicles
assert(effects[7].progress==13 and effects[7].remaining==71)
assert(effects[4].progress==0 and effects[4].remaining==64)
for _=1,47 do PoolView.step(world) end
assert(not effects[8] and effects[4].remaining==17 and effects[7].remaining==24)
assert(effects[7].y==20)
for _=1,24 do PoolView.step(world) end
assert(not next(effects))
print("PASS stock aircraft effect pool occupancy: smoke and both explosion lifetimes")
