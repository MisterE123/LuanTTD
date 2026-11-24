local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim, Terrain, Slope=m("sim"),m("openttd/terrain"),m("openttd/slope")
local Bind=m("campaign_simulation_bindings")(Sim,root:sub(1,-2))
local Art=m("airport_metropolitan_art")
local Expansion=m("openttd/airport_expansion_data")
local Calendar=m("openttd/stock_engine_calendar")
local owner="Hub transport"
local manifest={}
for _,dir in ipairs({"models","textures"}) do
  local f=assert(io.popen("ls "..root..dir))
  for l in f:lines() do manifest[l]=true end
  f:close()
end
local function check(kind,other)
  local s=Sim.new(251)
  Sim.W,Sim.H=64,64
  s.tiles,s.sites={},{}
  s.corner_grid=Terrain.new(64,64,function()return 0 end)
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  s.air_owned_preview,s.air_fleet_preview=true,true
  for k=1,64*64 do s.tiles[k]={terrain="grass",h=0,variant=1} end
  for i,x in ipairs({10,44}) do
    local cell=Sim.id(x,33)
    s.sites[i]={id=i,tile=cell,kind="town",name="Hub town",population=240,service=0,stock={},produced={},received={}}
    s.tiles[cell].site=i
    for ax=x-3,x+9 do for z=13,17 do
      local t=s.tiles[Sim.id(ax,z)]
      t.house,t.source_house=true,{id=4,town=i,completed=true}
    end end
  end
  local d=Expansion[kind]
  Sim.mount_road_bus_market(s,Calendar,d.intro_year-1,false)
  local N,R,O,A=Bind.air(s,Slope,function()return true end,true,nil,nil,{[kind]=true,[other]=true})
  local C=m("campaign_transport_commands")(Sim,{world=s,air={network=N,run=R,owned=O,roster=A}})
  assert(not Art(d,kind).missing(manifest))
  local base=Sim.id(10,18)
  local spec={mode="air",operation="build",layout=kind,tile=base}
  local q,why=C.quote(owner,spec)
  assert(not q and why==string.upper(kind).."_AIRPORT_NOT_INTRODUCED")
  s.day=Calendar.date(math.max(d.intro_year,Expansion[other].intro_year)+1,1,1)-s.stock_bus_market.epoch
  Sim.company(s,owner).cash=250000
  q=assert(C.quote(owner,spec))
  assert(#q.tiles==d.W*d.H)
  local ok,e,a=C.commit(owner,q)
  assert(ok,e)
  local first=a.id
  local second=assert(N.build(s,owner,Sim.id(44,18),other)).id
  local h,i={},{}
  for n,hangar in ipairs(d.hangars) do h[n]=Sim.id(10+hangar[1],18+hangar[2]) end
  assert(not C.depot(owner,"air",first,base),"An airport block is not a depot")
  assert(not C.depot("Non-owner","air",first,h[1]))
  assert(not C.depot(owner,"air",second,h[1]),"A hangar cannot belong to an unrelated station")
  for n=1,2 do
    local list=assert(C.depot(owner,"air",first,h[n]))
    assert(#list.vehicles==0)
    for _,offer in ipairs(list.offers) do
      if offer.request.engine==215 then
        assert(offer.request.hangar_tile==h[n])
        local bought,err,result=C.commit(owner,assert(C.quote(owner,offer.request)))
        assert(bought,err); i[n]=result.id; break
      end
    end
    assert(i[n],"Expected the purchasable Sampson")
    list=assert(C.depot(owner,"air",first,h[n]))
    assert(#list.vehicles==1 and list.vehicles[1].id==i[n])
  end
  local r,e=C.start(owner,{mode="air",first=first,second=second,vehicle=i[2]})
  assert(r,e)
  local run=assert(R.current(s,i[2]))
  assert(not R.current(s,i[1]),"Starting a selected plane must not dispatch its neighbour")
  local hx,hz=N.layout(kind).hangar_geometry.spawn(1)
  assert(run.vehicle.x==10*16+hx and run.vehicle.z==18*16+hz)
  local visits={}
  for day=1,240 do
    Sim.daily(s)
    assert(run.phase~="blocked",run.failure)
    if run.last_airfield then visits[run.last_airfield]=true end
    local p=assert(Sim.air_paid_status(s,i[2]))
    if p.fare>0 and visits[first] and visits[second] then
      local st=s.stock_ship_commercial.service.stations[0xC000+first]
      assert(#st.tiles==d.W*d.H and st.tiles[1].kind=="airport_"..kind)
      print("PASS paid "..kind.." route: owned distinct hangars, exact second spawn, 2 arrivals, catchment and fare",day,p.fare)
      return
    end
  end
  error(kind.." paid route did not finish")
end
check("international","intercontinental")
check("intercontinental","international")
