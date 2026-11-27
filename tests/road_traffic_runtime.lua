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

-- The temporary neighbor array must not leak records from an earlier
-- query or retain a vehicle that moved between signed spatial cells.
do
  local W=U.traffic_world(S)
  local a,b,c=moving(1),moving(2),moving(3)
  W.put(a,{-8,25,5,100,1})
  W.put(b,{-2,25,5,101,1})
  W.put(c,{5,25,5,102,1})
  local clock={}
  assert(W.find(a,clock,-8,25,5)==b and clock.blocked_ctr==1)
  W.put(b,{16,25,5,103,1})
  assert(not W.find(a,clock,-8,25,5) and clock.blocked_ctr==0)
  assert(W.find(c,clock,11,25,5)==b and clock.blocked_ctr==1)
  W.erase(b);W.put(b,{14,25,5,103,1})
  assert(W.find(c,clock,11,25,5)==b and clock.blocked_ctr==2)
  assert(not W.find(c,{reverse_ctr=1,blocked_ctr=30},11,25,5))
end

-- Actual stock height query: a live tick can reuse one surface without
-- losing sub-tile inclination. A fresh tick sees new ground, and spans
-- never substitute a previously cached terrain or deck height.
do
  local Sim=dofile(root.."sim.lua")
  local Terrain=dofile(root.."openttd/terrain.lua")
  Sim.W,Sim.H=8,8
  local s={tiles={},stock_road_bridges={},stock_road_tunnels={}}
  local id=Sim.id(4,4)
  s.tiles[id]={build="road",road_bits=10,h=2}
  s.corner_grid=Terrain.new(8,8,function(x) return x>=5 and 3 or 2 end)
  local height=Sim.stock_road_frame_z
  local frames={{64,67,5,id},{76,67,5,id},{70,67,5,id}}
  local old={}
  for _,f in ipairs(frames) do assert(height(s,f,old)==height(s,f)) end
  assert(type(old[id])=="table" and height(s,frames[1])~=height(s,frames[2]))
  s.corner_grid=Terrain.new(8,8,function() return 7 end)
  local fresh={}
  assert(height(s,frames[1],fresh)==56 and height(s,frames[2],fresh)==56)
  assert(fresh[id]==56,"flat ordinary road stored once per scope")
  s.stock_road_bridges[1]={deck=9,middle_by_tile={[id]=true}}
  local bridge={64,67,5,id,[10]=1}
  assert(height(s,bridge,fresh)==72)
  s.stock_road_bridges[1].deck=11
  assert(height(s,bridge,fresh)==88)
  s.stock_road_tunnels[1]={base=4}
  assert(height(s,{64,67,5,id,[14]=1},fresh)==32)
  assert(height(s,frames[1],fresh)==56)
end
print("PASS signed occupancy cells and scratch reuse; exact intra-tick grade, fresh terrain, and live span elevations")

-- Exercise same-tile updates across all opposite-lane transitions. An
-- ordinary road update must not spuriously register or retain a portal.
do
  local W=U.traffic_world(S)
  local a,b=moving(1),moving(2)
  W.put(a,{50,25,5,103,1});assert(not W.exposed())
  W.put(a,{51,25,5,103,1},true);assert(W.exposed())
  W.put(b,{52,25,5,103,1},true);assert(W.exposed())
  W.put(a,{53,25,5,103,1});assert(W.exposed())
  W.put(b,{54,25,5,103,1},false);assert(not W.exposed())
  assert(a.stock_tile==103 and b.stock_tile==103 and #W.stock_vehicles_at(103)==2)
  W.put(a,span(80,105,1,5,8,true),true)
  W.put(a,{130,25,5,108,1},true)
  W.put(a,{131,25,5,108,1},true)
  assert(a.stock_tile==108 and not a.opposite_portal and #W.stock_vehicles_at(103)==1)
  assert(W.exposed() and #W.stock_vehicles_at(108)==1)
  W.erase(a);assert(not W.exposed() and #W.stock_vehicles_at(108)==0)
end
print("PASS ordinary same-tile and span-exit lane updates preserve the occupancy buckets")

-- The rolling board retains hard occupancy only for ordinary records;
-- a new tick recomputes bay claims and grades and drops borrowed trams
-- before they are seeded again, even inside a shared bridge or tunnel.
do
  local bay=true
  local function grade(s,f,h)
    if not h then return s.alt end
    h[f[4]]=h[f[4]] or s.alt
    return h[f[4]]
  end
  local B=dofile(root.."road_speed_runtime.lua")(Speed,Prox,grade,
    function() return bay end,function() return false end,nil,nil,nil,nil,nil,nil,xy)
  local w={alt=8,stock_road_bridges=S.stock_road_bridges,stock_road_tunnels=S.stock_road_tunnels}
  local W=B.traffic_world(w,true)
  local coach,tram=moving(1),moving(37)
  tram.companion=true
  local same=span(86,105,1,5,8,true)
  W.put(coach,span(81,105,1,5,8,true))
  W.put(tram,same,true)
  assert(W.exposed() and W.bay(105)==1)
  assert(W.find(coach,{},82,25,5)==tram and #W.stock_vehicles_at(103)==2)
  w.alt=16;bay=false
  W.begin_tick()
  W.put(coach,span(81,105,1,5,8,true)) -- same coordinates and membership, new ground
  assert(not W.exposed() and not W.bay(105) and coach.z==16)
  assert(not W.find(coach,{},82,25,5) and #W.stock_vehicles_at(103)==1)
  assert(#W.vehicles_at(105)==1)
  W.erase(coach)
  assert(#W.vehicles_at(105)==0 and #W.stock_vehicles_at(103)==0)
end
print("PASS rolling road buckets retain ordinary vehicles and refresh current grade, bay and borrowed identities")

-- A single stock budget can consume two pixels before another vehicle
-- runs. A held crossing must not commit the second pixel or leak the
-- previous vehicle's frame context when its neighbor runs.
do
  local crossing_calls=0
  local function crossing(_,_,from,to,_,commit)
    assert(from==2 and to==3)
    crossing_calls=crossing_calls+1
    if crossing_calls==1 then return false end
    return commit()
  end
  local B=dofile(root.."road_speed_runtime.lua")(Speed,Prox,function() return 0 end,
    function() return false end,function() return false end,nil,crossing)
  local a,b=bus(1,30,38,41),bus(2,30,38,73)
  local w={fleet={a,b}}
  for _,v in ipairs(w.fleet) do
    v.running=true
    v.road_speed_state={index=1,speed=20,subspeed=0,progress=400,heading=5,ticks=0}
  end
  local noop=function() end
  local function tick(n)
    return B.live_day(w,function(step) step(n) end,
      {economy=function() return {} end,before=noop,arrive=noop,age=noop})
  end
  local _,traces=tick(1)
  assert(crossing_calls==2)
  assert(frame(a)[1]==31 and a.road_speed_state.waiting=="crossing" and a.road_speed_state.speed==0)
  assert(frame(b)[1]==32 and not b.road_speed_state.waiting and b.road_speed_state.speed==21)
  assert(traces[1].frames[2]==frame(a) and traces[2].frames[2]==frame(b))
  a.road_speed_state.progress=192
  tick(2)
  assert(crossing_calls==3 and frame(a)[1]==32 and not a.road_speed_state.waiting)
end
print("PASS mixed two-pixel movement budgets and blocked crossing transactions keep exact vehicle context")
