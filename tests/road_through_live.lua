-- Real parked stock bus contributes length only in its own running direction.
local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.corner_grid=T.new(S.W,S.H,function()return 0 end)
for _,t in ipairs(s.tiles) do
  t.build,t.owner,t.road_town,t.road_bits,t.house,t.wood,t.site,t.source_house=nil,nil,nil,nil,nil,nil,nil,nil
  t.terrain,t.h="grass",0
end
local at=S.id;local owner="Through QA"
s.sites[1].tile=at(10,10);s.sites[2].tile=at(18,10)
local left,right,through,depot=at(9,12),at(18,12),at(13,12),at(10,13)
local function build(tool,list)
  local ok,why=S.build(s,owner,tool,list);assert(ok,why)
end
for _,ends in ipairs({{left,right},{at(11,12),at(11,15)},{at(11,15),at(15,15)},{at(15,15),at(15,12)}}) do
  build("road",S.line(ends[1],ends[2]))
end
build("road_station",{left,right,through})
build("road_depot",{depot})
assert(s.tiles[through].stop_axis==10)
local function station(i) return s.stations[s.tiles[i].station] end
local function query(a,b)
  local v={engine="bus",cargo="passenger"}
  local route,td,cost=S.path(s,station(a),station(b),"road",owner,nil,v)
  assert(route and td and cost)
  local direct=false
  for _,id in ipairs(route) do if id==through then direct=true end end
  return direct,cost
end
local a,empty=query(left,right)
local b,inbound=query(right,left)
assert(a and b)
local id=assert(S.purchase(s,owner,"bus","passenger",nil,depot))
assert(S.add_order(s,owner,id,station(through).id,"full"))
assert(S.add_order(s,owner,id,station(right).id,"normal"))
local ok,why=S.toggle(s,owner,id);assert(ok,why)
for _=1,30 do
  S.daily(s)
  if s.fleet[id].load_state and s.fleet[id].station==station(through).id then break end
end
local front=s.fleet[id]
assert(front.station==station(through).id and front.load_state and front.load_state.full and front.units==0)
local f=assert(S.road_motion_frame(s,front))
assert(f[4]==through and math.floor(f[3]/2)==2 and f[6]>=64 and f[6]<80)
local live=dofile(root.."road_occupancy_view.lua")(S,s)
assert(live.drive_length(through,2)==8 and live.drive_length(through,0)==0)
local forward,detour=query(left,right)
local backward,routed_back=query(right,left)
assert(not forward and backward and detour==empty+84 and routed_back==inbound,
  ("incoming baseline %s/%s, outgoing %s/%s, choices %s/%s"):format(empty,inbound,detour,routed_back,tostring(forward),tostring(backward)))
-- Parked actor pose is authoritative; dropping transient views changes nothing.
local function copy(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
s=copy(s)
assert(not query(left,right) and query(right,left))
print(("PASS: actual parked through bus changes fresh direction-only YAPF choice %d -> %d; other direction stays %d"):format(empty,detour,inbound))
