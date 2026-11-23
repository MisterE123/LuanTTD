-- SPDX-License-Identifier: GPL-2.0-only
-- Exercise the actual adapter over the same stock controllers and cargo
-- clock as game init. Every arrival here uses a real berth or terminal.
local dir="mods/luanttd_core/"
local function M(p) return dofile(dir..p..".lua") end
local Sim=M("sim")
local T=M("openttd/terrain")
local O=M("openttd/rail_order_list")
local Adapter=M("water_air_orders")
local Track=M("openttd/rail_track")
local Water=M("openttd/ship_follow")(Track)
local Net=M("ship_network")(Sim,T,Water,M("openttd/ship_facilities")(Track,Water))
local Y=M("openttd/ship_yapf")(Track,Water,M("openttd/yapf_road_search"))
local Move=M("openttd/ship_motion")(Track,Water)
local Ship=M("ship_preview_run")(Net,Track,Water,Y,Move,M("openttd/ship_regions"),
  {width=Sim.W,height=Sim.H,x0=1,z0=1})
local Small=M("openttd/airport_small")
local Airport=M("airport_network")(Sim,T,Small)
local Roster=M("openttd/airport_roster")
local Air=M("airport_preview_run")(Sim,Airport,Small,M("openttd/airport_motion")(Small),T,M("openttd/slope"),Roster)
local Fleet=M("airport_owned")(Sim,Air,Roster,function()return true end)
local name="Alice"
local function id(x,z) return Sim.id(x,z) end
local function clone(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local c={}
  for k,v in pairs(t) do c[k]=clone(v) end
  return c
end
local function world(water)
  local s=Sim.new(1751)
  s.road_economy,s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply=true,true,true,true
  s.corner_grid=T.new(Sim.W,Sim.H,function(x) return water and x<9 and 1 or 0 end)
  for i in ipairs(s.tiles) do
    local x=Sim.xy(i)
    s.tiles[i]={terrain=water and x>=9 and "water" or "grass",variant=1}
  end
  return s
end
local function edit(a,id,op,idx,target)
  return a.edit(name,id,a.read(name,id).revision,op,idx,target)
end
local function air()
  local s=world(false)
  s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true
  Sim.mount_paid_air(s,Air)
  local fields={}
  for _,q in ipairs({{5,8},{21,17},{37,25}}) do
    local x,z=unpack(q)
    fields[#fields+1]=assert(Airport.build(s,name,id(x,z))).id
    for dx=4,6 do for dz=0,2 do
      local t=s.tiles[id(x+dx,z+dz)]
      t.house,t.parcel,t.variant=true,"shop",2
    end end
  end
  local a,b,c=unpack(fields)
  local u=assert(Fleet.commit(s,name,assert(Fleet.quote(s,name,a,215))))
  local p=assert(Fleet.start(s,name,a,b))
  local api=Adapter(s,Sim,O,nil,nil,nil,Air).air
  assert(not api.read("Other",u.serial))
  assert(not api.edit("Other",u.serial,0,"skip",1))
  assert(edit(api,u.serial,"append",nil,c))
  assert(not api.edit(name,u.serial,0,"remove",3))
  assert(edit(api,u.serial,"up",3))
  assert(api.read(name,u.serial).active==3 and api.read(name,u.serial).items[2].id==c)
  for _=1,200 do
    Sim.daily(s)
    if p.vehicle.state==Small.state.FLYING and p.target==b then break end
  end
  assert(p.vehicle.state==Small.state.FLYING and p.target==b and p.arrivals==0,p.failure or p.phase)
  local coords={p.vehicle.x,p.vehicle.z,p.vehicle.y}
  assert(edit(api,u.serial,"skip",2))
  assert(p.vehicle.x==coords[1] and p.vehicle.z==coords[2] and p.vehicle.y==coords[3] and p.target==b)
  s=clone(s);Sim.mount_paid_air(s,Air);p=Air.current(s,u.serial)
  api=Adapter(s,Sim,O,nil,nil,nil,Air).air
  assert(api.read(name,u.serial).active==2)
  local arrivals={}
  for _=1,500 do
    Sim.daily(s)
    assert(not p.failure,p.failure)
    for _,e in ipairs(Sim.air_paid_motion_events(s)) do
      if e.kind=="terminal" then arrivals[#arrivals+1]=e.airport end
    end
    if #arrivals>=3 then break end
  end
  assert(table.concat(arrivals,",")==table.concat({c,b,a},","),table.concat(arrivals,","))
  assert(Air.uses_airfield(p,c) and Sim.air_paid_status(s,u.serial).waiting[c])
  -- Interleave an order command on a real FTA approach tick, after
  -- landing has been reserved. RC1 may use the old terminal before it
  -- resumes the explicit list; it must not teleport or skip the edited row.
  local advance=Air.advance_paid
  local flags_before,late={}
  function Air.advance_paid(w,cb,observe,run)
    if not late and run.target==c and run.vehicle.state==Small.state.LANDING then
      flags_before=w.stock_small_airports[c].flags
      assert(flags_before~=0)
      local x,z,y=run.vehicle.x,run.vehicle.z,run.vehicle.y
      assert(edit(api,u.serial,"skip",3))
      assert(run.target==c and run.vehicle.x==x and run.vehicle.z==z and run.vehicle.y==y
        and w.stock_small_airports[c].flags==flags_before)
      late=true
    end
    return advance(w,cb,observe,run)
  end
  arrivals={}
  for _=1,400 do
    Sim.daily(s)
    assert(not p.failure,p.failure)
    for _,e in ipairs(Sim.air_paid_motion_events(s)) do
      if e.kind=="terminal" then arrivals[#arrivals+1]=e.airport end
    end
    if #arrivals>=2 then break end
  end
  Air.advance_paid=advance
  assert(late and arrivals[1]==c and arrivals[2]==b,table.concat(arrivals,","))
  print("PASS active aircraft order list: third airfield, cursor-preserving move, mid-flight skip, committed landing and saved terminal sequence")
end
local function ferry()
  local s=world(true)
  s.ship_paid_service=true
  Sim.mount_paid_ferry(s,Ship)
  local docks={}
  for _,z in ipairs({9,16,24}) do
    docks[#docks+1]=assert(Net.build(s,name,"dock",id(8,z))).id
    for dz=-2,2 do
      local t=s.tiles[id(6,z+dz)]
      t.house,t.parcel,t.variant=true,"shop",2
    end
  end
  local a,b,c=unpack(docks)
  local d=assert(Net.build(s,name,"depot",id(12,10),0)).id
  local buoy=assert(Net.build(s,name,"buoy",id(12,21)))
  local p=assert(Ship.start(s,name,d,a,b))
  p.owned=true
  local api=Adapter(s,Sim,O,Ship,nil,nil,nil).ship
  assert(api.read(name,"ferry") and not api.read("Other","ferry") and not api.read(name,"coal"))
  assert(not edit(api,"ferry","remove",1))
  assert(edit(api,"ferry","append",nil,c))
  assert(edit(api,"ferry","append",nil,"buoy:"..buoy.id))
  assert(edit(api,"ferry","up",4))
  local left
  for _=1,250 do
    Sim.daily(s)
    Sim.ferry_loading_events(s)
    assert(not p.failure,p.failure)
    if p.vehicle.loading and p.last_dock==a then break end
  end
  assert(p.vehicle.loading and p.last_dock==a,p.phase)
  local token=p.paid_clock
  -- A skip cleans up a genuine loading visit through the paid clock.
  assert(edit(api,"ferry","skip",3))
  assert(p.vehicle.loading and p.transport_skip_loading)
  s=clone(s);Sim.mount_paid_ferry(s,Ship);p=Ship.current(s)
  api=Adapter(s,Sim,O,Ship,nil,nil,nil).ship
  assert(api.read(name,"ferry").active==3)
  local arrivals={}
  for _=1,350 do
    Sim.daily(s)
    assert(not p.failure,p.failure)
    for _,e in ipairs(Sim.ferry_loading_events(s)) do
      if e.kind=="leave" and e.station==a and not left then left=e end
      if e.kind=="arrive" then arrivals[#arrivals+1]=e.station end
    end
    if #arrivals>=3 then break end
  end
  assert(left and left.vehicle==token)
  assert(table.concat(arrivals,",")==table.concat({c,a,b},","),table.concat(arrivals,","))
  assert(Ship.ordered_dock(p,c) and Sim.ferry_paid_status(s).waiting[c])
  assert(edit(api,"ferry","remove",3))
  assert(#api.read(name,"ferry").items==3)
  print("PASS active ferry order list: berth cancellation on skip, real buoy and third dock, saved cursor and paid loading cleanup")
end
air()
ferry()
