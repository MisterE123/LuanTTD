local root="mods/bayline/"
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
