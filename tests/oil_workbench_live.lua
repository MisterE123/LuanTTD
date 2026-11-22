local mod="mods/bayline/"
local Sim=dofile(mod.."sim.lua")
local Terrain=dofile(mod.."openttd/terrain.lua")
local s=Sim.new(1751)
s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_oil,s.road_junction_clearance=true,true
dofile(mod.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(Sim,Terrain,s)
local W=assert(Sim.mount_oil_world(s,Terrain,true))
assert(W.default_1751(s))
assert(Sim.road_oil_active(s))
local paths={
  {{12,4},{16,4},{16,7},{15,7},{15,8},{12,8},{12,14},{14,14},{14,16},{18,16}},
  {{12,4},{12,5},{16,5}},{{15,8},{15,12},{12,12}},{{18,16},{18,15},{14,15}},
}
local at=Sim.id
local function tile(p) return assert(at(p[1],p[2])) end
for _,route in ipairs(paths) do for i=2,#route do
 assert(Sim.build(s,"A","road",Sim.line(tile(route[i-1]),tile(route[i]))))
end end
local stop={}
for i,xy in ipairs{{13,4},{16,16},{14,8}} do
 local t=tile(xy)
 assert(Sim.build_truck_stop(s,"A",t))
 stop[i]=s.tiles[t].station
end
local depot=at(11,12)
assert(Sim.build(s,"A","road_depot",{depot}))
local function status(i,cargo)
 return select(2,Sim.oil_stop_status(s,s.stations[stop[i]],cargo))
end
assert(not status(1,"oil").accepts and #status(1,"oil").sources==1)
assert(status(2,"oil").accepts and status(2,"oil").eighths>=8 and #status(2,"goods").sources==1)
assert(status(3,"goods").accepts and status(3,"goods").eighths==9)
local function buy(engine,cargo,a,b)
 local id=assert(Sim.purchase(s,"A",engine,cargo,nil,depot))
 assert(Sim.add_order(s,"A",id,stop[a]))
 assert(Sim.add_order(s,"A",id,stop[b]))
 assert(Sim.toggle(s,"A",id))
 return id
end
local a=buy("oil_tanker","oil",1,2)
local b=buy("goods_truck","goods",2,3)
assert(s.fleet[a].speed==nil and Sim.vehicle_capacity(s.fleet[a])==21)
local function cycle(w,a0,b0)
 local a,b=w.fleet[a],w.fleet[b]
 for _=1,400 do
  Sim.daily(w)
  if a.delivered>a0 and b.delivered>b0 then
    assert(a.revenue>0 and b.revenue>0 and a.expense>0 and b.expense>0)
    assert(a.delivered+b.delivered==w.companies.A.paid_units and a.revenue+b.revenue==w.companies.A.revenue)
    assert(w.stock_oil_industries[W.BASE+1].received.oil==a.delivered)
    assert(w.stock_load_tick==w.passenger_house_clock.counter)
    return a.delivered,b.delivered,a.revenue+b.revenue
  end
 end
 error(("%s: oil %d way=%s; Goods %d way=%s"):format(w.day,a.delivered,a.status,b.delivered,b.status))
end
local first,goods=cycle(s,0,0)
local function copy(t)
 if type(t)~="table" then return t end
 local out={};for k,v in pairs(t) do out[k]=copy(v) end
 return out
end
s=copy(s)
assert(Sim.mount_oil_world(s,Terrain,true))
local after,after_goods,paid=cycle(s,first,goods)
assert(after>first and after_goods>goods)
print(("PASS: exact native-ready oil clock, repeated after save: crude %d thousand L, Goods %d, $%d"):format(after,after_goods,paid))
