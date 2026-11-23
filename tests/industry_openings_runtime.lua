-- SPDX-License-Identifier: GPL-2.0-only
local root="mods/luanttd_core"
local function m(name) return dofile(root.."/"..name..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Binding=m("industry_openings_runtime")
local Schedule=m("openttd/industry_build_scheduler")
local Draw=m("openttd/industry_gameplay_construction")
local Count={oil_rig=2,oil_refinery=1}
local function state(year,density)
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.tiles,s.sites={},{}
  s.corner_grid=T.new(64,64,function(_,z) return z<=28 and 1 or 0 end)
  for z=1,64 do for x=1,64 do
    s.tiles[Sim.id(x,z)]={h=z<=28 and 1 or 0,terrain=z<=28 and "grass" or "water",variant=1,
      water_class=z>28 and "sea" or nil}
  end end
  local t=Sim.id(11,11)
  s.sites[1]={kind="town",id=1,tile=t,name="North Reach",population=600,received={},produced={},stock={}}
  s.tiles[t].site=1
  Sim.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),year,true)
  local o=assert(Sim.mount_oil_world(s,T,true))
  local coal=m("openttd/coal_industry")()
  local w=m("openttd/industry_worldgen")(coal,nil,Sim.oil_rules())
  assert(w.probability({width=64,height=64},5)==0)
  s.stock_industry_builder=Schedule.reset(240,0)
  s.stock_industry_builder.wanted_inds=65536
  s.stock_industry_builder.daily_counter=65535
  local draws,ads=0,0
  local pick=Sim.id(12,year<1960 and 18 or 47)-1
  local seed_fields={0,0xe0000000,pick,0x91ed3aa5,0xa31c91fb,0,
      0,0x40000000,0xacc78cab,0x0491cdfa,0x34cd9123,0,1,2,0x9100a1b2}
  local advance=Binding(Sim,root,s,{oil=o},w,{
    terrain=T,density=density,coal=coal,
    random=function() draws=draws+1 return seed_fields[draws] or 0 end,
    advertise=function() ads=ads+1 end,
  })
  advance()
  return s,draws,ads
end
do
  local s,d,a=state(1965,4)
  local o=assert(s.stock_oil_industries[0x3000])
  assert(s.road_oil and o.kind=="oil_rig" and o.x==11 and o.z==46 and o.construction_type=="gameplay")
  assert(o.random==0x91fb and o.random_colour==0xb and o.counter==0x8ca)
  assert(o.produced[1].rate==7 and o.produced[2].rate==1) -- exact 2 production draws
  assert(o.tiles[1].random_bits==0xfa and o.tiles[6].random_bits==0xb2)
  assert(d==15 and a==1 and #s.changed==6)
  assert(s.stock_industry_builder.builddata[5].probability==6 and s.stock_industry_builder.builddata[5].max_wait==1)
  assert(not o.tiles[1].completed and not o.neutral_station)
  assert(s.stock_industry_builder.daily_counter==math.floor(4096/31)-1)
end
do
  local s,d,a=state(1959,4)
  local land=assert(s.stock_oil_industries[0x3000])
  assert(land.kind=="oil_refinery" and land.construction_type=="gameplay" and a==1 and d>10)
  local b=s.stock_industry_builder.builddata[5]
  assert(b.probability==0 and b.target_count==0)
end
do
  local s,d,a=state(1965,0)
  assert(not s.stock_oil_industries and a==0 and d==1)
  assert(s.stock_industry_builder.builddata[5].probability==0)
end
print("PASS authority-side RC1 gameplay opening: 1960 probability, exact six-oil-tile randomization, old/new stage separation and Funded Only")
