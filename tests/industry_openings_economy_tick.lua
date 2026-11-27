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
  s.sites[1]={kind="town",id=1,tile=t,name="North Reach",population=600,service=0,received={},produced={},stock={}}
  s.tiles[t].site=1
  Sim.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),year,true)
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
  s.stock_generated_profile={width=64,depth=64,industry_stats={},map_height_limit=30,town_settings={growth_setting=0}}
  s.day=30 -- January 31; this batch ends on February 1
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
  local ticks,old_day=0,s.day
  local seen={}
  local placed
  Sim.daily(s,nil,function()
    ticks=ticks+1
    if ticks<74 then
      assert(draws==0 and not s.stock_oil_industries,"Daily opening was early")
    elseif density~=0 then
      local rig=assert(s.stock_oil_industries[0x3000],"The source opening was too late")
      assert(rig==placed and rig.counter==0x8c9,"New rig did not run its first industry tick")
      assert(rig.produced[1].rate==7 and rig.produced[2].rate==1)
      assert(s.stock_industry_builder.month==year*12+2)
    end
  end,function(phase)
    seen[#seen+1]=phase
    local added=advance(phase)
    if added then
      placed=assert(s.stock_oil_industries[0x3000])
      assert(placed.counter==0x8ca and ticks==73)
    end
    return added
  end)
  assert(ticks==74 and s.day==old_day+1)
  assert(seen[1]=="day" and seen[2]=="month" and not seen[3])
  assert(draws==(density~=0 and 15 or 1))
  assert(ads==(density~=0 and 1 or 0))
  assert(not advance("day") and not advance("month"),"The saved date already ran")
end
state(1965,4)
state(1965,0)
print("PASS genuine source oil rig opens at the last economy tick and enters the same tick's industry pass")
