-- Ordinary worker ownership and exact source founder receipts. Each dated
-- Iron Ore and Steel family is exercised with a real separate truck.
local root="mods/luanttd_core/"
local function m(p) return dofile(root..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local mode=arg and arg[1] or "early"
local alternate=arg and arg[2]=="layout1"
local dated={early={1950,"iron_mps","steel_balogh",22,15},mid={1985,"iron_uhl","steel_uhl",25,18},
  late={2025,"iron_chippy","steel_kelling",27,20}}
local selected=assert(dated[mode])
local E=m("openttd/stock_engine_calendar")
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.sites,s.tiles={},{}
s.corner_grid=T.new(64,64,function() return 1 end)
for id=1,64^2 do s.tiles[id]={h=1,terrain="grass",variant=1} end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
s.road_farm,s.road_heavy,s.road_junction_clearance=true,true,true
local Farm,_,Rules=Sim.mount_farm_world(s,T,true)
local H=Sim.mount_heavy_world(s,T)
assert(Sim.mount_oil_world(s,T,true))
local at=Sim.id
local function produce(kind,x,z)
  return Rules.new(kind,0,x-1,z-1,{completed=true,counter=1,economy_year=1950,
    layout=alternate and kind=="steel_mill" and 1 or 0})
end
local ore=assert(H.place_generated(s,"iron_mine",at(10,12),{record=produce("iron_mine",10,12),name="Ore"}))
local mill=assert(H.place_generated(s,"steel_mill",at(26,12),{record=produce("steel_mill",26,12),name="Steel"}))
local factory=assert(Farm.place_generated(s,"factory",at(45,12),{record=produce("factory",45,12),name="Factory"},function()return 0 end))
assert(Sim.road_heavy_active(s))
local cap={road={start_year=selected[1],foster=true,breakdowns=0,service_interval=0,
  extra={[selected[2]]=true,[selected[3]]=true}},ferry={},air={},oil_tanker=true}
local boot,Cmd=m("campaign_authority_runtime"),m("campaign_authority_endpoint")
local runtime,A
local function mount()
  runtime=boot(Sim,root:sub(1,-2),s,cap)
  A=Cmd(Sim,runtime)
end
mount()
local owner="Heavy freight"
Sim.company(s,owner)
local function command(kind,data)
  data.kind,data.revision=kind,s.authority_revision or 0
  local r=A.command(owner,data);assert(r.ok,r.why);return r.value
end
local function build(req)
  local q=A.road_quote(owner,req)
  assert(q.ok,q.why)
  return command("road_commit",{request=req,quote=q.value})
end
local points={{8,16,50,16},{8,16,8,17},{8,17,14,17},{14,17,14,16},
 {23,16,23,17},{23,17,31,17},{31,17,31,16},{42,16,42,17},{42,17,50,17},{50,17,50,16}}
for _,r in ipairs(points) do assert(Sim.build(s,owner,"road",Sim.line(at(r[1],r[2]),at(r[3],r[4])))) end
local function stop(x)
  local pos=at(x,16);build({tool="truck_stop",first=pos});return s.tiles[pos].station
end
local a,b,c=stop(11),stop(27),stop(46)
local function inspect(tile)
  local q=A.truck_stop(owner,tile)
  assert(q.ok,q.why)
  local cargo={}
  for _,row in ipairs(q.value.cargo) do
    assert(not cargo[row.cargo],"A stop must not show duplicate cargo queues")
    cargo[row.cargo]=row
  end
  return cargo
end
assert(inspect(at(11,16)).iron_ore.collects)
local middle=inspect(at(27,16))
assert(middle.iron_ore.accepts and middle.steel.collects)
assert(inspect(at(46,16)).steel.accepts)
assert(not A.truck_stop(owner,at(11,12)).ok)
local dep=at(18,17)
build({tool="road_depot",first=dep})
local function vehicle(id,cargo,one,two)
  local panel=assert(runtime.transport.depot(owner,"road",dep))
  local req
  for _,q in ipairs(panel.offers) do if q.request.engine==id then req=q.request;break end end
  assert(req and req.cargo==cargo)
  local v=command("road_buy",req)
  command("road_order_add",{vehicle=v,station=one});command("road_order_add",{vehicle=v,station=two})
  command("road_toggle",{vehicle=v})
  return v
end
local ore_truck=vehicle(selected[2],"iron_ore",a,b)
local steel_truck=vehicle(selected[3],"steel",b,c)
assert(Sim.vehicle_capacity(s.fleet[ore_truck])==selected[4] and Sim.vehicle_capacity(s.fleet[steel_truck])==selected[5])
local function clone(t)
  if type(t)~="table" then return t end
  local y={};for k,v in pairs(t) do y[k]=clone(v) end;return y
end
local function paid()
  local i,j=s.fleet[ore_truck],s.fleet[steel_truck]
  for _=1,480 do
    runtime.day()
    if i.delivered>0 and j.delivered>0 and s.stock_heavy_industries[mill.id].received.iron_ore==i.delivered
      and s.stock_farm_industries[factory.id].received.steel==j.delivered then
      assert(i.revenue>0 and j.revenue>0 and i.expense>0 and j.expense>0)
      assert(s.stock_heavy_industries[mill.id].received.iron_ore==i.delivered,("mill accepted %s vs truck paid %s"):format(tostring(s.stock_heavy_industries[mill.id].received.iron_ore),i.delivered))
      assert(s.stock_farm_industries[factory.id].received.steel==j.delivered)
      assert(s.stock_load_tick==s.passenger_house_clock.counter)
      assert(i.delivered+j.delivered==s.companies[owner].paid_units)
      return i.delivered,j.delivered
    end
  end
  error(("ore %d/%s steel %d/%s"):format(i.delivered,i.status,j.delivered,j.status))
end
local ore_units,steel_units=paid()
s=clone(s);mount()
for _=1,180 do
  runtime.day()
  local a,b=s.fleet[ore_truck],s.fleet[steel_truck]
  if a.delivered>ore_units and b.delivered>steel_units then
    print(("PASS %s stock Iron Ore truck and Steel Truck ran ordinary profitable services and restored; %d ore / %d steel, exact one Factory Goods authority"):format(mode,a.delivered,b.delivered))
    return
  end
end
error("No paid resumption of both stock trucks")
