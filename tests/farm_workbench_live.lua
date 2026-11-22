local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local s=S.new(1751)
s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_farm,s.road_junction_clearance=true,true
dofile(mod.."town_layout.lua")(S,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(S,T,s)
local W,RNG=S.mount_farm_world(s,T,true)
assert(W,RNG)
local scene=assert(W.scenario_1751(s))
assert(W.default_1751(s,RNG))
assert(S.road_farm_active(s))
for _,group in ipairs(scene.road_waypoints) do
 for i=2,#group do assert(S.build(s,"A","road",S.line(group[i-1],group[i]))) end
end
for _,tile in ipairs({scene.farm_stop,scene.factory_stop,scene.goods_stop}) do
 assert(S.build_truck_stop(s,"A",tile))
end
assert(S.build(s,"A","road_depot",{scene.depot}))
local function station(tile) return s.tiles[tile].station end
local fa,fo,to=station(scene.farm_stop),station(scene.factory_stop),station(scene.goods_stop)
for _,cargo in ipairs({"grain","livestock"}) do
  local _,out=S.farm_stop_status(s,s.stations[fo],cargo)
  assert(out.accepts and out.eighths>=8)
end
local _,out=S.farm_stop_status(s,s.stations[to],"goods")
assert(out.accepts and out.eighths==9)
local function buy(engine,cargo,a,b)
 local id=assert(S.purchase(s,"A",engine,cargo,nil,scene.depot))
 assert(S.add_order(s,"A",id,a))
 assert(S.add_order(s,"A",id,b))
 assert(S.toggle(s,"A",id))
 return id
end
local first=buy("grain_truck","grain",fa,fo)
local second=buy("livestock_van","livestock",fa,fo)
local third=buy("goods_truck","goods",fo,to)
local fs,ps=s.stock_farm_industries[8192],s.stock_farm_industries[8193]
assert(fs and ps)
local function copy(t)
 if type(t)~="table" then return t end
 local out={};for k,v in pairs(t) do out[k]=copy(v) end
 return out
end
local function distinct_payments(world,grow)
 local prior={}
 for _,id in ipairs{first,second,third} do prior[id]=world.fleet[id].delivered end
 for _=1,400 do
  S.daily(world)
  local a,b,c=world.fleet[first],world.fleet[second],world.fleet[third]
  if a.delivered>prior[first] and b.delivered>prior[second] and c.delivered>prior[third] then
    assert(a.expense>0 and b.expense>0 and c.expense>0)
    assert(a.revenue>0 and b.revenue>0 and c.revenue>0)
    assert(a.delivered+b.delivered+c.delivered==world.companies.A.paid_units)
    assert(world.stock_load_tick==world.passenger_house_clock.counter)
    assert(a.last_fare.tick<=world.stock_load_tick and b.last_fare.tick<=world.stock_load_tick
      and c.last_fare.tick<=world.stock_load_tick)
    return a.delivered,b.delivered,c.delivered
  end
 end
 local a,b,c=world.fleet[first],world.fleet[second],world.fleet[third]
 error(("At %d: grain %d %s, livestock %d %s, goods %d %s"):format(world.day,a.delivered,a.status,b.delivered,b.status,c.delivered,c.status))
end
local a,b,c=distinct_payments(s)
s=copy(s)
assert(S.mount_farm_world(s,T,true))
local x,y,z=distinct_payments(s)
assert(x>a and y>b and z>c)
print(("PASS: actual common road world from farm to factory to town, repeated after save: grain %d, livestock %d, goods %d"):format(x,y,z))
