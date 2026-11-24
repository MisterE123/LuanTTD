local root="mods/luanttd_core/"
local Speed=dofile(root.."openttd/road_speed.lua")
local Prox=dofile(root.."openttd/road_proximity.lua")
local R=dofile(root.."road_speed_runtime.lua")(Speed,Prox,function() return 0 end,
  function(s,id) return s.bays[id] end,function(s,id) return s.depots[id] end)
local function line(x0,x1,y,tile_override)
  local seq={}
  local forward=x1>x0
  for x=x0,x1,forward and 1 or -1 do
    local tile=tile_override and tile_override(x) or math.floor(x/16)+1
    seq[#seq+1]={x,y,forward and 5 or 1,tile,1}
  end
  return seq
end
local function bus(id,x0,x1,y,override)
  return {id=id,engine="bus",route={1,2,3,4},progress=1,road_motion_frames=line(x0,x1,y,override)}
end
local function frame(v)
  return v.road_motion_frames[v.road_speed_state.index]
end
local s={fleet={},bays={},depots={}}
local moving=bus(1,26,120,41)
local parked={id=2,engine="bus",road_stop_pose={51,41,5,4}}
s.fleet={moving,parked}
for _=1,3 do R.day(s,{1}) end
assert(frame(moving)[1] < 51 and moving.road_speed_state.waiting=="road" and moving.road_speed_state.speed==0)
local before=frame(moving)[1]
s.fleet[2]=nil
R.day(s,{1})
assert(frame(moving)[1]>before and not moving.road_speed_state.waiting)
local o1,o2=bus(1,26,110,41),bus(2,58,18,37)
s.fleet={o1,o2}
for _=1,3 do R.day(s,{1,2}) end
assert(frame(o1)[1]>frame(o2)[1] and not o1.road_speed_state.waiting and not o2.road_speed_state.waiting)
local a,b=bus(1,18,88,41),bus(2,18,88,41)
s.fleet={a,b};s.depots[2]=true
local _,tls=R.day(s,{1,2})
assert(tls[2].cursors[1]==0 and tls[1].cursors[2]>0)
local release
for i,frame_idx in ipairs(tls[2].cursors) do
  if frame_idx>0 then release=i;break end
end
assert(release and release>2 and tls[1].cursors[release]>8)
assert(frame(a)[1]>frame(b)[1])
local approach=bus(1,26,88,41)
s.fleet={approach,{id=2,engine="bus",road_stop_pose={53,45,1,4}}};s.depots={};s.bays[4]=true
for _=1,3 do R.day(s,{1}) end
assert(frame(approach)[4]==3 and approach.road_speed_state.waiting=="bay")
s.fleet[2]=nil
R.day(s,{1})
assert(frame(approach)[4]==4)
print("PASS: following bus stops and resumes, opposite lanes, depot separation, exclusive bay entrance")

-- Wormhole candidates follow the logical tiles as the visible pixel
-- crosses terrain not owned by this span. This also admits a future
-- tram record to the exact same classifier as any other road vehicle.
local function xy(id) return id%100,math.floor(id/100) end
local U=dofile(root.."road_speed_runtime.lua")(Speed,Prox,function(s,f)return f.alt or 8 end,
  function() return false end,function() return false end,nil,nil,nil,nil,nil,nil,xy)
local function portal(start,finish)
  return {start=start,["end"]=finish,head={inside_direction=2},tail={inside_direction=0}}
end
local S={stock_road_bridges={[1]=portal(103,108),[2]=portal(104,109)},
  stock_road_tunnels={[1]=portal(103,108)}}
local function moving(id)
  return {id=id,first=id,type="road"}
end
local function span(x,id,span_id,d,alt,tunnel)
  return {x,25,d,id,1,255,nil,nil,nil,not tunnel and span_id or nil,nil,true,tunnel,
    tunnel and span_id or nil,alt=alt}
end
for _,tunnel in ipairs({false,true}) do
  local W=U.traffic_world(S)
  local a,b,c,traffic=moving(1),moving(2),moving(3),moving(4)
  local same=span(86,105,1,5,8,tunnel)
  W.put(a,{51,25,5,103,1})
  W.put(a,span(81,105,1,5,8,tunnel)) -- entering still uses the old logical tile
  W.put(b,same)
  W.put(c,span(82,105,2,5,8,false)) -- adjacent pixels, not the same pair of portals
  W.put(traffic,{83,25,5,105,1,0,alt=8}) -- same height, not on the wormhole's logical portals
  assert(a.stock_tile==103 and a.opposite_portal==108 and a.stock_x==3)
  assert(W.find(a,{},82,25,5)==b)
  assert(#W.stock_vehicles_at(103)==2 and #W.stock_vehicles_at(105)==1)
  assert(W.find(traffic,{},85,25,5)==nil,"ground candidate scan must not see an interior at the wrong logical tile")
  W.erase(b)
  assert(W.find(a,{},82,25,5)==nil and #W.stock_vehicles_at(103)==1)
  W.put(a,{131,25,5,108,1})
  assert(#W.stock_vehicles_at(103)==0 and #W.stock_vehicles_at(108)==1)
  W.put(a,span(132,108,1,1,8,tunnel))
  assert(a.stock_tile==108 and a.opposite_portal==103)
  W.erase(a)
  assert(#W.stock_vehicles_at(108)==0)
end
do
  local W=U.traffic_world(S)
  local a,b=moving(1),moving(2)
  W.put(a,{10,25,5,100,1})
  W.put(b,{18,25,5,101,1})
  assert(W.find(a,{},11,25,5)==b,"seven pixels away in the adjacent tile")
end
print("PASS: shared stock portal buckets, physical-vs-logical positions, unrelated-span separation, full RC1 proximity window")
