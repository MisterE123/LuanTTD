-- SPDX-License-Identifier: GPL-2.0-only
-- A live bus uses an unordered depot to reverse without changing orders.
local path="mods/luanttd_core/"
local function m(p)return dofile(path..p..".lua") end
local Sim,T,F=m("sim"),m("openttd/terrain"),m("openttd/yapf_road_follow")
local Move=m("openttd/road_motion")(m("openttd/road_motion_data"))
local runtime=m("road_speed_runtime")(m("openttd/road_speed"),m("openttd/road_proximity"),function()return 1 end,
  function()return false end,function(s,i)return s.tiles[i].build=="road_depot" end)
local P=m("packed_campaign")
Sim.W,Sim.H=64,64
local s=Sim.new(1751)
s.tiles,s.stations,s.fleet={},{},{}
s.corner_grid=T.new(64,64,function()return 1 end)
s.road_economy=true
for i=1,64*64 do s.tiles[i]={h=1,terrain="grass"} end
local function id(x)return Sim.id(x,12) end
for x=25,34 do
  s.tiles[id(x)]={h=1,terrain="grass",build="road",road_bits=10,owner="A"}
end
local depot=id(25)
s.tiles[depot]={h=1,terrain="grass",build="road_depot",road_bits=2,depot_dir=2,owner="A"}
for i,x in ipairs({27,33}) do
  local t=s.tiles[id(x)]
  t.build,t.station,t.stop_axis="road_station",i,10
  s.stations[i]={id=i,tile=id(x),mode="road",owner="A",stop_type="bus"}
end
local v={id=1,owner="A",engine="bus",cargo="passenger",running=true,progress=1,
  road_arrival_td=F.direction_trackdir(0),orders={{station=1},{station=2}}}
local route,td,_,frames=Sim.path(s,s.stations[1],s.stations[2],"road","A",nil,v)
assert(route and td==8 and frames and frames[#frames][4]==s.stations[2].tile)
local hid
for i,f in ipairs(frames) do
  if f[16] then
    assert(not hid and f[4]==depot and f[6]==0 and f[15]==Move.DEPOT_STOP)
    local out=frames[i+1]
    assert(out[4]==depot and out[6]==8 and out[15]==Move.DEPOT_START and out[3]==5)
    hid=i
  end
end
assert(hid)
v.route,v.road_motion_frames=route,frames;s.fleet[1]=v
local hidden,reloaded,services,completed=0,false,0,false
local hooks={economy=function()return{}end,before=function()end,age=function()end,
  exited=function(vehicle)
    assert(vehicle==s.fleet[1] and not vehicle.depot)
    assert(vehicle.road_speed_state.speed==0)
    services=services+1
  end,
  arrive=function(vehicle,_,pose)
    assert(pose[4]==s.stations[2].tile and services==1)
    completed=true
    vehicle.route,vehicle.road_motion_frames=nil,nil
    vehicle.road_stop_pose=pose
    return true,false
  end}
for tick=1,1800 do
  local _,vis=runtime.live_day(s,function(fn) fn(tick) end,hooks)
  local vehicle=s.fleet[1]
  if vehicle.road_speed_state.index==hid then
    assert(not vis[1] or vis[1].cursors[2]==0)
    assert(Sim.road_hidden_depot(vehicle) and not Sim.road_motion_frame(s,vehicle))
    hidden=hidden+1
    if not reloaded then
      s=P.decode(P.encode(s));reloaded=true
      local saved=s.fleet[1]
      assert(saved.road_motion_frames[hid][16] and saved.road_speed_state.index==hid and not saved.depot)
    end
  end
  if completed then break end
end
assert(reloaded and completed and hidden>=1 and services==1)
assert(#s.fleet[1].orders==2 and s.fleet[1].orders[2].station==2 and not s.fleet[1].depot)
print("PASS unordered owned depot hides the bus, restores the hidden checkpoint, services once and leaves on its existing orders")
