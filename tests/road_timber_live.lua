-- Published seed with actual independent vehicles and no injected cargo.
local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
local mode=arg and arg[1]
local later=mode=="craighead"
local stock={
  wood_foster={1985,145,22},
  wood_moreland={2025,146,24}
}
local wood_variant=stock[mode]
local wood_model=wood_variant and mode or "wood_truck"
local wood_capacity=wood_variant and wood_variant[3] or 20
local Calendar=dofile(root.."openttd/stock_engine_calendar.lua")
local function mount(w)
  if later then S.mount_road_bus_market(w,Calendar,1976,true,true)
  elseif wood_variant then S.mount_road_bus_market(w,Calendar,wood_variant[1],true,true,{[wood_model]=true}) end
end
mount(s)
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
local w=buy(wood_model,"wood",p.forest_stop,p.sawmill_stop)
local goods_model=later and "craighead_goods_truck" or "goods_truck"
local capacity=later and 16 or 14
if later then
  assert(S.vehicle_available(s,goods_model))
  local offer=S.vehicle_offer(s,goods_model)
  assert(offer.stock_engine_id==139 and offer.speed==176 and offer.capacity==16 and offer.cost==7109)
  local earlier=S.new(1751)
  earlier.road_timber=true
  S.mount_road_bus_market(earlier,Calendar,1950,true,true)
  assert(not S.vehicle_available(earlier,goods_model))
  local stub=dofile(root.."openttd/road_freight_catalog.lua")
  local row=assert(stub.row(goods_model))
  assert(row.life==15 and row.base_life==55 and row.intro_after_1920==19724 and
    row.climates==7 and row.running_factor==168 and row.weight_quarters==48 and row.power_tens_hp==22)
  assert(not S.purchase(s,"Wood Route",goods_model,"coal",nil,p.depot))
  assert(not S.purchase(s,"Wrong Owner",goods_model,"goods",nil,p.depot))
end
local g
if later then
  local form,closed
  core={formspec_escape=function(x) return x end,
    get_modpath=function() return "mods/luanttd_core" end,
    show_formspec=function(_,name,markup) assert(name=="luanttd_core:service");form=markup end,
    close_formspec=function(_,name) closed=name end}
  local player={get_player_name=function()return "Wood Route" end}
  local api={Sim=S,s=s,road_first=true,timber_tools=true,save=function()end}
  local U=dofile(root.."ui.lua")(api)
  U.service(player,"depot",p.depot)
  assert(form:find("depot_buy_craighead;Buy Craighead Goods Truck",1,true))
  local before=S.company(s,"Wood Route").cash
  g=s.next_vehicle
  assert(U.fields(player,"luanttd_core:service",{depot_buy_craighead=true}))
  assert(s.fleet[g].engine==goods_model and S.company(s,"Wood Route").cash==before-7109)
  assert(form:find("0 / 16 aboard",1,true))
  assert(U.fields(player,"luanttd_core:service",{depot_buy_craighead=true}))
  assert(s.next_vehicle==g+1 and not closed)
  assert(S.add_order(s,"Wood Route",g,station(mill_goods).id,"full"))
  assert(S.add_order(s,"Wood Route",g,station(p.goods_stop).id,"unload"))
  local ok,why=S.toggle(s,"Wood Route",g);assert(ok,why)
  core=nil
else g=buy(goods_model,"goods",mill_goods,p.goods_stop) end
assert(S.vehicles[wood_model].stock_engine_id==(wood_variant and wood_variant[2] or 144) and S.vehicle_capacity(s.fleet[w])==wood_capacity)
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
      assert(e.data.units==wood_capacity and e.data.amount>0)
      wood_first=wood_first or e.data.tick
    end
    if e.kind=="fare" and e.vehicle==g then
      assert(e.data.units==capacity and e.data.amount>0)
      goods_first=goods_first or e.data.tick
    end
  end
  if not reload and a.units>=math.floor(wood_capacity/2) and a.delivered==0 then
    assert(mill.wood_received==nil)
    s=clone(s);reload=true
    mount(s)
  end
  if reload and wood_first and goods_first and b.delivered>=capacity*2 then break end
end
local a,b=s.fleet[w],s.fleet[g]
assert(reload and wood_first and goods_first and wood_first<goods_first)
assert(a.delivered>=wood_capacity and b.delivered==capacity*2 and a.expense>0 and b.expense>0)
assert((s.sites[station(p.goods_stop).site].received.goods or 0)==b.delivered)
assert(s.companies["Wood Route"].revenue==a.revenue+b.revenue)
assert(not (station(p.sawmill_stop).stock or {}).wood,"Stock wood leaked into the legacy prototype queue")
print(("PASS: physical wood/goods trucks, two processed goods loads and saved loaded forest run: wood %dt/$%d, goods %d crates/$%d"):
  format(a.delivered,a.revenue,b.delivered,b.revenue))
