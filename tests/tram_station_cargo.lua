-- A native body outside the bus movement roster uses the *same* paid road
-- station/loading queues, gradual loading, pickup ages, and income rules.
local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local owner="Mixed station"
local T=dofile(root.."openttd/terrain.lua")
local Pack=dofile(root.."packed_campaign.lua")
local s=Sim.new(1751)
s.corner_grid=T.new(Sim.W,Sim.H)
for _,t in ipairs(s.tiles) do t.terrain,t.h,t.wood,t.house,t.site,t.build,t.owner="grass",0,nil,nil,nil,nil,nil end
s.road_stock_loading,s.road_stock_clock,s.road_economy=true,true,true
local a,b=Sim.id(8,10),Sim.id(21,10)
local function st(id,name,tile)
  return {id=id,name=name,owner=owner,tile=tile,mode="road",stop_type="bus",
    served={id},stock={passenger={}},last_service={}}
end
for i,pos in ipairs({a,b}) do
  s.sites[i]={id=i,kind="town",tile=pos,name="Town "..i,population=0,
    stock={},produced={},received={},service=0}
  local t=s.tiles[pos]
  t.build,t.road_bits,t.station,t.stop_axis,t.owner,t.site="road_station",10,i,10,owner,i
  t.tram={kind="drive_stop",dir=0,tramtype=1,tram_bits=10,tram_owner=owner,
    owner=owner,station=pos,shared_station=i,stop_type="bus"}
  s.stations[i]=st(i,"Stop "..i,pos)
end
local function frame(tile)
  local x,z=Sim.xy(tile)
  return {16*x+11,16*z+9,5,tile,1,72}
end
local c=Sim.company(s,owner)
local v={id=s.next_vehicle,owner=owner,engine="native_streetcar",cargo="passenger",
  stock_tram={capacity=24,slice=5,aging=185,speed=96},running=true,
  batches={},units=0,revenue=0,delivered=0,bought=s.day}
s.next_vehicle=s.next_vehicle+1
s.tram_pilot={carrier=v}
s.stations[1].stock.passenger={{units=24,source=1,origin_station=1,age=0}}
Sim.daily(s)
assert(not Sim.tram_passenger_arrive(s,v,{0,0,5,a,1,0},{},s.stock_load_tick))
local before=Sim.waiting_passengers(s,s.stations[1])
local l=assert(Sim.tram_passenger_arrive(s,v,frame(a),{},s.stock_load_tick))
assert(Sim.tram_passenger_arrive(s,v,frame(a),{},s.stock_load_tick)==l)
assert(not Sim.tram_passenger_arrive(s,v,frame(b),{},s.stock_load_tick))
assert(v.station==1 and #s.stations[1].loading_order==1)
assert(not Sim.tram_passenger_depart(s,v,s.stock_load_tick),"never settle an unfinished stock visit")
assert(Sim.waiting_passengers(s,s.stations[1])==before,
  "reserved passengers are visible until actually boarded")
s=assert(Pack.decode(Pack.encode(s)))
v=s.tram_pilot.carrier
assert(s.fleet[v.id]==nil and s.stations[1].loading_order[1]==v.id)
for _=1,16 do
  Sim.daily(s)
  if v.load_state.finished then break end
end
assert(v.units==24 and v.load_state.finished and Sim.waiting_passengers(s,s.stations[1])<before)
assert(Sim.tram_passenger_depart(s,v,s.stock_load_tick) and not v.station and not s.stations[1].loading_order[1])
assert(Sim.tram_passenger_arrive(s,v,frame(b),{no_load=true},s.stock_load_tick))
for _=1,16 do
  Sim.daily(s)
  if v.load_state.finished then break end
end
assert(Sim.tram_passenger_depart(s,v,s.stock_load_tick))
assert(v.delivered==24 and v.revenue>0 and s.companies[owner].paid_units==24)
assert(s.companies[owner].cash==c.cash+v.revenue and v.last_fare.amount==v.revenue)
print("PASS canonical shared road station loads the tram, persists reservations without a fake bus, and credits the exact stock passenger delivery")
