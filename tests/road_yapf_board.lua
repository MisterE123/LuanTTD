local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local F=dofile(root.."openttd/yapf_road_follow.lua")
local C=dofile(root.."openttd/yapf_road_cost.lua")(F)
local Search=dofile(root.."openttd/yapf_road_search.lua")(F,C)
local make_board=dofile(root.."road_yapf_board.lua")
local s=Sim.new(1751)
for _,tile in ipairs(s.tiles) do
  tile.wood=nil;tile.house=nil;tile.site=nil;tile.h=0;tile.terrain="grass"
end
local function at(x,z) return Sim.id(x+3,z+6) end
local function fill(x,z,bits,build,owner)
  local t=s.tiles[at(x,z)]
  t.build,t.road_bits,t.owner=build or "road",bits,owner or "A"
  return t
end
local depot=fill(0,0,2,"road_depot")
depot.depot_dir=2
fill(1,0,14)
fill(2,0,10)
local mid=fill(3,0,10,nil,"B")
fill(4,0,10)
fill(5,0,14)
fill(1,1,3)
for x=2,4 do fill(x,1,10) end
fill(5,1,9)
local target=fill(6,0,8,"road_station")
target.station=1
s.stations[1]={id=1,tile=at(6,0),mode="road"}
local bus={tile=at(0,0),display_max_speed=112,bus=true,owner="A"}
local sw=F.direction_trackdir(F.SW)
local function route()
  local B=make_board(Sim,s,F)
  local d=C.destination(B,bus,{kind="station",station=1})
  local ok,best=Search.find(B,bus,bus.tile,2^sw,d)
  assert(ok)
  local course=Search.trace(B,bus,d,best)
  return B,best.cost,course
