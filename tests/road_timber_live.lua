-- Published seed with actual independent vehicles and no injected cargo.
local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
s.corner_grid=dofile(root.."terrain_preview.lua")(S,Terrain,s)
dofile(root.."town_layout.lua")(S,s)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
s.road_timber=true
local W=dofile(root.."timber_world.lua")(S,Terrain,S.timber_rules())
local result=assert(W.default_1751(s))
local p=assert(W.scenario_1751(s))
local function build(kind,list)
  local yes,note=S.build(s,"Wood Route",kind,list);assert(yes,note)
end
local function route(points)
  local out={points[1]}
  for i=2,#points do
    local seg=S.line(points[i-1],points[i])
    for n=2,#seg do out[#out+1]=seg[n] end
  end
  return out
end
for _,waypoints in ipairs(p.road_waypoints) do build("road",route(waypoints)) end
local mill_goods=p.mill_goods_stop
build("road",route(p.mill_goods_spur))
for _,id in ipairs({p.forest_stop,p.sawmill_stop,mill_goods,p.goods_stop}) do
  local yes,why=S.build_truck_stop(s,"Wood Route",id);assert(yes,why)
end
build("road_depot",{p.depot})
local function station(id) return s.stations[s.tiles[id].station] end
local _,wood_accept=S.timber_stop_status(s,station(p.sawmill_stop),"wood")
local _,goods_accept=S.timber_stop_status(s,station(p.goods_stop),"goods")
assert(wood_accept.eighths==8 and goods_accept.eighths==9)
local function buy(engine,cargo,from,to)
  assert(not S.purchase(s,"Wood Route",engine,cargo,station(from).id))
  local id,err=S.purchase(s,"Wood Route",engine,cargo,nil,p.depot)
  assert(id,err)
  assert(S.add_order(s,"Wood Route",id,station(from).id,"full"))
  assert(S.add_order(s,"Wood Route",id,station(to).id,"unload"))
  local ok,why=S.toggle(s,"Wood Route",id);assert(ok,why)
  return id
end
local w=buy("wood_truck","wood",p.forest_stop,p.sawmill_stop)
local g=buy("goods_truck","goods",mill_goods,p.goods_stop)
assert(S.vehicles.wood_truck.stock_engine_id==144 and S.vehicles.wood_truck.capacity==20)
assert(S.vehicles.goods_truck.stock_engine_id==138 and S.vehicles.goods_truck.capacity==14)
local function clone(a,seen)
  if type(a)~="table" then return a end
  seen=seen or {}
  if seen[a] then return seen[a] end
  local o={};seen[a]=o
  for k,v in pairs(a) do o[k]=clone(v,seen) end
  return o
end
local wood_first,goods_first,reload=nil,nil,false
for i=1,190 do
  S.daily(s)
  local a,b=s.fleet[w],s.fleet[g]
  local mill=s.stock_timber_industries[result.sawmill]
  assert((mill.wood_received or 0)>=b.delivered)
  assert(mill.accepted.waiting==0 and not s.timber_transactions.open_station)
  local tick=s.passenger_house_clock.counter
  assert(tick==s.day*74 and a.stock_aged_tick==tick and b.stock_aged_tick==tick)
  for _,e in ipairs(S.road_loading_events(s)) do
    if e.kind=="fare" and e.vehicle==w then
      assert(e.data.units==20 and e.data.amount>0)
      wood_first=wood_first or e.data.tick
    end
    if e.kind=="fare" and e.vehicle==g then
      assert(e.data.units==14 and e.data.amount>0)
      goods_first=goods_first or e.data.tick
    end
  end
  if not reload and a.units>=10 and a.delivered==0 then
    assert(mill.wood_received==nil)
    s=clone(s);reload=true
  end
  if reload and wood_first and goods_first and b.delivered>=28 then break end
end
local a,b=s.fleet[w],s.fleet[g]
assert(reload and wood_first and goods_first and wood_first<goods_first)
assert(a.delivered>=20 and b.delivered==28 and a.expense>0 and b.expense>0)
assert((s.sites[station(p.goods_stop).site].received.goods or 0)==b.delivered)
assert(s.companies["Wood Route"].revenue==a.revenue+b.revenue)
assert(not (station(p.sawmill_stop).stock or {}).wood,"Stock wood leaked into the legacy prototype queue")
print(("PASS: physical wood/goods trucks, two processed goods loads and saved loaded forest run: wood %dt/$%d, goods %d crates/$%d"):
  format(a.delivered,a.revenue,b.delivered,b.revenue))
