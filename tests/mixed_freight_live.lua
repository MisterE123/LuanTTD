-- A clean common campaign-sized board with real road loads, processing,
-- shared Goods queues and the station ledger, not synthetic packet grants.
local root=core and core.get_modpath("luanttd_core").."/" or "mods/luanttd_core/"
local function m(name) return dofile(root..name..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local function tile(x,z) return Sim.id(x,z) end
local owner="Common Freight"
local function setup()
  local s=Sim.new(26027)
  Sim.W,Sim.H=64,64
  s.tiles,s.sites={},{}
  s.corner_grid=Terrain.new(64,64,function()return 0 end)
  for i=1,64*64 do s.tiles[i]={terrain="grass",h=0,variant=1} end
  local center=tile(53,28)
  s.sites[1]={id=1,tile=center,kind="town",name="Fallow",population=60,service=0,stock={},produced={},received={}}
  s.tiles[center].site=1
  for _,x in ipairs({55,56,57}) do
    local h=s.tiles[tile(x,29)]
    h.house,h.source_house=true,{id=0x0E,town=1,completed=true}
  end
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  s.stock_farm_frozen,s.stock_oil_frozen=true,true
  local Farm,rng,FRules=Sim.mount_farm_world(s,Terrain,true)
  local Oil=assert(Sim.mount_oil_world(s,Terrain,true))
  local ORules,TRules=Sim.oil_rules(),Sim.timber_rules()
  local Timber=m("timber_world")(Sim,Terrain,TRules)
  for k,v in pairs(Timber.facilities) do Sim.facilities[k]=v end
  local function place(W,R,kind,x,z)
    local opts={record=R.new(kind,0,x-1,z-1,{completed=true,original=true,
      generating_world=true,counter=4,economy_year=1950}),name=kind}
    local a,b=W.place_generated(s,kind,tile(x,z),opts,rng)
    return assert(a,b)
  end
  local farm=place(Farm,FRules,"farm",7,26)
  local fact=place(Farm,FRules,"factory",45,26)
  local well=place(Oil,ORules,"oil_well",15,26)
  local refinery=place(Oil,ORules,"oil_refinery",36,26)
  local forest=place(Timber,TRules,"forest",7,32)
  local sawmill=place(Timber,TRules,"sawmill",25,27)
  s.road_farm,s.road_oil,s.road_timber=true,true,true
  assert(Sim.road_farm_active(s) and Sim.road_oil_active(s) and Sim.road_timber_active(s))
  assert(Sim.build(s,owner,"road",Sim.line(tile(4,30),tile(59,30))))
  local depot=tile(5,31)
  assert(Sim.build(s,owner,"road_depot",{depot}))
  local stations={}
  for _,x in ipairs({8,16,27,37,46,56}) do
    assert(Sim.build(s,owner,"road",Sim.line(tile(x,30),tile(x,31))))
    assert(Sim.build_truck_stop(s,owner,tile(x,31)))
    stations[x]=s.tiles[tile(x,31)].station
  end
  local _,town=Sim.farm_stop_status(s,s.stations[stations[56]],"goods")
  assert(town.accepts and town.eighths>=8)
  local _,saw=Sim.timber_stop_status(s,s.stations[stations[27]],"wood")
  assert(saw.accepts and saw.near[1].id==sawmill.id)
  local _,mix=Sim.timber_stop_status(s,s.stations[stations[46]],"goods")
  assert(mix.sources[1]==fact.id)
  local function buy(engine,cargo,from,to)
    local id=assert(Sim.purchase(s,owner,engine,cargo,nil,depot))
    assert(Sim.add_order(s,owner,id,stations[from]))
    assert(Sim.add_order(s,owner,id,stations[to]))
    assert(Sim.toggle(s,owner,id))
    return id
  end
  local units={
    buy("grain_truck","grain",8,46),buy("livestock_van","livestock",8,46),
    buy("wood_truck","wood",8,27),buy("oil_tanker","oil",16,37),
    buy("goods_truck","goods",46,56),buy("goods_truck","goods",27,56),buy("goods_truck","goods",37,56),
  }
  return s,{units=units,stations=stations,industries={farm.id,fact.id,well.id,refinery.id,forest.id,sawmill.id}}
end
local function verify(s,p,initial)
  local yes=false
  for _=1,240 do
    Sim.daily(s)
    local count=0
    for i,id in ipairs(p.units) do if s.fleet[id].delivered>(initial and initial[i] or 0) then count=count+1 end end
    if count==#p.units and s.day>=31 then yes=true;break end
  end
  local sum,cash,final=0,0,{}
  for i,id in ipairs(p.units) do
    local v=s.fleet[id]
    final[i]=v.delivered
    sum,cash=sum+v.delivered,cash+v.revenue
    if not yes then io.stderr:write(v.name,": ",v.status," ",v.delivered," units, ",v.units," onboard\n") end
    assert(v.revenue>0,v.name.." never paid")
  end
  assert(yes,"all real goods chains must pay in one world")
  assert(s.companies[owner].paid_units==sum and s.companies[owner].revenue==cash,"receipt or cash counted twice")
  assert(s.stock_load_tick==s.passenger_house_clock.counter,"world used a second freight clock")
  assert(s.freight_transactions and not s.farm_transactions and not s.oil_transactions and not s.timber_transactions)
  for _,st in pairs(s.stations) do
    assert(st.stock_freight and not st.stock_farm and not st.stock_oil and not st.stock_timber,"station used split queues")
  end
  assert(s.freight_transactions.months[p.industries[2]] and s.freight_transactions.months[p.industries[4]]
    and s.freight_transactions.months[p.industries[6]],"mixed processor missed common calendar.")
  return final,sum,cash
end
local function remount(state)
  Sim.W,Sim.H=64,64
  assert(Sim.mount_farm_world(state,Terrain,true))
  assert(Sim.mount_oil_world(state,Terrain,true))
  local Timber=m("timber_world")(Sim,Terrain,Sim.timber_rules())
  for k,v in pairs(Timber.facilities) do Sim.facilities[k]=v end
end
if core then return {setup=setup,verify=verify,remount=remount} end
local function snapshot(x)
  if type(x)~="table" then return x end
  local t={} for k,v in pairs(x) do t[k]=snapshot(v) end return t
end
local state,details=setup()
local first=verify(state,details)
state=snapshot(state)
remount(state)
local _,units,cash=verify(state,details,first)
print(("PASS: seven real farm/wood/oil trucks across common month and reload, %d paid units / $%d without duplicate Goods authority"):format(units,cash))
