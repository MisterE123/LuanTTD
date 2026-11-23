-- SPDX-License-Identifier: GPL-2.0-only
-- Repeat the focus fixture's blocked commute in all four stock directions.
local path="mods/luanttd_core/"
local Sim=dofile(path.."sim.lua")
local Terrain=dofile(path.."openttd/terrain.lua")
local Follow=dofile(path.."openttd/yapf_road_follow.lua")
local Move=dofile(path.."openttd/road_motion.lua")(dofile(path.."openttd/road_motion_data.lua"))
Sim.W,Sim.H=64,64
local s=Sim.new(1751)
s.tiles,s.stations={},{}
s.corner_grid=Terrain.new(64,64,function()return 1 end)
s.road_economy=true
for i=1,64*64 do s.tiles[i]={h=1,terrain="grass"} end
local owner="A"
local expected={[0]=6,7,14,15}
local function along(from,n,d)
  if n<0 then n,d=-n,Follow.reverse_direction(d) end
  for i=1,n do from=Sim.adjacent(from,4-d) end
  return from
end
for d=0,3 do
  local center=Sim.id(10+d*7,10+d*5)
  local a,b=center,along(center,-2,d)
  local turn,last=along(center,1,d),along(center,2,d)
  local rev=Follow.reverse_direction(d)
  local bits=2^(3-d)+2^(3-rev)
  for i=-2,2 do
    s.tiles[along(center,i,d)]={h=1,terrain="grass",build="road",road_bits=i==2 and 2^(3-rev) or bits,owner=owner}
  end
  local from,to
  for i,id in ipairs({a,b}) do
    local v={id=i,tile=id,mode="road",owner=owner,stop_type="bus"}
    s.stations[i]=v;s.tiles[id].station=i;s.tiles[id].stop_axis=bits;s.tiles[id].build="road_station"
    if i==1 then from=v else to=v end
  end
  local v={owner=owner,engine="bus",cargo="passenger",road_arrival_td=Follow.direction_trackdir(d)}
  local trail,td,_,motion=Sim.path(s,from,to,"road",owner,nil,v)
  assert(trail and trail[1]==a and trail[2]==turn and trail[#trail]==b and td==Follow.direction_trackdir(rev))
  assert(motion and motion[1][4]==a and motion[#motion][4]==b)
  assert(motion[1][15]==Move.DRIVE_THROUGH_STOP and motion[#motion][15]==Move.DRIVE_THROUGH_STOP)
  local state,n,previous=expected[d],0
  for _,frame in ipairs(motion) do
    assert(frame[4]~=last)
    if frame[6]==state then
      assert(frame[4]==turn and not frame[9])
      n=n+1
    end
    if previous then
      assert(math.abs(frame[1]-previous[1])<=1 and math.abs(frame[2]-previous[2])<=1)
    end
    previous=frame
  end
  assert(n>=4,"The selected in-tile turn never entered the real RC1 movement row")
  s.tiles[turn].road_disallowed=1
  local _,_,_,refused=Sim.path(s,from,to,"road",owner,nil,v)
  assert(not refused,"No road reversal is allowed on signed one-way pavement")
end
print("PASS four exact stock terminal turns keep positions continuous and refuse signed reversals")
