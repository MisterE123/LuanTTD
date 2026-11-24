local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
dofile(root.."town_layout.lua")(S,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(S,T,s)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_mail,s.road_stock_loading=true,true,true,true,true
local name="Shared Road Service"
local p=S.company(s,name)
local function id(x,z) return S.id(x,z) end
for _,leg in ipairs{{9,12,20,12},{20,12,20,14},{20,14,9,14},{9,14,9,12}} do
  assert(S.build(s,name,"road",S.line(id(leg[1],leg[2]),id(leg[3],leg[4]))))
end
local depot=id(14,13)
local C=dofile(root.."campaign_road_construction.lua")(S,s)
assert(C.commit(name,{tool="stock_terminal",kind="depot",direction=3,first=depot},nil,true))
local ta,tb,sa,sb=id(11,12),id(17,12),id(12,12),id(16,12)
local function put(i,kind)
  return assert(C.commit(name,{tool="stock_stop_area",kind=kind,direction=0,through=true,first=i},nil,true))
end
-- The first mixed station preserves a truck sign, the second a bus sign.
-- Drivers must choose the matching physical stop at either station.
put(ta,"truck");put(sa,"bus");put(sb,"bus");put(tb,"truck")
local a,b=s.tiles[ta].station,s.tiles[tb].station
assert(a~=b and s.tiles[sa].station==a and s.tiles[sb].station==b)
assert(s.stations[a].tile==ta and s.stations[b].tile==sb)
assert(S.road_stop_has(s.stations[a],"bus") and S.road_stop_has(s.stations[a],"truck"))
assert(s.stations[a].bus_tile==sa and s.stations[a].truck_tile==ta)
local entries={}
for _,offer in ipairs{{"bus","passenger",sa,sb},{"mail_van","mail",ta,tb}} do
  local engine,cargo,first,second=unpack(offer)
  local v=assert(S.purchase(s,name,engine,cargo,nil,depot))
  local profile=s.fleet[v]
  assert(S.add_order(s,name,v,a) and S.add_order(s,name,v,b))
  local route,_,_,frames=S.path(s,{mode="road",tile=depot,owner=name},s.stations[a],"road",name,nil,profile)
  assert(route and route[#route]==first and frames and frames[#frames][4]==first)
  assert(S.toggle(s,name,v))
  entries[#entries+1]={v=v,cargo=cargo,first=first,second=second}
end
local deny=assert(not C.commit(name,{tool="stock_stop_remove",first=ta},nil,true))
assert(s.tiles[ta].station==a and p.cash>0)
local entered={}
for _=1,260 do
  S.daily(s)
  local paid=true
  for _,e in ipairs(entries) do
    local v=s.fleet[e.v]
    local f=v.road_stop_pose
    if f and v.station==a then
      assert(f[4]==e.first)
      entered[e.v]=true
    elseif f and v.station==b then assert(f[4]==e.second) end
    local motion=v.road_motion_frames
    if motion and (v.dest==a or v.dest==b) then
      assert(motion[#motion][4]==(v.dest==a and e.first or e.second))
      if v.dest==a then entered[e.v]=true end
    end
    if v.delivered==0 then paid=false end
  end
  if paid then break end
end
for _,e in ipairs(entries) do
  local v=s.fleet[e.v]
  assert(entered[e.v] and v.delivered>0 and v.last_fare.amount>0,e.cargo)
  assert(v.last_fare.tile==e.first or v.last_fare.tile==e.second)
  assert(v.last_board.tile==e.first or v.last_board.tile==e.second)
end
assert(s.stations[a].passenger_rating_state and s.stations[a].mail_rating_state)
print("PASS paid bus and Mail van enter different physical stops at the same two station IDs; orders protect the last truck platform")
