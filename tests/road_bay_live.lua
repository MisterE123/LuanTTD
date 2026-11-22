-- Real source poses from a purchased depot fleet, no injected clocks.
local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
dofile(root.."town_layout.lua")(S,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(S,T,s)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_bay_build=true,true,true,true,true
local a,b,d=S.id(11,12),S.id(17,12),S.id(12,13)
local owner="Test"
local function build(tool,ids)
  local ok,why=S.build(s,owner,tool,ids);assert(ok,why)
end
build("road",S.line(a,b))
build("road_bay_pair",{a,b})
build("road_depot",{d})
local sa,sb=s.tiles[a].station,s.tiles[b].station
assert(S.road_bay_status(s,a) and not S.road_bay_status(s,a).first)
assert(not S.purchase(s,owner,"bus","passenger",sa))
for n=1,3 do
  local id,why=S.purchase(s,owner,"bus","passenger",nil,d)
  assert(id==n,why)
  assert(S.add_order(s,owner,id,sa,"full"))
  assert(S.add_order(s,owner,id,sb))
  local ok,msg=S.toggle(s,owner,id);assert(ok,msg)
end
local function copy(o,seen)
  if type(o)~="table" then return o end
  seen=seen or {}
  if seen[o] then return seen[o] end
  local z={};seen[o]=z
  for k,v in pairs(o) do z[k]=copy(v,seen) end
  return z
end
local double,queue,reload,paid=false,false,false,false
for _=1,130 do
  S.daily(s)
  local one,two,three=s.fleet[1],s.fleet[2],s.fleet[3]
  local bays=S.road_bay_status(s,a)
  if one.station==sa and two.station==sa and not double then
    assert(one.road_bay_claim.bay==0 and two.road_bay_claim.bay==1)
    local p,q=one.road_stop_pose,two.road_stop_pose
    assert(p[4]==q[4] and p[3]==q[3] and math.abs(p[1]-q[1])+math.abs(p[2]-q[2])==4)
    assert(bays.first and bays.second and not bays.entrance)
    double=true
  end
  if double and not reload and three.road_speed_state and three.road_speed_state.waiting=="bay" then
    queue=true
    assert(three.road_bay_claim==nil and S.position(s,three)~=a)
    assert(not S.plan(s,owner,"clear",{a}))
    s=copy(s)
    local saved=S.road_bay_status(s,a)
    assert(saved.first and saved.second and not saved.entrance)
    reload=true
  end
  if reload and s.fleet[3].last_road_arrival_tick and s.companies[owner].paid_units>0 then paid=true;break end
end
assert(double and queue and reload and paid,"two real bays, third wait, persistence and released passenger route must all occur")
print(("PASS: two parked stock passenger buses four pixels apart; third waited across snapshot, then arrived; %d riders paid")
  :format(s.companies[owner].paid_units))
