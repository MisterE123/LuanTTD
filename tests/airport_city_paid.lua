-- Paid City Airport and a mixed Country–City route on the ordinary ledger.
local root="mods/luanttd_core/"
local function m(name)return dofile(root..name..".lua") end
local Sim,T,Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local Build=m("campaign_simulation_bindings")(Sim,root:sub(1,-2))
local function clone(t)
  if type(t)~="table" then return t end
  local n={};for k,v in pairs(t) do n[k]=clone(v) end
  return n
end
local owner="City Air"
local stock=tonumber(arg and arg[1]) or 226
local rows={[217]={90,10,43750,1248000},[220]={200,30,49218,2304000},
  [225]={95,10,43750,1296000},[226]={170,35,49218,2304000},[228]={300,50,82031,2428800}}
local selected=assert(rows[stock])
local function fixture(year,ready)
  local s=Sim.new(1751)
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  s.air_owned_preview,s.air_fleet_preview=true,true
  Sim.W,Sim.H=64,64
  s.tiles,s.sites={},{}
  s.corner_grid=T.new(64,64,function()return 0 end)
  for i=1,64*64 do s.tiles[i]={terrain="grass",h=0,variant=1} end
  for i,px in ipairs({9,47}) do
    local id=Sim.id(px,24)
    s.sites[i]={id=i,tile=id,kind="town",name="Airport town",population=200,service=0,stock={},produced={},received={}}
    s.tiles[id].site=i
    for x=px-2,px+7 do for z=14,17 do
      local h=s.tiles[Sim.id(x,z)]
      h.house,h.source_house=true,{id=4,town=i,completed=true}
    end end
  end
  Sim.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),year,false)
  local N,R,O,A=Build.air(s,Slope,function(id)return ready and (id==stock or id==226 or id==215) end,ready)
  return s,N,R,O,A
end
do
  local s,N=fixture(1954,true)
  local q,e=N.quote(s,owner,Sim.id(9,18),"city")
  assert(not q and e=="CITY_AIRPORT_NOT_INTRODUCED")
  local old,net,_,O=fixture(1960,true)
  local a=assert(net.build(old,owner,Sim.id(9,18),"city"))
  q,e=O.quote(old,owner,a.id,226)
  assert(not q and e=="AIRCRAFT_NOT_INTRODUCED")
  local unavailable,n=fixture(1975,false)
  q,e=n.quote(unavailable,owner,Sim.id(9,18),"city")
  assert(not q and e=="AIRPORT_TYPE_NOT_AVAILABLE")
end
do
  local state,N,R,O=fixture(1958,true)
  local small=assert(N.build(state,owner,Sim.id(9,18)))
  local city=assert(N.build(state,owner,Sim.id(47,18),"city"))
  local unit=assert(O.commit(state,owner,assert(O.quote(state,owner,small.id,215))))
  local plane=assert(O.start(state,owner,small.id,city.id))
  local visits={}
  for _=1,120 do
    Sim.daily(state)
    assert(plane.phase~="blocked",plane.failure)
    if plane.last_airfield then visits[plane.last_airfield]=true end
    if visits[small.id] and visits[city.id] and Sim.air_paid_status(state,unit.id).fare>0 then break end
  end
  assert(visits[small.id] and visits[city.id] and Sim.air_paid_status(state,unit.id).fare>0)
  print("PASS mixed Country–City service uses each airport's own FTA and pays a real fare")
end
local s,N,R,O,A=fixture(1975,true)
local reserve=stock==228 and 150000 or 125000
Sim.company(s,owner).cash=reserve
local C=m("campaign_transport_commands")(Sim,{world=s,air={network=N,run=R,owned=O,roster=A}})
local function build(x,z,layout)
  local tile=Sim.id(x,z)
  local q=assert(C.quote(owner,{mode="air",operation="build",tile=tile,layout=layout}))
  assert(q.request.layout==layout and #q.tiles==(layout=="city" and 36 or 12))
  assert(C.commit(owner,q))
  return N.airport_for(s,tile)
end
local a,b,c=build(9,18,"city"),build(47,18,"city"),build(22,15)
assert(a.price==21600 and b.price==21600 and c.price==7200)
local q=assert(C.quote(owner,{mode="air",operation="buy",depot=a.id,engine=stock}))
assert(q.price==selected[3] and C.commit(owner,q))
local unit=assert(O.status(s,a.id))
assert(unit.passengers==selected[1] and unit.mail==selected[2] and unit.annual_fp==selected[4])
assert(s.companies[owner].cash==reserve-a.price-b.price-c.price-q.price)
local d=assert(C.depot(owner,"air",a.id))
assert(#d.targets==2 and d.targets[1].label:find("City Airport",1,true))
local cannot,reason=O.start(s,owner,a.id,c.id)
assert(not cannot and reason=="LARGER_AIRFIELD_REQUIRED")
local run=assert(O.start(s,owner,a.id,b.id))
assert(run.engine_id==stock and run.vehicle.x==a.x+85)
local ok,e=R.route_stop(s,a,215)
assert(not ok and e=="CITY_AIRFIELD_SERVICE_ALREADY_ASSIGNED")
local route=m("water_air_orders")(s,Sim,m("openttd/rail_order_list"),nil,nil,nil,R).air
local v=assert(route.read(owner,unit.id))
assert(#v.targets==2 and not route.edit(owner,unit.id,v.revision,"append",nil,c.id))
local first_tick,first_fare
for _=1,425 do
  Sim.daily(s)
  local p=assert(Sim.air_paid_status(s,unit.id))
  assert(p.capacity==selected[1] and run.phase~="blocked",run.failure)
  local st=s.stock_ship_commercial.service.stations[0xC000+a.id]
  assert(#st.tiles==36 and st.tiles[1].kind=="airport_city")
  if p.fare>0 and not first_fare then
    first_fare,first_tick=p.fare,p.tick
    s=clone(s)
    N,R,O=Build.air(s,Slope,function(id)return id==stock end,true)
    run=assert(R.current(s,unit.id))
  elseif first_fare and p.fare>first_fare then
    assert(p.tick>first_tick and p.running_expense>0 and p.delivered==s.companies[owner].paid_units)
    print(("PASS bought stock airframe #%d: rebuilt City airports, %d-seat orders, reload and %d paid passengers/$%d"):format(stock,selected[1],p.delivered,p.fare))
    return
  end
end
error("The owned city aircraft did not earn two fares")