end
local B,cost,course=route()
assert(cost==600 and #course==7 and course[4].tile==at(3,0))
assert(B.tile(at(6,0)).kind=="bay_stop" and B.tile(at(6,0)).dir==F.NE)
local reverse=F.follow(B,bus,at(6,0),sw)
assert(reverse.ok and reverse.reversed and reverse.tile==at(6,0) and reverse.trackdirs==1)
assert(B.adjacent(at(0,0),F.SW)==at(1,0))
assert(B.edge_available(at(2,0),at(3,0),F.SW))
assert(B.center_z(at(0,0))==0 and B.tile(nil)==nil)
do
  local height=Sim.road_center_z
  local calls=0
  Sim.road_center_z=function(...)
    calls=calls+1
    return height(...)
  end
  local road=at(2,0)
  local one=make_board(Sim,s,F)
  assert(one.center_z(road)==0 and one.center_z(road)==0 and calls==1)
  s.tiles[road].h=2
  local next_search=make_board(Sim,s,F)
  assert(next_search.center_z(road)==16 and calls==2)
  s.tiles[road].h=0
  Sim.road_center_z=height
end
mid.build,mid.station,mid.stop_axis="road_station",2,10
s.stations[2]={id=2,tile=at(3,0),mode="road"}
B,cost,course=route()
assert(cost==1084 and #course==9 and course[3].tile==at(1,1))
local queue=make_board(Sim,s,F,{drive_length=function(tile,dir)
  assert(tile==at(3,0) and dir==F.SW);return 7
end,bay_taken=function(tile,bay) return tile==at(6,0) and bay==1 end})
assert(C.one_tile(queue,at(3,0),sw)==1250)
assert(C.one_tile(queue,at(6,0),sw)==850)
print("PASS: source YAPF on LuanTTD tiles with depot, actual bay, through stop and foreign road")

local Motion=dofile(root.."openttd/road_motion.lua")(dofile(root.."openttd/road_motion_data.lua"))
local Leg=dofile(root.."road_motion_leg.lua")
local Presentation=dofile(root.."road_motion_presentation.lua")(dofile(root.."road_lanes.lua"))
-- Compiling every pixel still reads each chosen physical part once.
-- A changed board must be sampled fresh, never inherit route descriptors.
local descriptor_reads=0
local describe=B.tile
function B.tile(id) descriptor_reads=descriptor_reads+1;return describe(id) end
local frames=assert(Leg(Motion,F,B).compile(course))
assert(descriptor_reads==#course)
B.tile=describe
-- Optionally pass the previous road_motion_leg.lua to benchmark exactly
-- the same selected detour and two bay ends in a local LuaJIT.
local baseline=arg and arg[1]
if baseline then
  local file=assert(io.open(baseline,"rb"))
  local old=assert(loadstring(file:read("*a"),"@"..root.."road_motion_leg.lua"))()
  file:close()
  local runs=16384
  local function bench(compile)
    local reads=0
    local probe=setmetatable({tile=function(id) reads=reads+1;return B.tile(id) end},{__index=B})
    local motion=compile(Motion,F,probe)
    local results={}
    collectgarbage("collect")
    local now=os.clock()
    for i=1,runs do
      local bay=i%2
      results[bay]=assert(motion.compile(course,nil,{arrival_bay=bay}))
    end
    return os.clock()-now,reads,results
  end
  for batch=1,4 do
    local at,ar,af,bt,br,bf
    if batch%2==0 then bt,br,bf=bench(Leg);at,ar,af=bench(old)
    else at,ar,af=bench(old);bt,br,bf=bench(Leg) end
    for bay=0,1 do
      assert(#af[bay]==#bf[bay])
      for i,a in ipairs(af[bay]) do for j=1,16 do assert(a[j]==bf[bay][i][j]) end end
    end
    assert(br<ar and br==runs*#course)
    print(("MOTION COMPILE %d CPU=%.3f/%.3f s reads=%d/%d"):format(batch,at,bt,ar,br))
  end
end
local target_tile=at(6,0)
assert(frames[1][4]==at(0,0) and frames[#frames][4]==target_tile)
local rotates=0
for i=2,#frames do
  local a,b=frames[i-1],frames[i]
  if a[1]==b[1] and a[2]==b[2] then
    assert((a[3]-b[3])%8==1 or (b[3]-a[3])%8==1)
    rotates=rotates+1
  end
  local dx,dz=math.abs(b[1]-a[1]),math.abs(b[2]-a[2])
  assert(dx<=1 and dz<=1,("position jump at frame %d: %s %s"):format(i,dx,dz))
end
assert(rotates>=8)
local t=course[#course].td
local bx,by=B.xy(target_tile)
local _,sx,sy=Motion.sample(32+t,1,Motion.bay_stop_frame(32+t,1))
assert(frames[#frames][1]==bx*16+sx and frames[#frames][2]==by*16+sy)
local leg=assert(Leg(Motion,F,B).compile({
  {tile=target_tile,td=F.direction_trackdir(F.NE)},
  {tile=at(5,0),td=F.direction_trackdir(F.NE)},
  {tile=at(4,0),td=F.direction_trackdir(F.NE)},
  {tile=at(3,0),td=F.direction_trackdir(F.NE)},
}))
assert(leg[1][1]==frames[#frames][1] and leg[1][2]==frames[#frames][2]
  and leg[1][3]==frames[#frames][3], "arrival/departure jump at bay")
target.road_stop_pair=true
local router=dofile(root.."road_yapf_route.lua")(Sim,F,C,Search,make_board,Motion,Leg)
local route,same_td,_,first,branch=router.route(s,{tile=at(0,0)},s.stations[1],"A",{cargo="passenger",engine="bus"})
assert(route and same_td==t and branch.tile==target_tile and first[branch.first][9])
local p,q=first[#first],branch.second[#branch.second]
assert(p[6]+2==q[6] and p[4]==q[4] and p[3]==q[3])
assert(math.abs(p[1]-q[1])+math.abs(p[2]-q[2])==4, "stock bays should be four source pixels apart")
local _,_,_,second_depart=router.route(s,s.stations[1],s.stations[2],"A",
  {cargo="passenger",engine="bus",road_stop_pose=q})
assert(second_depart and second_depart[1][1]==q[1] and second_depart[1][2]==q[2]
  and second_depart[1][3]==q[3] and second_depart[1][6]==q[6], "second bay departure must retain actual boarded pose")
local _,lx=Presentation.xy(48,5,1)
local _,rx=Presentation.xy(48,9,1)
assert(math.abs(rx-lx-.310)<1e-7)
assert(rx-lx>.26796 and .155+.26796*.5<.3125)
assert(math.abs(Presentation.yaw(3))<1e-9)
assert(math.abs(Presentation.yaw(5)-math.pi/2)<1e-9)
assert(math.abs(Presentation.yaw(1)+math.pi/2)<1e-9)
local x0,z0,ang=Presentation.pose({15,0,7},{15,0,0},.5)
assert(math.abs(ang-4.5*math.pi/4)<1e-9)
-- Inside corner, carried initial heading SE. Seven new positions, two
-- distinct stationary rotations, then the edge marker: ten steps.
local v={x=5,y=0,direction=3,state=2,frame=0}
local n=0
for i=1,10 do
  local k,x,y,d,f=Motion.step(v,0)
  if i==10 then
    assert(k=="next_tile" and x==F.NE and v.direction==1 and n==2)
  else
    if k=="rotate" then n=n+1;assert(x==v.x and y==v.y and f==v.frame) end
    v.x,v.y,v.direction,v.frame=x,y,d,f
  end
end
print("PASS: source poses for depot, detour, bay turnaround, opposing lanes and inner corner")

-- The live board caches geometry across expansion and trace only within
-- one read-only traversal. A new search must see the edited infrastructure.
do
  local Terrain=dofile(root.."openttd/terrain.lua")
  local world=Sim.new(1751)
  world.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 2 end)
  local a,b=at(2,2),at(3,2)
  world.tiles[a].build,world.tiles[a].road_bits="road",10
  world.tiles[b].build,world.tiles[b].road_bits="road",10
  local original=Sim.road_surface
  local calls=0
  Sim.road_surface=function(...) calls=calls+1;return original(...) end
  local board=make_board(Sim,world,F)
  assert(board.edge_available(a,b,F.SW) and board.edge_available(a,b,F.SW))
  assert(not board.edge_available(a,b+1,F.SW),"the same direction must not admit a different neighbor")
  assert(board.edge_available(b,a,F.NE) and board.center_z(a)==16 and board.center_z(b)==16 and calls==2)
  world.tiles[b].road_bits=2
  assert(not make_board(Sim,world,F).edge_available(a,b,F.SW),"new traversal must see the missing entrance edge")
  world.tiles[b].road_bits=10
  assert(make_board(Sim,world,F).edge_available(a,b,F.SW),"new traversal must not inherit a cached refusal")
  Sim.road_surface=original
end
print("PASS read-only traversal shares real surface profiles and fresh searches see edits")
