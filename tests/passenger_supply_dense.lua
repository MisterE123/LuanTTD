-- SPDX-License-Identifier: GPL-2.0-only
-- Release regression: do not replace real authored towns with one house.
local root="mods/bayline/"
local function mod(p) return dofile(root..p..".lua") end
local Sim=mod("sim")
local Terrain=mod("openttd/terrain")
local Small=mod("openttd/airport_small")
local Net=mod("airport_network")(Sim,Terrain,Small)
local Air=mod("airport_preview_run")(Sim,Net,Small,mod("openttd/airport_motion")(Small),
  Terrain,mod("openttd/slope"))
local function copy(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
local s=Sim.new(1751)
mod("town_layout")(Sim,s)
s.corner_grid=mod("terrain_preview")(Sim,Terrain,s)
s.air_paid_service=true;s.road_economy=true;s.road_stock_loading=true;s.road_stock_clock=true;s.road_stock_house_supply=true
Sim.mount_paid_air(s,Air)
local a=assert(Net.build(s,"A",Sim.id(7,16)))
local b=assert(Net.build(s,"A",Sim.id(30,16)))
assert(Air.start(s,"A",a.id,b.id))
local dense,max_tick=0,0
for day=1,120 do
  Sim.daily(s)
  local p=Air.current(s)
  assert(p.phase~="blocked",p.failure)
  local g=assert(s.stock_passenger_mux)
  local batch=g.receipt
  if batch and batch.tick>max_tick and #batch.events>1 then
    dense=dense+1
    local seen={}
    for i,e in ipairs(batch.events) do
      local key=e.x..":"..e.y
      assert(e.tick==batch.tick and not seen[key] and batch.by_tile[key]==i)
      seen[key]=true
    end
    assert(batch.next==#batch.events+1)
    max_tick=batch.tick
  end
  assert(g.pending==nil and s.passenger_house_clock.counter==s.stock_load_tick and p.vehicle.tick==s.day*74)
  if day==40 then
    s=copy(s);Sim.mount_paid_air(s,Air)
    assert(#Sim.air_loading_events(s)==0)
  end
end
assert(dense>1 and Air.current(s).arrivals>=2,
  "Regression needs multiple real houses on observed ticks and the real air controller")
print(("PASS: 120 default-town days across reload, %d observed multi-house receipts on one absolute stock tick each"):format(dense))
