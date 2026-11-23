-- SPDX-License-Identifier: GPL-2.0-only
-- Two genuinely purchased Sampsons sharing a real Country FTA and the
-- same house/stock clock. Simulation only; native presentation separate.
local root="mods/luanttd_core/"
local function mod(p) return dofile(root..p..".lua") end
local Sim=mod("sim")
local Terrain=mod("openttd/terrain")
local Bind=mod("campaign_simulation_bindings")(Sim,root:sub(1,-2))
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local out={}
  for k,v in pairs(t) do out[k]=clone(v) end
  return out
end
assert(core==nil,"paid aircraft should not need engine views")
local s=Sim.new(1751)
local Net,Air,Owned=Bind.air(s,mod("openttd/slope"),function(id) return id==215 end)
s.air_owned_preview,s.air_fleet_preview=true,true
s.road_economy,s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply=true,true,true,true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
for _,tile in ipairs(s.tiles) do
  tile.terrain="grass";tile.wood=nil;tile.house=nil;tile.site=nil;tile.build=nil;tile.owner=nil
end
local field_ids={}
for _,at in ipairs({{5,8},{21,17},{37,25}}) do
  local x,z=at[1],at[2]
  local field=assert(Net.build(s,"A",Sim.id(x,z)))
  field_ids[#field_ids+1]=field.id
  for dx=4,6 do for dz=0,2 do
    local t=s.tiles[Sim.id(x+dx,z+dz)]
    t.house,t.parcel,t.variant=true,"shop",2
  end end
end
local A,H,B=unpack(field_ids)
local comp=Sim.company(s,"A")
assert(Sim.loan(s,"A",10000))
local u1=assert(Owned.commit(s,"A",assert(Owned.quote(s,"A",A,215))))
local u2=assert(Owned.commit(s,"A",assert(Owned.quote(s,"A",B,215))))
assert(u1.serial==1 and u2.serial==2)
local spent,bank=comp.expense,comp.cash
local advance=Air.advance_paid
local art_missing
local manifest_ready=Air.paid_art_ready
assert(manifest_ready({engine_id=215}) and not manifest_ready({engine_id=216}))
local last_world,last_actor=0,0
local steps={}
function Air.paid_art_ready(p) return p and p.paid_clock~=art_missing and manifest_ready(p) end
function Air.advance_paid(w,cb,observe,p)
  local tick=w.stock_ship_commercial.service.tick
  assert(tick~=last_world or last_actor<p.paid_clock,"Controller not in source vehicle ID order")
  last_world,last_actor=tick,p.paid_clock
  steps[p.paid_clock]=(steps[p.paid_clock] or 0)+1
  return advance(w,cb,observe,p)
end
Sim.mount_paid_air(s,Air)
-- Physical dispatch order does not assign commercial identity: purchase
-- #2 files first. The typed old singleton alias is migrated in place.
assert(Owned.start(s,"A",B,H))
Sim.daily(s)
local shared=s.stock_ship_commercial
local v2=assert(shared.service.vehicles[0xC002])
local before_age=v2.carrying_parts[1].cargo_age_counter
shared.air_serials=nil
assert(shared.air_serial==0xC002)
assert(Owned.start(s,"A",A,H))
Sim.daily(s)
assert(shared.air_serial==0xC001 and shared.air_serials[0xC001] and shared.air_serials[0xC002])
assert(shared.service.vehicles[0xC002]==v2 and v2.carrying_parts[1].cargo_age_counter~=before_age)
local fares,paid,arrivals,boarded={0,0},{0,0},{0,0},{0,0}
local function day()
  Sim.daily(s)
  local svc=s.stock_ship_commercial.service
  local tick=s.passenger_house_clock.counter
  assert(svc.tick==tick and svc.post_tick==tick and s.stock_load_tick==tick)
  assert(not s.stock_passenger_mux.pending)
  local by_terminal={}
  local previous
  for _,e in ipairs(Sim.air_paid_motion_events(s)) do
    assert(e.owner=="A" and e.paid_clock and e.world_tick<=tick)
    if previous and previous.world_tick==e.world_tick then assert(previous.paid_clock<=e.paid_clock) end
    previous=e
    if e.kind=="terminal" then
      by_terminal[e.world_tick..":"..e.paid_clock]=e
    end
  end
  for _,e in ipairs(Sim.air_loading_events(s)) do
    local id=e.paid_clock
    assert((id==1 or id==2) and e.vehicle==0xC000+id and e.owner=="A")
    if e.kind=="arrive" then
      local m=assert(by_terminal[e.tick..":"..id])
      assert(m.airport==e.station_local and m.cargo_tile==e.tile)
      local marker=s.tiles[e.tile].airfield
      assert(marker and marker.airport==e.station_local and e.tile~=s.stock_small_airports[e.station_local].origin)
      arrivals[id]=arrivals[id]+1
    elseif e.kind=="board" then
      assert(e.units<=(e.cargo=="mail" and 5 or 20));boarded[id]=boarded[id]+e.units
    elseif e.kind=="fare" then
      fares[id],paid[id]=fares[id]+e.amount,paid[id]+e.units
    end
  end
  local c=Sim.company(s,"A")
  assert(c.cash==bank+c.revenue-(c.expense-spent) and c.paid_units==c.units)
  assert(not Air.current(s,1).failure and not Air.current(s,2).failure)
  local v1,v2=svc.vehicles[0xC001],svc.vehicles[0xC002]
  for _,plane in ipairs({v1,v2}) do
    assert(plane.carrying_parts[1].units<=25 and plane.carrying_parts[2].units<=4)
  end
  assert(Air.current(s,1).finance and Air.current(s,2).finance)
  return v1,v2
end
-- Consume the first two reconciliation days' effects: status checks
-- below compare exact paid counter transitions after both actors exist.
Sim.air_paid_motion_events(s);Sim.air_loading_events(s)
local checkpoint
for _=1,500 do
  local v1,v2=day()
  local r=Air.current(s,1)
  if not checkpoint and r.phase=="terminal" and v1.load_state and v1.units>0 then
    local save={units=v1.units,ticks=v1.load_state.ticks,elapsed=v1.load_state.elapsed,
      reserved=v1.load_state.reserved_units,age=v1.carrying_parts[1].cargo_age_counter,x=r.vehicle.x,z=r.vehicle.z,
      terminal=v1.cargo_tile}
    s=clone(s)
    Sim.mount_paid_air(s,Air)
    assert(Sim.air_paid_status(s,1).onboard==save.units)
    assert(Sim.air_paid_status(s,2).paid_clock==2)
    assert(Sim.air_paid_status(s).paid_clock==1 and not Sim.air_paid_status(s,899))
    assert(not Sim.air_paid_pose(s,1,899))
    assert(Sim.air_paid_pose(s,1,1),"Saved actual terminal pose missing")
    art_missing=1
    local first,second=steps[1],steps[2]
    for j=1,3 do
      v1,v2=day()
      r=Air.current(s,1)
      local l=assert(v1.load_state)
      assert(v1.units==save.units and l.ticks==save.ticks and l.elapsed==save.elapsed and
        l.reserved_units==save.reserved and v1.carrying_parts[1].cargo_age_counter==save.age and v1.cargo_tile==save.terminal)
      assert(r.vehicle.x==save.x and r.vehicle.z==save.z and Sim.air_paid_status(s,1).paused)
      assert(not Sim.air_paid_status(s,2).paused)
    end
    assert(steps[1]==first and steps[2]==second+3*74)
    art_missing=nil
    checkpoint=save
  end
  if checkpoint and fares[1]>0 and fares[2]>0 and arrivals[1]>=2 and arrivals[2]>=2 then break end
end
assert(checkpoint and fares[1]>0 and fares[2]>0 and boarded[1]>0 and boarded[2]>0)
local company=Sim.company(s,"A")
local svc=s.stock_ship_commercial.service
assert(company.revenue==fares[1]+fares[2] and company.paid_units==paid[1]+paid[2])
assert(svc.companies.A.cash==company.revenue)
assert(svc.vehicles[0xC001].delivered==paid[1] and svc.vehicles[0xC002].delivered==paid[2])
assert(Sim.air_paid_status(s,1).fare==fares[1] and Sim.air_paid_status(s,2).fare==fares[2])
assert(Sim.air_paid_status(s,1).charged_running_ticks>0 and Sim.air_paid_status(s,2).charged_running_ticks>0)
assert(Sim.air_paid_status(s,1).waiting[H].waiting==Sim.air_paid_status(s,2).waiting[H].waiting)
for id=1,2 do
  local actual=Air.pose(Air.current(s,id))
  local shown=Sim.air_paid_pose(s,1,id)
  assert((not actual) == (not shown))
  if actual then assert(shown.x==actual.x and shown.y==actual.y and shown.z==actual.z) end
end
print(("PASS: two bought Sampsons, one FTA/clock, singleton row migration + reload/model pause, #%d %d passengers/$%d; #%d %d passengers/$%d"):
  format(1,paid[1],fares[1],2,paid[2],fares[2]))
